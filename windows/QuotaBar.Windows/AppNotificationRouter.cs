using Forms=System.Windows.Forms;
namespace QuotaBar.Windows;
internal sealed class AppNotificationRouter : IDisposable {
    readonly Forms.NotifyIcon tray;
    readonly ExperienceNotificationQueue queue=new();
    readonly DispatcherTimer timeout=new() { Interval=TimeSpan.FromSeconds(15) };
    readonly Func<ExperienceNotification,bool> valid;
    readonly Action<ExperienceNotification> clicked,shown;
    ExperienceNotification? active;
    public Action? Failed { get; set; }
    bool stopped;
    public AppNotificationRouter(Forms.NotifyIcon tray,Func<ExperienceNotification,bool> valid,Action<ExperienceNotification> clicked,Action<ExperienceNotification> shown) {
        this.tray=tray; this.valid=valid; this.clicked=clicked; this.shown=shown;
        tray.BalloonTipClicked+=Clicked; tray.BalloonTipShown+=Shown; tray.BalloonTipClosed+=Closed; timeout.Tick+=(_,_)=>Complete();
    }
    public void Enqueue(ExperienceNotification message) { if(stopped) return; queue.Enqueue(message); Dispatch(); }
    void Dispatch() {
        if(stopped || active is not null || timeout.IsEnabled) return;
        while(queue.Next(DateTimeOffset.UtcNow) is { } next) {
            if(!valid(next)) continue;
            active=next; timeout.Start();
            try { tray.ShowBalloonTip(10000,next.Title,next.Body,Forms.ToolTipIcon.Info); }
            catch(InvalidOperationException) { active=null; timeout.Stop(); Failed?.Invoke(); continue; }
            break;
        }
    }
    void Shown(object? sender,EventArgs e) { if(active is { } message && valid(message)) shown(message); }
    void Clicked(object? sender,EventArgs e) { if(active is { } message) clicked(message); Complete(); }
    void Closed(object? sender,EventArgs e)=>Complete();
    void Complete() { timeout.Stop(); active=null; Dispatch(); }
    public void CancelAuthenticationEpoch(string epoch) {
        queue.Cancel(epoch);
        if(active?.Epoch==epoch) { active=null; /* leave timeout running so a trailing native click cannot route to the next message */ }
    }
    public void Dispose() { stopped=true; timeout.Stop(); active=null; tray.BalloonTipClicked-=Clicked; tray.BalloonTipShown-=Shown; tray.BalloonTipClosed-=Closed; }
}
