using System.Text.Json;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class RuntimeStateReaderTests
{
    [DataTestMethod]
    [DataRow(-3600)]
    [DataRow(3600)]
    public async Task DoesNotReportAnOldOrFutureOutcomeAsCurrent(int seconds)
    {
        var path = Path.Combine(Path.GetTempPath(), $"sidebar-state-{Guid.NewGuid():N}.json");
        try
        {
            var outcome = new RuntimeStateOutcome(HostRuntimeState.Visible,
                new CompatibilityDecision(SemanticCompatibility.Valid, ProfileCompatibility.Validated,
                    SafeDockPlacement.Titlebar, CompatibilityFailureCode.None), DateTimeOffset.UtcNow.AddSeconds(seconds));
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(outcome));
            Assert.IsNull(await RuntimeStateReader.LoadAsync(path, CancellationToken.None));
        }
        finally { File.Delete(path); }
    }

    [TestMethod]
    public async Task PreservesAFreshOutcome()
    {
        var path = Path.Combine(Path.GetTempPath(), $"sidebar-state-{Guid.NewGuid():N}.json");
        try
        {
            var outcome = new RuntimeStateOutcome(HostRuntimeState.Visible,
                new CompatibilityDecision(SemanticCompatibility.Valid, ProfileCompatibility.Validated,
                    SafeDockPlacement.Titlebar, CompatibilityFailureCode.None), DateTimeOffset.UtcNow);
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(outcome));
            Assert.AreEqual(outcome, await RuntimeStateReader.LoadAsync(path, CancellationToken.None));
        }
        finally { File.Delete(path); }
    }

    [TestMethod]
    public async Task IncompleteStateIsUnknownRatherThanAValidOutcome()
    {
        var path = Path.Combine(Path.GetTempPath(), $"sidebar-state-{Guid.NewGuid():N}.json");
        try
        {
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(new { RecordedAt = DateTimeOffset.UtcNow }));
            Assert.IsNull(await RuntimeStateReader.LoadAsync(path, CancellationToken.None));
        }
        finally { File.Delete(path); }
    }
}
