using CodexUsageSidebar.Core;
using CodexUsageSidebar.Windows;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class OverlayDetailLayoutTests
{
    [TestMethod]
    public void FreeDetailUsesAllAvailableSpaceAboveTheIndicatorBeforeShowingBelowIt()
    {
        var placement = OverlayDetailLayout.ResolveFreeDetailPlacement(
            new RectD(100, 600, 333, 56), new RectD(0, 0, 1600, 720),
            minimumHeight: 128, gap: 6);

        Assert.IsNotNull(placement);
        Assert.IsTrue(placement.Value.IsAbove);
        Assert.AreEqual(594, placement.Value.AvailableHeight, 0.000001);
    }

    [TestMethod]
    public void FreeDetailFallsBelowTheIndicatorWhenTheTopCannotFitItsMinimumHeight()
    {
        var placement = OverlayDetailLayout.ResolveFreeDetailPlacement(
            new RectD(100, 50, 333, 56), new RectD(0, 0, 1600, 720),
            minimumHeight: 128, gap: 6);

        Assert.IsNotNull(placement);
        Assert.IsFalse(placement.Value.IsAbove);
        Assert.AreEqual(608, placement.Value.AvailableHeight, 0.000001);
    }
}
