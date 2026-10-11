namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class AutomaticFallbackTests
{
    [TestMethod]
    public void DefaultSlotUsesActualWidthAndChecksInteractiveSafetyGap()
    {
        var result = PlacementResolver.ResolveDefaultFallback(new(0, 0, 1000, 800),
            new(0, 60, 1000, 46), new(800, 69, 80, 28), 200, 1, [new(620, 69, 2, 28)]);
        Assert.IsNotNull(result);
        Assert.AreEqual(new RectD(624, 69, 200, 28), result.Value.Placement.Frame);
        Assert.IsTrue(result.Value.SwitchToFree);
        var clear = PlacementResolver.ResolveDefaultFallback(new(0, 0, 1000, 800),
            new(0, 60, 1000, 46), new(800, 69, 80, 28), 200, 1, [new(620, 100, 2, 28)]);
        Assert.IsFalse(clear!.Value.SwitchToFree);
    }

    [TestMethod]
    public async Task FreeFallbackSurvivesSavingAndReloadingPreferences()
    {
        var path = Path.Combine(Path.GetTempPath(), $"cus-fallback-{Guid.NewGuid():N}.json");
        try
        {
            var store = new IndicatorPreferencesStore(path);
            var preferences = new IndicatorPlacementPreferences();
            var frame = new RectD(624, 69, 200, 28);
            var work = new RectD(0, 0, 1000, 800);
            preferences.SwitchToFreeFallback("display", frame, work);
            await store.SaveAsync(preferences, CancellationToken.None);
            var restored = await store.LoadAsync(CancellationToken.None);
            Assert.AreEqual(IndicatorPlacementMode.Free, restored.Mode);
            Assert.AreEqual(frame, restored.Resolve("display", work, new(0, 0, 200, 28)));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [TestMethod]
    public void CapturesTheDefaultFrameInsteadOfReusingAnOlderManualCoordinate()
    {
        var preferences = new IndicatorPlacementPreferences();
        var work = new RectD(0, 0, 1000, 800);
        preferences.Capture("display", new(20, 400, 200, 28), work);
        var frame = new RectD(600, 70, 200, 28);
        Assert.IsTrue(preferences.SwitchToFreeFallback("display", frame, work));
        Assert.AreEqual(IndicatorPlacementMode.Free, preferences.Mode);
        Assert.AreEqual(frame, preferences.Resolve("display", work, frame));
        Assert.IsFalse(preferences.SwitchToFreeFallback("display", new(50, 50, 200, 28), work));
        Assert.AreEqual(frame, preferences.Resolve("display", work, frame));
    }

    [TestMethod]
    public void DoesNotChangeALockedManualPosition()
    {
        var preferences = new IndicatorPlacementPreferences { Mode = IndicatorPlacementMode.Locked };
        Assert.IsFalse(preferences.SwitchToFreeFallback("display", new(600, 70, 200, 28), new(0, 0, 1000, 800)));
        Assert.AreEqual(IndicatorPlacementMode.Locked, preferences.Mode);
    }
}
