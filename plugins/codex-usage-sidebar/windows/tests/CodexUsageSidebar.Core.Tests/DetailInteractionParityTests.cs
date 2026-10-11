namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class DetailInteractionParityTests
{
    [TestMethod]
    public void OutsideDismissalAllowsTheNextHoverToOpenDetails()
    {
        var state = DetailInteractionState.Initial.TogglePinned(true).PointerPressed(false, false);
        Assert.IsFalse(state.ShouldShowDetail);
        Assert.IsFalse(state.IsPinned);
        Assert.IsTrue(state.PointerChanged(true).ShouldShowDetail);
    }

}
