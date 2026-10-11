using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public static class DiagnosticTitlebarScope
{
    public static bool IsInteractiveControlType(string controlType) => controlType is
        "ControlType.Button" or "ControlType.Hyperlink" or "ControlType.MenuItem"
        or "ControlType.CheckBox" or "ControlType.RadioButton" or "ControlType.ComboBox";

    public static RectD? Resolve(
        HostWindowSnapshot host, string controlType, string className,
        RectD bounds, RectD? parentScope)
    {
        if (!IsUsable(bounds)) return null;
        if (parentScope is { } scope)
            return Contains(scope, bounds) || (IsInteractiveControlType(controlType)
                && bounds.Height <= 64 * host.DpiScale && bounds.Width <= 420 * host.DpiScale
                && bounds.X >= scope.X && bounds.Right <= scope.Right
                && bounds.Y < scope.Bottom && bounds.Bottom > scope.Y) ? scope : null;

        if (!IsUsable(host.Bounds) || !double.IsFinite(host.DpiScale) || host.DpiScale <= 0)
            return null;
        // Native caption and web content headers occupy separate rows on Windows.
        // Geometry alone never authorizes text collection: require a toolbar role
        // or the known header container's structural class tokens as well.
        if (!Contains(host.Bounds, bounds)
            || bounds.Y > host.Bounds.Y + 90 * host.DpiScale
            || bounds.Height > 64 * host.DpiScale)
            return null;
        var tokens = className.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var isHeader = tokens.Contains("fixed") && tokens.Contains("h-toolbar")
            && tokens.Contains("top-toolbar-sm");
        return controlType == "ControlType.ToolBar"
            || className == "ChromeNodeCaptionButtonContainer" || isHeader ? bounds : null;
    }

    public static string ReadName(RectD? scope, RectD bounds, string controlType, Func<string> readName)
    {
        if (scope is not { } region || !IsUsable(bounds) || !Contains(region, bounds)) return "";
        // Container names may aggregate descendant conversation text.
        return controlType is "ControlType.Button" or "ControlType.Text" or "ControlType.Hyperlink"
            or "ControlType.MenuItem" or "ControlType.CheckBox" or "ControlType.RadioButton"
            ? readName() : "";
    }

    private static bool Contains(RectD outer, RectD inner) => inner.X >= outer.X && inner.Y >= outer.Y
        && inner.Right <= outer.Right && inner.Bottom <= outer.Bottom;

    private static bool IsUsable(RectD bounds) => UiaTraversalBudget.HasFiniteBounds(bounds)
        && double.IsFinite(bounds.Right) && double.IsFinite(bounds.Bottom)
        && bounds.Width > 0 && bounds.Height > 0;
}
