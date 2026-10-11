using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class DiagnosticTitlebarScopeTests
{
    private static readonly HostWindowSnapshot Host = new(
        new IntPtr(42), new RectD(-13, -13, 3026, 1930), true, 2, "153");
    private static readonly RectD Toolbar = new(478, 70, 2522, 92);

    [TestMethod]
    public void RetainsPartiallyOverlappingInteractiveGeometryWithoutReadingItsText()
    {
        var bounds = new RectD(1800, 150, 40, 40);
        var scope = DiagnosticTitlebarScope.Resolve(Host, "ControlType.Button", "", bounds, Toolbar);
        Assert.AreEqual(Toolbar, scope);
        Assert.AreEqual("", DiagnosticTitlebarScope.ReadName(scope, bounds, "ControlType.Button",
            () => throw new InvalidOperationException("Outside-band text must not be requested")));
    }


    [TestMethod]
    public void RecognizesToolbarByClassTokensWithoutDependingOnTheirOrder()
    {
        Assert.AreEqual(Toolbar, DiagnosticTitlebarScope.Resolve(
            Host, "ControlType.Group", "flex top-toolbar-sm z-30 fixed h-toolbar", Toolbar, null));
    }

    [TestMethod]
    public void DoesNotReadConversationOrContainerNames()
    {
        var reads = 0;
        string Read() { reads++; return "private conversation"; }
        Assert.AreEqual("", DiagnosticTitlebarScope.ReadName(null, Toolbar, "ControlType.Text", Read));
        Assert.AreEqual("", DiagnosticTitlebarScope.ReadName(Toolbar, Toolbar, "ControlType.Group", Read));
        Assert.AreEqual("", DiagnosticTitlebarScope.ReadName(Toolbar, new(500, 187, 300, 40), "ControlType.Text", Read));
        Assert.AreEqual(0, reads);
    }

    [TestMethod]
    public void ReadsOnlySupportedControlsContainedInTheConfirmedToolbar()
    {
        var reads = 0;
        Assert.AreEqual("Open", DiagnosticTitlebarScope.ReadName(
            Toolbar, new(2620, 88, 182, 56), "ControlType.Button", () => { reads++; return "Open"; }));
        Assert.AreEqual(1, reads);
    }

    [TestMethod]
    public void RejectsAConversationToolbarAndDescendantsOutsideTheConfirmedScope()
    {
        Assert.IsNull(DiagnosticTitlebarScope.Resolve(
            Host, "ControlType.ToolBar", "", new(500, 500, 600, 40), null));
        Assert.IsNull(DiagnosticTitlebarScope.Resolve(
            Host, "ControlType.Text", "", new(500, 187, 300, 40), Toolbar));
    }

    [TestMethod]
    public void AcceptsNativeCaptionControlsButRejectsInvalidGeometry()
    {
        var caption = new RectD(2700, -2, 300, 72);
        Assert.AreEqual(caption, DiagnosticTitlebarScope.Resolve(
            Host, "ControlType.Pane", "ChromeNodeCaptionButtonContainer", caption, null));
        Assert.IsNull(DiagnosticTitlebarScope.Resolve(
            Host, "ControlType.ToolBar", "", Toolbar with { Width = double.PositiveInfinity }, null));
    }
}
