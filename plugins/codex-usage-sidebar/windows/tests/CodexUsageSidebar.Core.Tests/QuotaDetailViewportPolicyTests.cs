using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class QuotaDetailViewportPolicyTests
{
    [TestMethod]
    public void FreeDetailViewportShrinksToFitTheSpaceAboveTheIndicator()
    {
        var height = QuotaDetailViewportPolicy.ResolveViewportWithinAvailableHeight(
            requestedHeight: 256, availablePanelHeight: 360, fixedChromeHeight: 240);

        Assert.AreEqual(120, height!.Value, 0.000001);
    }

    [TestMethod]
    public void FreeDetailViewportRejectsAnAreaSmallerThanTheMinimumScrollableRows()
    {
        var height = QuotaDetailViewportPolicy.ResolveViewportWithinAvailableHeight(
            requestedHeight: 256, availablePanelHeight: 303, fixedChromeHeight: 240);

        Assert.IsNull(height);
    }
}
