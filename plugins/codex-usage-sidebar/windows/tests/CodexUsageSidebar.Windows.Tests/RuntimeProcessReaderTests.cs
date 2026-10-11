using System.Diagnostics;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class RuntimeProcessReaderTests
{
    [TestMethod]
    public void RequiresTheExactExecutablePathNotJustTheProcessName()
    {
        using var current = Process.GetCurrentProcess();
        var path = current.MainModule!.FileName;
        var running = RuntimeProcessReader.Find(path);
        Assert.IsNotNull(running);
        Assert.IsTrue(running.ProcessId > 0);
        Assert.IsTrue(running.StartedAt <= DateTimeOffset.UtcNow);
        var otherPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), Path.GetFileName(path));
        Assert.IsNull(RuntimeProcessReader.Find(otherPath));
    }

    [TestMethod]
    public void APreviousProcessOutcomeDoesNotDescribeTheNewProcess()
    {
        var started = DateTimeOffset.UtcNow;
        var process = new RuntimeProcessIdentity(123, started);
        var outcome = new RuntimeStateOutcome(HostRuntimeState.Visible,
            new CompatibilityDecision(SemanticCompatibility.Valid, ProfileCompatibility.Validated,
                SafeDockPlacement.Titlebar, CompatibilityFailureCode.None), started.AddSeconds(-1));
        Assert.IsNull(process.CurrentOutcome(outcome));
        Assert.AreEqual(outcome with { RecordedAt = started }, process.CurrentOutcome(outcome with { RecordedAt = started }));
        Assert.IsNull(process.CurrentOutcome(null));
    }
}
