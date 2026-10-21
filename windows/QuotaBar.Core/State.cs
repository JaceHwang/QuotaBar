namespace QuotaBar.Core;

public enum Phase { Loading, Ready, Offline, NeedsLogin, SigningIn, Unsupported }
public sealed class RefreshState {
    public Phase Phase { get; private set; }=Phase.Loading;
    public DateTimeOffset? LastSuccess { get; private set; }
    private DateTimeOffset next=DateTimeOffset.MinValue;
    private int failures;
    public bool ShouldRefresh(DateTimeOffset now) => Phase is not (Phase.NeedsLogin or Phase.SigningIn or Phase.Unsupported) && now>=next;
    public void Received(DateTimeOffset now) { Phase=Phase.Ready; LastSuccess=now; failures=0; next=now.AddSeconds(60); }
    public void BeginLogin() { Phase=Phase.SigningIn; }
    public void LoginCompleted(bool success) { Phase=success?Phase.Loading:Phase.NeedsLogin; next=DateTimeOffset.MinValue; }
    public void Error(string method,string message,DateTimeOffset? at=null) {
        if(method is not ("account/rateLimits/read" or "initialize")) return;
        var value=message.ToLowerInvariant();
        if(new[]{"401","token_expired","authentication","not logged"}.Any(value.Contains)) Phase=Phase.NeedsLogin;
        else if(value.Contains("unsupported") || value.Contains("method not found")) Phase=Phase.Unsupported;
        else { Phase=Phase.Offline; next=(at??DateTimeOffset.UtcNow).AddSeconds(Math.Min(300,15*Math.Pow(2,Math.Min(failures++,5)))); }
    }
}

public sealed class DetailInteractionState {
    public bool IsPinned { get; private set; }
    public bool IsLocked { get; private set; }
    private bool pointer,suppress;
    public bool ShouldShow => IsLocked || IsPinned || pointer && !suppress;
    public void UpdatePointer(bool inside) { if(!inside) suppress=false; pointer=inside; }
    public void TogglePinned(bool inside) { pointer=inside; IsPinned=!IsPinned; suppress=!IsPinned && inside; }
    public void ToggleLocked(bool inside) { pointer=inside; IsLocked=!IsLocked; if(IsLocked) IsPinned=false; suppress=false; }
    public void DismissOutside() { IsPinned=false; pointer=false; suppress=false; }
    public void DismissForContextMenu() { IsPinned=false; IsLocked=false; pointer=true; suppress=true; }
    public void Reset() { IsPinned=false; IsLocked=false; pointer=false; suppress=false; }
}

public readonly record struct WorkArea(double X,double Y,double Width,double Height) {
    public (double X,double Y) Clamp(double x,double y,double width,double height) => (Math.Clamp(x,X,X+Math.Max(0,Width-width)),Math.Clamp(y,Y,Y+Math.Max(0,Height-height)));
    public double Distance(double x,double y) { var dx=Math.Max(Math.Max(X-x,0),x-X-Width); var dy=Math.Max(Math.Max(Y-y,0),y-Y-Height); return dx*dx+dy*dy; }
}
