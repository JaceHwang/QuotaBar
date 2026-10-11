using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed record HostWindowSnapshot(
    IntPtr Handle,
    RectD Bounds,
    bool IsForeground,
    double DpiScale,
    string BuildIdentity,
    RectD? WorkArea = null,
    RectD? CaptionBounds = null);

public readonly record struct PointD(double X, double Y);

public static class OverlayPointerPolicy
{
    public static bool IsInside(PointD point, RectD bounds) =>
        double.IsFinite(point.X)
        && double.IsFinite(point.Y)
        && double.IsFinite(bounds.X)
        && double.IsFinite(bounds.Y)
        && double.IsFinite(bounds.Width)
        && double.IsFinite(bounds.Height)
        && bounds.Width > 0
        && bounds.Height > 0
        && point.X >= bounds.X
        && point.X < bounds.Right
        && point.Y >= bounds.Y
        && point.Y < bounds.Bottom;
}

public enum OverlayThemeKind { Light, Dark, HighContrast }

public static class OverlayThemePolicy
{
    public static OverlayThemeKind Resolve(byte red, byte green, byte blue, bool highContrast)
    {
        if (highContrast) return OverlayThemeKind.HighContrast;
        var luminance = ((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) / 255;
        return luminance < 0.5 ? OverlayThemeKind.Dark : OverlayThemeKind.Light;
    }
}

public sealed record TitlebarSnapshot(
    double PreferredAnchorTrailingEdge,
    IReadOnlyList<RectD> Obstacles,
    RectD ToolbarBounds = default,
    RectD OpenLocationBounds = default,
    RectD TitleBounds = default,
    RectD RightToolbarBounds = default,
    IReadOnlyList<RectD>? ValidatedRightObstacles = null,
    IReadOnlyList<RectD>? InteractiveToolbarObstacles = null)
{
    public IReadOnlyList<RectD> RightObstacles =>
        ValidatedRightObstacles ?? Array.Empty<RectD>();

    public IReadOnlyList<RectD> AllInteractiveObstacles =>
        InteractiveToolbarObstacles ?? Obstacles.Concat(RightObstacles).ToArray();
}

public sealed record OverlayPresentation(
    IntPtr OwnerHandle,
    double DpiScale,
    DisplayLanguage Language,
    AllowanceSnapshot Snapshot,
    PlacementResult Placement,
    SnapshotFreshness Freshness,
    PointD ThemeProbePoint,
    TokenUsageSnapshot? TokenUsage = null,
    AccountIdentity? Account = null,
    string Version = "",
    PlacementMode Mode = PlacementMode.Titlebar,
    SafeDockSize SafeDockSize = SafeDockSize.Standard,
    SafeDockPlacementRequest? SafeDockRequest = null,
    bool SwitchToFree = false);

public enum PlacementMode
{
    Titlebar,
    SafeDock,
}

public enum HostRuntimeState
{
    WaitingForCodex,
    DeviceValidationRequired,
    Hidden,
    Visible,
}

public sealed class WindowsDeviceValidationRequiredException : Exception
{
    public WindowsDeviceValidationRequiredException(string buildIdentity)
        : base($"Windows UI Automation selectors are not validated for Codex build {buildIdentity}.") =>
        BuildIdentity = buildIdentity;

    public string BuildIdentity { get; }
}

public sealed class HostSettingsPageDetectedException : Exception;

public interface IHostWindowLocator
{
    ValueTask<HostWindowSnapshot?> FindAsync(CancellationToken cancellationToken);
}

public interface ITitlebarScanner
{
    TitlebarSnapshot? TryGetCurrent(HostWindowSnapshot host) => null;
    TitlebarSnapshot? TryGetRetained(HostWindowSnapshot host) => null;
    ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken);
    void Invalidate();
}

public interface IOverlaySurface
{
    bool HasForegroundWindow => false;
    ValueTask ShowAsync(OverlayPresentation presentation, CancellationToken cancellationToken);
    ValueTask HideAsync(CancellationToken cancellationToken);
}

public interface IIndicatorSizeProvider
{
    double MeasureIndicatorWidth(AllowanceSnapshot snapshot, DisplayLanguage language, double height);
}

public interface ISafeDockOverlaySurface : IOverlaySurface
{
    event Func<SafeDockPreferences, CancellationToken, ValueTask>? SafeDockPreferencesChanged;
}
