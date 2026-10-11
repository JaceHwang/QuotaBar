namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class TitlebarFreeSlotTests
{
    [TestMethod]
    public void SearchesLeftwardWhenThePreferredSlotIsOccupied()
    {
        var result = PlacementResolver.ResolveResponsive(
            new(0, 0, 1000, 46), new(800, 8, 100, 28), new(10, 8, 100, 28),
            164, 8, [new(650, 8, 60, 28), new(800, 8, 100, 28)], default, []);
        Assert.IsNotNull(result);
        Assert.AreEqual(new RectD(478, 8, 164, 28), result.Value.Frame);
    }

    [TestMethod]
    public void MaintainsSafetyGapEvenWhenTheObstacleDoesNotOverlapThePreferredFrame()
    {
        var result = PlacementResolver.ResolveResponsive(
            new(0, 0, 1000, 46), new(800, 8, 100, 28), new(10, 8, 100, 28),
            164, 8, [new(620, 8, 4, 28), new(800, 8, 100, 28)], default, []);
        Assert.IsNotNull(result);
        Assert.AreEqual(new RectD(448, 8, 164, 28), result.Value.Frame);
    }

    [TestMethod]
    public void PartialBandControlsBlockSlotsButControlsBelowTheBandDoNot()
    {
        var result = PlacementResolver.ResolveResponsive(
            new(0, 0, 1000, 46), new(800, 8, 100, 28), new(10, 8, 100, 28),
            164, 8, [new(650, 30, 60, 30), new(470, 36, 180, 20), new(800, 8, 100, 28)], default, []);
        Assert.IsNotNull(result);
        Assert.AreEqual(new RectD(478, 8, 164, 28), result.Value.Frame);
    }
}
