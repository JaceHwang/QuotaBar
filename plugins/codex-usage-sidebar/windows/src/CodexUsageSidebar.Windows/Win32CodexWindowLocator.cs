#if WINDOWS
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed class Win32CodexWindowLocator : IHostWindowLocator
{
    private readonly IWindowLocatorAcquisition acquisition;
    private readonly object captionCacheGate = new();
    private CaptionCacheEntry? captionCache;

    public Win32CodexWindowLocator() : this(new NativeWindowLocatorAcquisition())
    {
    }

    internal Win32CodexWindowLocator(IWindowLocatorAcquisition acquisition)
    {
        this.acquisition = acquisition;
    }

    public ValueTask<HostWindowSnapshot?> FindAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var foreground = acquisition.ForegroundWindow;
        var candidates = new List<(HostWindowSnapshot Snapshot, double Area)>();
        foreach (var candidate in acquisition.EnumerateCandidates())
        {
            var bounds = WindowsCoordinateSpace.ToPhysicalBounds(
                candidate.Left,
                candidate.Top,
                candidate.Right,
                candidate.Bottom,
                candidate.DpiScale);
            if (bounds.Width < 400 * candidate.DpiScale || bounds.Height < 300 * candidate.DpiScale)
            {
                continue;
            }
            var workArea = acquisition.WorkAreaFor(candidate.Handle);
            var captionBounds = CaptionBoundsFor(candidate.Handle, bounds, candidate.DpiScale);
            candidates.Add((new HostWindowSnapshot(
                candidate.Handle,
                bounds,
                candidate.Handle == foreground,
                candidate.DpiScale,
                candidate.BuildIdentity,
                WorkArea: workArea,
                CaptionBounds: captionBounds),
                bounds.Width * bounds.Height));
        }

        var selected = candidates
            .OrderByDescending(x => x.Snapshot.IsForeground)
            .ThenByDescending(x => x.Area)
            .Select(x => x.Snapshot)
            .FirstOrDefault();
        return ValueTask.FromResult<HostWindowSnapshot?>(selected);
    }

    private RectD? CaptionBoundsFor(IntPtr handle, RectD hostBounds, double dpiScale)
    {
        var key = CaptionCacheKey.For(handle, hostBounds, dpiScale);
        lock (captionCacheGate)
        {
            if (captionCache is { } cached && cached.Key == key)
            {
                return cached.Bounds;
            }
        }

        RectD? bounds;
        try
        {
            var candidates = acquisition.CaptionCandidatesFor(handle);
            bounds = candidates is null
                ? null
                : HostWindowGeometry.TryResolveVerifiedCaptionBounds(hostBounds, candidates, dpiScale);
        }
        catch (ElementNotAvailableException)
        {
            bounds = null;
        }
        catch (InvalidOperationException)
        {
            bounds = null;
        }
        catch (COMException)
        {
            bounds = null;
        }

        lock (captionCacheGate)
        {
            captionCache = new CaptionCacheEntry(key, bounds);
        }
        return bounds;
    }

    private sealed record CaptionCacheEntry(CaptionCacheKey Key, RectD? Bounds);

    private readonly record struct CaptionCacheKey(IntPtr Handle, RectD HostBounds, double DpiScale)
    {
        internal static CaptionCacheKey For(IntPtr handle, RectD hostBounds, double dpiScale) =>
            new(handle, hostBounds, dpiScale);
    }

    internal static string? ExecutablePath(IntPtr handle)
    {
        NativeMethods.GetWindowThreadProcessId(handle, out var processId);
        try
        {
            using var process = Process.GetProcessById(checked((int)processId));
            return process.MainModule?.FileName;
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    private static FileVersionInfo? SafeFileVersionInfo(Process process)
    {
        try
        {
            return process.MainModule?.FileVersionInfo;
        }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    private static string? SafeExecutablePath(Process process)
    {
        try
        {
            return process.MainModule?.FileName;
        }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    private static class NativeMethods
    {
        internal delegate bool EnumWindowsCallback(IntPtr handle, IntPtr parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowVisible(IntPtr handle);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(IntPtr handle, out NativeRect rectangle);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        internal static extern uint GetDpiForWindow(IntPtr handle);

        [DllImport("user32.dll")]
        internal static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        internal int Left;
        internal int Top;
        internal int Right;
        internal int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MonitorInfo
    {
        internal int Size;
        internal NativeRect Monitor;
        internal NativeRect Work;
        internal uint Flags;
    }

    private sealed class NativeWindowLocatorAcquisition : IWindowLocatorAcquisition
    {
        public IntPtr ForegroundWindow => NativeMethods.GetForegroundWindow();

        public IEnumerable<WindowLocatorCandidate> EnumerateCandidates()
        {
            var candidates = new List<WindowLocatorCandidate>();
            NativeMethods.EnumWindows((handle, _) =>
            {
                if (!NativeMethods.IsWindowVisible(handle)
                    || !NativeMethods.GetWindowRect(handle, out var rectangle))
                {
                    return true;
                }
                NativeMethods.GetWindowThreadProcessId(handle, out var processId);
                try
                {
                    using var process = Process.GetProcessById(checked((int)processId));
                    var versionInfo = SafeFileVersionInfo(process);
                    var executablePath = SafeExecutablePath(process);
                    if (!CodexProcessIdentity.IsSupported(
                        process.ProcessName,
                        versionInfo?.ProductName,
                        versionInfo?.CompanyName,
                        executablePath,
                        Path.Combine(
                            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                            "WindowsApps")))
                    {
                        return true;
                    }
                    candidates.Add(new WindowLocatorCandidate(
                        handle,
                        rectangle.Left,
                        rectangle.Top,
                        rectangle.Right,
                        rectangle.Bottom,
                        Math.Max(1, NativeMethods.GetDpiForWindow(handle)) / 96d,
                        versionInfo?.FileVersion ?? "unknown"));
                }
                catch (ArgumentException)
                {
                }
                catch (InvalidOperationException)
                {
                }
                return true;
            }, IntPtr.Zero);
            return candidates;
        }

        public RectD? WorkAreaFor(IntPtr handle)
        {
            var monitor = NativeMethods.MonitorFromWindow(handle, 2);
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            if (monitor == IntPtr.Zero || !NativeMethods.GetMonitorInfo(monitor, ref info)) return null;
            return new RectD(
                info.Work.Left,
                info.Work.Top,
                info.Work.Right - info.Work.Left,
                info.Work.Bottom - info.Work.Top);
        }

        public IReadOnlyList<HostWindowGeometry.CaptionBoundsCandidate>? CaptionCandidatesFor(IntPtr handle)
        {
            var root = AutomationElement.FromHandle(handle);
            if (root is null) return null;
            var condition = new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Pane),
                new PropertyCondition(AutomationElement.ClassNameProperty, "ChromeNodeCaptionButtonContainer"));
            return root.FindAll(TreeScope.Descendants, condition)
                .Cast<AutomationElement>()
                .Select(element => new HostWindowGeometry.CaptionBoundsCandidate(
                    BoundsFor(element),
                    HasVerifiedCaptionButtons(element)))
                .ToArray();
        }

        private static RectD BoundsFor(AutomationElement element)
        {
            var bounds = element.Current.BoundingRectangle;
            return new RectD(bounds.X, bounds.Y, bounds.Width, bounds.Height);
        }

        private static bool HasVerifiedCaptionButtons(AutomationElement container)
        {
            foreach (var automationId in new[] { "view_1", "view_2", "view_3", "view_4" })
            {
                var condition = new AndCondition(
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
                    new PropertyCondition(AutomationElement.AutomationIdProperty, automationId),
                    new PropertyCondition(AutomationElement.ClassNameProperty, "ChromeNodeCaptionButton"));
                if (container.FindAll(TreeScope.Descendants, condition).Count != 1) return false;
            }
            return true;
        }
    }
}

internal interface IWindowLocatorAcquisition
{
    IntPtr ForegroundWindow { get; }
    IEnumerable<WindowLocatorCandidate> EnumerateCandidates();
    RectD? WorkAreaFor(IntPtr handle);
    IReadOnlyList<HostWindowGeometry.CaptionBoundsCandidate>? CaptionCandidatesFor(IntPtr handle);
}

internal sealed record WindowLocatorCandidate(
    IntPtr Handle,
    int Left,
    int Top,
    int Right,
    int Bottom,
    double DpiScale,
    string BuildIdentity);

public sealed class UnverifiedUiaTitlebarScanner : ITitlebarScanner
{
    public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
        ValueTask.FromException<TitlebarSnapshot>(new WindowsDeviceValidationRequiredException(host.BuildIdentity));

    public void Invalidate() { }
}
#endif
