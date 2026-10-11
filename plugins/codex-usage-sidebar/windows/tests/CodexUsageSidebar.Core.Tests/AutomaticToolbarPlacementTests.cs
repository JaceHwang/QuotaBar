namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class AutomaticToolbarPlacementTests
{
    [TestMethod]
    public void SearchesBeforeTheTitleWhenThatIsTheOnlyFreeInterval()
    {
        var result = PlacementResolver.ResolveAutomatic(new(0, 0, 1000, 800), new(0, 60, 1000, 46),
            new(800, 69, 100, 28), new(400, 69, 390, 28), 164, 1,
            [new(800, 69, 200, 28)]);
        Assert.IsNotNull(result);
        Assert.AreEqual(new RectD(228, 69, 164, 28), result.Value.Placement.Frame);
        Assert.IsFalse(result.Value.SwitchToFree);
    }

    [TestMethod]
    public void TriesTheSafeDefaultBeforeSearchingOtherIntervals()
    {
        var result = PlacementResolver.ResolveAutomatic(new(0, 0, 1000, 800), new(0, 60, 1000, 46),
            new(500, 69, 100, 28), new(8, 69, 400, 28), 164, 1, [new(500, 69, 100, 28)]);
        Assert.AreEqual(new RectD(660, 69, 164, 28), result!.Value.Placement.Frame);
        Assert.IsFalse(result.Value.SwitchToFree);
    }

    [TestMethod]
    public void NeverSearchesUnobservedSpaceOrTreatsStaticTitleAsAFreeModeTrigger()
    {
        var result = PlacementResolver.ResolveAutomatic(new(0, 0, 1000, 800), new(600, 60, 400, 46),
            new(900, 69, 100, 28), new(600, 69, 290, 28), 164, 1, [new(900, 69, 100, 28)]);
        Assert.AreEqual(new RectD(660, 69, 164, 28), result!.Value.Placement.Frame);
        Assert.IsFalse(result.Value.SwitchToFree);
    }
}
