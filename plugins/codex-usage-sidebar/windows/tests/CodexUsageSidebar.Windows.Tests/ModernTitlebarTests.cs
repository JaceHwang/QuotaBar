using System.Text.Json;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class ModernTitlebarTests
{
    [TestMethod]
    public void CollectsUnrecognizedButtonsBeforeTheAnchorAndAcrossTheBandBoundary()
    {
        var fixture = Load();
        var control = new UiaStructureNode(16, "ControlType.Button", "", "new-host-action",
            new RectD(1800, 130, 40, 40), 0);
        var result = CodexTitlebarSelector.TryResolve(fixture.Host.BuildIdentity,
            fixture.Host.DpiScale, fixture.Host.Bounds, fixture.Nodes.Append(control).ToArray());
        Assert.IsNotNull(result);
        Assert.IsTrue(result.AllInteractiveObstacles.Contains(control.Bounds));
        Assert.IsTrue(result.AllInteractiveObstacles.Contains(new RectD(652, 88, 56, 56)));
        Assert.IsTrue(result.AllInteractiveObstacles.Contains(new RectD(708, 92, 353, 48)));
    }

    [TestMethod]
    public async Task DoesNotMistakeModernConversationNavigationForSettings()
    {
        var fixture = Load();
        var observations = fixture.Nodes.Select(node => new UiaScanningObservation(
            node.Depth, node.ControlType, node.AutomationId, node.ClassName, node.Bounds, ""))
            .Append(new UiaScanningObservation(10, "ControlType.Button", "", "",
                new RectD(30, 60, 120, 40), "Tasks")).ToArray();
        var scanner = new ValidatedUiaTitlebarScanner(SelectorProfileCatalog.Default,
            (_, _) => ValueTask.FromResult<IReadOnlyList<UiaScanningObservation>>(observations));
        var result = await scanner.ScanAsync(new HostWindowSnapshot(new IntPtr(42),
            fixture.Host.Bounds, true, fixture.Host.DpiScale, fixture.Host.BuildIdentity), CancellationToken.None);
        Assert.AreEqual(2652, result.PreferredAnchorTrailingEdge);
    }

    [TestMethod]
    public void ResolvesTheLocallyObserved153ToolbarWithoutAnOpenLocationAnchor()
    {
        var fixture = Load();
        var result = CodexTitlebarSelector.TryResolve(fixture.Host.BuildIdentity,
            fixture.Host.DpiScale, fixture.Host.Bounds, fixture.Nodes);
        Assert.IsNotNull(result);
        Assert.AreEqual(new RectD(624, 70, 2376, 92), result.ToolbarBounds);
        Assert.AreEqual(new RectD(2652, 88, 56, 56), result.OpenLocationBounds);
        Assert.AreEqual(new RectD(652, 88, 409, 56), result.TitleBounds);
        Assert.IsTrue(result.Obstacles.Contains(new RectD(2928, 88, 56, 56)));
    }

    [TestMethod]
    public void RejectsModernStructureWhenCaptionVerificationIsMissing()
    {
        var fixture = Load();
        Assert.IsNull(CodexTitlebarSelector.TryResolve(fixture.Host.BuildIdentity,
            fixture.Host.DpiScale, fixture.Host.Bounds,
            fixture.Nodes.Where(node => node.AutomationId != "view_4").ToArray()));
    }

    private static Fixture Load() => JsonSerializer.Deserialize<Fixture>(File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "contracts", "windows-codex-153-scoped-200.json")))!;
    private sealed record Fixture(WindowsProbeHost Host, UiaStructureNode[] Nodes);
}
