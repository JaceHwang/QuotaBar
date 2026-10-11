using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public readonly record struct DetailVerticalPlacement(bool IsAbove, double AvailableHeight);

public static class OverlayDetailLayout
{
    public const double LogoSize = 28;
    public const double RowSeparatorHeight = 1;
    public const int FullWidthSectionSeparatorCount = 2;
    public const double SectionSeparatorHeight = 1;
    public const double SectionSeparatorHorizontalMargin = 0;

    public static double LeftForIndicator(RectD indicatorFrame, RectD workArea, double detailWidth)
    {
        if (!double.IsFinite(detailWidth) || detailWidth <= 0)
        {
            return workArea.X;
        }

        var maximumLeft = Math.Max(workArea.X, workArea.Right - detailWidth);
        return Math.Clamp(indicatorFrame.X, workArea.X, maximumLeft);
    }

    public static DetailVerticalPlacement? ResolveFreeDetailPlacement(
        RectD indicatorFrame,
        RectD workArea,
        double minimumHeight,
        double gap)
    {
        if (!double.IsFinite(minimumHeight) || minimumHeight <= 0
            || !double.IsFinite(gap) || gap < 0) return null;
        var aboveHeight = indicatorFrame.Y - gap - workArea.Y;
        if (aboveHeight >= minimumHeight) return new(true, aboveHeight);
        var belowHeight = workArea.Bottom - indicatorFrame.Bottom - gap;
        return belowHeight >= minimumHeight ? new(false, belowHeight) : null;
    }
}
