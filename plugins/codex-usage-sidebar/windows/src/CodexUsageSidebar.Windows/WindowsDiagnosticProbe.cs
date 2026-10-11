#if WINDOWS
using System.Windows.Automation;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed class WindowsDiagnosticProbe(IHostWindowLocator locator)
{
    private const int MaximumNodes = UiaTraversalBudget.DiagnosticMaximumNodes;
    private const int MaximumDepth = UiaTraversalBudget.DiagnosticMaximumDepth;

    public async ValueTask<WindowsProbeReport> CaptureAsync(
        bool includeText,
        CancellationToken cancellationToken)
    {
        var host = await locator.FindAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("A visible Codex window is required for the diagnostic probe.");
        var root = AutomationElement.FromHandle(host.Handle)
            ?? throw new InvalidOperationException("Windows UI Automation could not inspect the Codex window.");
        var redactor = ProbeRedactor.Create();
        var nodes = Collect(root, host, includeText, redactor, cancellationToken);
        var executablePath = Win32CodexWindowLocator.ExecutablePath(host.Handle);
        var titlebar = CodexTitlebarSelector.TryResolve(
            host.BuildIdentity,
            host.DpiScale,
            host.Bounds,
            nodes.Select(node => new UiaStructureNode(
                node.Depth,
                node.ControlType,
                node.AutomationId,
                node.ClassName,
                node.Bounds,
                node.NameLength,
                node.SemanticRole)).ToArray());
        return new WindowsProbeReport(
            "1",
            DateTimeOffset.UtcNow,
            Environment.OSVersion.VersionString,
            includeText,
            WindowsProbeHost.From(host),
            executablePath is null ? null : redactor.Token(executablePath),
            nodes,
            titlebar);
    }

    internal static IReadOnlyList<UiaProbeNode> Collect(
        AutomationElement root, HostWindowSnapshot host, bool includeText,
        ProbeRedactor redactor, CancellationToken cancellationToken)
    {
        var nodes = new List<UiaProbeNode>();
        var visited = 0;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var metadata = new CacheRequest { TreeScope = TreeScope.Element };
        metadata.Add(AutomationElement.BoundingRectangleProperty);
        metadata.Add(AutomationElement.ControlTypeProperty);
        metadata.Add(AutomationElement.ClassNameProperty);
        metadata.Add(AutomationElement.AutomationIdProperty);
        Append(root, 0, host, null, includeText, redactor, nodes, seen, metadata, ref visited, cancellationToken);
        return nodes;
    }

    private static void Append(
        AutomationElement element,
        int depth,
        HostWindowSnapshot host,
        RectD? parentScope,
        bool includeText,
        ProbeRedactor redactor,
        List<UiaProbeNode> nodes,
        HashSet<string> seen,
        CacheRequest metadata,
        ref int visited,
        CancellationToken cancellationToken)
    {
        if (depth > MaximumDepth || visited >= MaximumNodes)
        {
            return;
        }
        cancellationToken.ThrowIfCancellationRequested();
        visited++;
        RectD? scope;
        try
        {
            var runtimeId = element.GetRuntimeId();
            if (runtimeId.Length > 0 && !seen.Add(string.Join(",", runtimeId))) return;
            // Batch structural properties in one provider request. Name stays
            // outside this cache so unrelated text is never fetched eagerly.
            var current = element.GetUpdatedCache(metadata).Cached;
            var bounds = current.BoundingRectangle;
            var resolvedBounds = new RectD(bounds.X, bounds.Y, bounds.Width, bounds.Height);
            var controlType = current.ControlType?.ProgrammaticName ?? string.Empty;
            var className = current.ClassName ?? string.Empty;
            scope = DiagnosticTitlebarScope.Resolve(host, controlType, className, resolvedBounds, parentScope);
            if (scope is not null)
            {
                var name = DiagnosticTitlebarScope.ReadName(scope, resolvedBounds, controlType,
                    () => element.Current.Name ?? string.Empty);
                nodes.Add(new UiaProbeNode(
                    depth,
                    controlType,
                    current.AutomationId ?? string.Empty,
                    className,
                    resolvedBounds,
                    name.Length,
                    redactor.Token(name),
                    UiaSemanticRoleClassifier.Classify(name),
                    includeText ? name : null));
            }
        }
        catch (ElementNotAvailableException)
        {
            return;
        }

        var walker = TreeWalker.RawViewWalker;
        AutomationElement? child;
        try
        {
            child = walker.GetFirstChild(element);
        }
        catch (ElementNotAvailableException)
        {
            return;
        }
        while (child is not null && visited < MaximumNodes)
        {
            Append(child, depth + 1, host, scope, includeText, redactor, nodes, seen, metadata, ref visited, cancellationToken);
            try
            {
                child = walker.GetNextSibling(child);
            }
            catch (ElementNotAvailableException)
            {
                break;
            }
        }
    }
}
#endif
