namespace QuotaBar.Core;
/// <summary>Unifies a global mouse-down dismissal with the subsequent native tray click.</summary>
public sealed class TrayClickGate {
    private bool dismissed;
    public void BeginMouseDown() => dismissed=false;
    public void OutsideDismissed() => dismissed=true;
    public bool SuppressTrayClick() { var samePress=dismissed; dismissed=false; return samePress; }
}
