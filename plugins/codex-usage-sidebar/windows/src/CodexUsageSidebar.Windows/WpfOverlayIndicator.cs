#if WINDOWS
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed partial class WpfOverlaySurface
{
    private static double TextWidth(string text, bool bold = false) => Math.Ceiling(new FormattedText(
        text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
        new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal,
            bold ? FontWeights.Bold : FontWeights.SemiBold, FontStretches.Normal),
        OverlayVisualMetrics.IndicatorTextFontSize, Brushes.Black, 1).WidthIncludingTrailingWhitespace);

    private static double[] IndicatorColumns(IReadOnlyList<QuotaIndicatorRow> rows) =>
    [
        rows.Max(row => TextWidth(row.Label)) + 5,
        Math.Max(TextWidth("100%", true), rows.Max(row => TextWidth(row.Percentage, true))) + 3,
        TextWidth("·") + 5,
        rows.Max(row => TextWidth(row.Reset)) + 1,
    ];

    public double MeasureIndicatorWidth(AllowanceSnapshot snapshot, DisplayLanguage language, double height)
    {
        double Measure() => OverlayVisualMetrics.ClampMeasuredIndicatorWidth(IndicatorColumns(QuotaDetailFormatter.FormatIndicatorRows(snapshot, language, timeZone)).Sum()
            + OverlayVisualMetrics.IndicatorLogoSize + OverlayVisualMetrics.IndicatorLogoTextGap
            + 2 * OverlayVisualMetrics.IndicatorHorizontalPaddingForHeight(height));
        return indicator.Dispatcher.CheckAccess() ? Measure() : indicator.Dispatcher.Invoke(Measure);
    }

    private void UpdateIndicator(AllowanceSnapshot snapshot, DisplayLanguage language, bool compactMode)
    {
        var rows = QuotaDetailFormatter.FormatIndicatorRows(snapshot, language, timeZone);
        indicatorText.Children.Clear();
        indicatorText.RowDefinitions.Clear();
        indicatorText.ColumnDefinitions.Clear();
        var widths = compactMode ? new[] { TextWidth("100%", true) } : IndicatorColumns(rows);
        foreach (var width in widths) indicatorText.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(width) });
        for (var rowIndex = 0; rowIndex < rows.Count; rowIndex++)
        {
            var row = rows[rowIndex];
            indicatorText.RowDefinitions.Add(new RowDefinition { Height = new GridLength(13) });
            void Add(string text, int column, bool accent = false)
            {
                var label = new TextBlock
                {
                    Text = text,
                    FontFamily = new FontFamily("Segoe UI"),
                    FontSize = OverlayVisualMetrics.IndicatorTextFontSize,
                    FontWeight = accent ? FontWeights.Bold : FontWeights.SemiBold,
                    Foreground = accent ? new SolidColorBrush(WpfQuotaColors.ForRemainingPercent(row.RemainingPercent)) : palette.Primary,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                Grid.SetRow(label, rowIndex);
                Grid.SetColumn(label, column);
                indicatorText.Children.Add(label);
            }
            if (compactMode) Add(row.Percentage, 0, true);
            else
            {
                Add(row.Label, 0);
                Add(row.Percentage, 1, true);
                Add("·", 2);
                Add(row.Reset, 3);
            }
        }
        System.Windows.Automation.AutomationProperties.SetName(indicatorText,
            string.Join("; ", rows.Select(row => $"{row.Label} {row.Percentage} · {row.Reset}")));
    }
}
#endif
