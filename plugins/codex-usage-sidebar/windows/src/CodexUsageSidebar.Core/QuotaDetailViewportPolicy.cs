namespace CodexUsageSidebar.Core;

public static class QuotaDetailViewportPolicy
{
    public const double RowHeight = 32;
    public const double MinimumRowViewportHeight = RowHeight * 2;
    public const double DefaultRowViewportHeight = RowHeight * 8;

    public static double ResolveRowViewportHeight(
        double requestedHeight,
        double availablePanelHeight,
        double fixedChromeHeight)
    {
        var maximum = Math.Max(
            MinimumRowViewportHeight,
            availablePanelHeight - Math.Max(0, fixedChromeHeight));
        return Math.Clamp(requestedHeight, MinimumRowViewportHeight, maximum);
    }

    public static double? ResolveViewportWithinAvailableHeight(
        double requestedHeight,
        double availablePanelHeight,
        double fixedChromeHeight)
    {
        if (!double.IsFinite(requestedHeight) || !double.IsFinite(availablePanelHeight)
            || !double.IsFinite(fixedChromeHeight)) return null;
        var maximum = availablePanelHeight - Math.Max(0, fixedChromeHeight);
        if (maximum < MinimumRowViewportHeight) return null;
        return Math.Clamp(requestedHeight, MinimumRowViewportHeight, maximum);
    }

    public static string ResizeHint(DisplayLanguage language) => language switch
    {
        DisplayLanguage.SimplifiedChinese => "调整高度",
        DisplayLanguage.TraditionalChinese => "調整高度",
        _ => "Adjust height",
    };

    public static bool ShouldKeepDetailVisible(
        bool isResizing,
        DetailInteractionState interaction) => isResizing || interaction.ShouldShowDetail;
}
