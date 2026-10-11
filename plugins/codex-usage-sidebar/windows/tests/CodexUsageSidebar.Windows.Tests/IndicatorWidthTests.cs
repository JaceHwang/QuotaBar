namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class IndicatorWidthTests
{
    [TestMethod]
    [DataRow(120d, 164d)]
    [DataRow(210.2d, 211d)]
    [DataRow(400d, 280d)]
    public void MeasuredWidthUsesTheMacOSRange(double measured, double expected) =>
        Assert.AreEqual(expected, OverlayVisualMetrics.ClampMeasuredIndicatorWidth(measured));
}
