namespace CodexUsageSidebar.Windows;

public static class OverlayVisualMetrics
{
    public static double ClampMeasuredIndicatorWidth(double measured) =>
        double.IsFinite(measured) ? Math.Clamp(Math.Ceiling(measured), 164, 280) : 164;

    public const double IndicatorTextWidth = 168;
    public const double IndicatorLogoSize = 20;
    public const double IndicatorLogoTextGap = 4;
    public const double IndicatorContentWidth = IndicatorTextWidth + IndicatorLogoSize + IndicatorLogoTextGap;
    public const double IndicatorHeight = 28;
    public const double IndicatorTextFontSize = 11;
    public const double IndicatorHorizontalPadding = IndicatorHeight / 3;
    public const double IndicatorWidth = IndicatorContentWidth + (2 * IndicatorHorizontalPadding);
    public const double CompactIndicatorTextWidth = 32;
    public const double CompactIndicatorContentWidth = IndicatorLogoSize + IndicatorLogoTextGap + CompactIndicatorTextWidth;
    public const double CompactIndicatorWidth = CompactIndicatorContentWidth + (2 * IndicatorHorizontalPadding);
    public const double DetailWidth = 360;
    public const double HeaderTitleFontSize = 18;
    public const double HeaderTitleMaximumWidth = 190;
    public const double VersionBadgeFontSize = 9;
    public const double VersionBadgeHeight = 18;
    public const double DetailLockButtonSize = 26;
    public const double DetailLockButtonBadgeGap = 6;
    public const byte DetailLockButtonHoverAlpha = 20;
    public const byte DetailLockButtonActiveAlpha = 31;
    public const double DetailResizeHitHeight = 14;
    public const double DetailResizeHandleWidth = 20;
    public const double DetailResizeHandleHeight = 3;
    public const double RemainingPercentFontSize = 28;
    public const double DetailValueFontSize = 13;
    public const double CountdownDigitFontSize = 16;
    public const double CountdownUnitFontSize = 11;
    public const double ProgressTrackHeight = 4;

    public static double IndicatorHorizontalPaddingForHeight(double height) => height / 3;

    public static double IndicatorWidthForHeight(double height) =>
        IndicatorContentWidth + (2 * IndicatorHorizontalPaddingForHeight(height));
}

public static class OverlayWindowPolicy
{
    private const uint NoActivate = 0x0010;
    private const uint ShowWindow = 0x0040;
    private const uint NoOwnerZOrder = 0x0200;

    public const uint PositionFlags = NoActivate | ShowWindow | NoOwnerZOrder;
}
