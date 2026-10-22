using Forms=System.Windows.Forms;
namespace QuotaBar.Windows;
internal sealed class AppNotificationRouter : IDisposable {
    readonly Forms.NotifyIcon tray;
    readonly ExperienceNotificationQueue systemQueue=new();
    readonly NotificationPresentationState state=new();
    readonly Dictionary<string,ExperienceNotification> messages=[];
    readonly HashSet<string> receipted=[];
    readonly HashSet<string> previews=[];
    readonly HashSet<string> consumed=[];
    readonly HashSet<string> failedDeliveries=[];
    readonly DispatcherTimer nativeTimeout=new() { Interval=TimeSpan.FromSeconds(15) };
    readonly DispatcherTimer bubbleTimer=new() { Interval=TimeSpan.FromSeconds(1) };
    readonly Func<ExperienceNotification,bool> valid;
    readonly Action<ExperienceNotification> clicked,shown;
    ExperienceNotification? nativeActive;
    NotificationPresentationPreferences preferences=new();
    bool stopped,canPresent;
    public Action? Failed,HideBubble,UnreadChanged;
    public Func<ExperienceNotification,bool>? PresentBubble;
    internal Action<ExperienceNotification,Action<bool>>? SystemDelivery;
    public bool HasActiveBubble=>state.ActiveId!=null;
    public IReadOnlyList<NotificationUnreadItem> Unread=>state.Unread(DateTimeOffset.UtcNow).Where(i=>!i.Message.Id.StartsWith("preview-",StringComparison.Ordinal)).Select(i=>i with { Stale=i.Stale||!valid(i.Message) }).ToArray();
    public AppNotificationRouter(Forms.NotifyIcon tray,Func<ExperienceNotification,bool> valid,Action<ExperienceNotification> clicked,Action<ExperienceNotification> shown) {
        this.tray=tray; this.valid=valid; this.clicked=clicked; this.shown=shown;
        tray.BalloonTipClicked+=Clicked; tray.BalloonTipShown+=Shown; tray.BalloonTipClosed+=Closed;
        nativeTimeout.Tick+=(_,_)=> { nativeTimeout.Stop(); if(nativeActive is { } pending&&!receipted.Contains(pending.Id)) MarkFailed(pending); nativeActive=null; DispatchSystem(); };
        bubbleTimer.Tick+=(_,_)=>Tick();
    }
    public void Configure(NotificationPresentationPreferences value) { if(preferences==value) return; var channelChanged=preferences.Mode!=value.Mode; preferences=value; while(systemQueue.Next(DateTimeOffset.UtcNow)!=null) { } nativeActive=null; if(SystemDelivery!=null) nativeTimeout.Stop(); Suspend(); RetryFailedDeliveries(channelChanged); Dispatch(); }
    public void RetryFailedDeliveries(bool allUndelivered=false) {
        var candidates=allUndelivered?messages.Keys.ToArray():failedDeliveries.ToArray();
        var retry=candidates.Where(id=>messages.ContainsKey(id)&&!receipted.Contains(id)&&!consumed.Contains(id)).Select(id=>messages[id]).ToArray(); failedDeliveries.Clear();
        foreach(var m in retry) { CancelMessage(m.Id); if(valid(m)&&m.Valid(DateTimeOffset.UtcNow)) Enqueue(m); }
    }
    void MarkFailed(ExperienceNotification m) { if(!receipted.Contains(m.Id)) failedDeliveries.Add(m.Id); Failed?.Invoke(); }
    public void UpdateEnvironment(bool visible) { canPresent=visible; if(!visible) Suspend(); else Dispatch(); }
    public bool Preview(ExperienceNotification message) {
        if(!canPresent||stopped) return false;
        Suspend(); foreach(var item in state.Unread(DateTimeOffset.UtcNow)) state.Dismiss(item.Message.Id,false);
        previews.Add(message.Id); Enqueue(message,true); return state.ActiveId==message.Id;
    }
    public void Enqueue(ExperienceNotification message)=>Enqueue(message,false);
    void Enqueue(ExperienceNotification input,bool forceBubble) {
        var message=input with { DeliveryToken=Guid.NewGuid().ToString() };
        if(stopped||preferences.Mode==NotificationDeliveryMode.Off&&!forceBubble||messages.ContainsKey(message.Id)||!forceBubble&&!valid(message)||!message.Valid(DateTimeOffset.UtcNow)) return;
        messages[message.Id]=message;
        if(messages.Count>128) { var oldest=messages.Values.Where(m=>m.Id!=state.ActiveId&&m.Id!=nativeActive?.Id).OrderBy(m=>m.CreatedAt).First(); messages.Remove(oldest.Id); receipted.Remove(oldest.Id); }
        if(preferences.UsesBubble||forceBubble) state.Enqueue(message,canPresent&&(!preferences.Paused(DateTimeOffset.UtcNow)||forceBubble),DateTimeOffset.UtcNow);
        if(preferences.UsesSystem&&!forceBubble) systemQueue.Enqueue(message);
        UnreadChanged?.Invoke(); Dispatch(); DispatchSystem();
    }
    void Receipt(ExperienceNotification message) { if(stopped||!messages.TryGetValue(message.Id,out var current)||current.DeliveryToken!=message.DeliveryToken||!valid(message)||!receipted.Add(message.Id)) return; shown(message); }
    void Dispatch() {
        if(stopped||(!preferences.UsesBubble||preferences.Paused(DateTimeOffset.UtcNow))&&previews.Count==0||!canPresent) return;
        while(state.Next(true,DateTimeOffset.UtcNow) is { } message) {
            if(!valid(message)&&!previews.Contains(message.Id)) { state.Dismiss(message.Id,false); continue; }
            if(PresentBubble?.Invoke(message)!=true) { state.Suspend(); break; }
            state.Shown(message.Id,DateTimeOffset.UtcNow); Receipt(message); bubbleTimer.Start(); break;
        }
    }
    void Tick() {
        if(state.ActiveId is { } id&&(!messages.TryGetValue(id,out var m)||!valid(m)&&!previews.Contains(id))) { state.Dismiss(id,false); HideBubble?.Invoke(); }
        if(state.Tick(DateTimeOffset.UtcNow)) { previews.Clear(); HideBubble?.Invoke(); UnreadChanged?.Invoke(); }
        if(state.ActiveId==null) { bubbleTimer.Stop(); Dispatch(); }
    }
    public void ObserveQuota(QuotaObservation observation) {
        if(!state.ObserveQuota(observation,DateTimeOffset.UtcNow)) return;
        previews.Clear(); bubbleTimer.Stop(); HideBubble?.Invoke(); UnreadChanged?.Invoke(); Dispatch();
    }
    public void SetInteracting(bool value)=>state.SetInteracting(value,DateTimeOffset.UtcNow);
    public void Suspend() { previews.Clear(); state.Suspend(); bubbleTimer.Stop(); HideBubble?.Invoke(); }
    public void Dismiss(string id,bool read,string? token=null) {
        if(token!=null&&(!messages.TryGetValue(id,out var d)||d.DeliveryToken!=token)) return;
        if(read) consumed.Add(id);
        var active=state.ActiveId==id; state.Dismiss(id,read); previews.Remove(id); if(active) { bubbleTimer.Stop(); HideBubble?.Invoke(); } UnreadChanged?.Invoke(); Dispatch();
    }
    public void ActivateLatest(string id,string? token=null) { if(consumed.Contains(id)||!messages.TryGetValue(id,out var m)||token!=null&&token!=m.DeliveryToken) return; if(m.Kind==ExperienceNotificationKind.Update) { Activate(id); return; } Dismiss(id,true); clicked(m); }
    public void Activate(string id,string? token=null) { if(consumed.Contains(id)) return; if(token!=null&&(!messages.TryGetValue(id,out var d)||d.DeliveryToken!=token)) return; if(messages.TryGetValue(id,out var message)&&(valid(message)||previews.Contains(id))) { consumed.Add(id); Receipt(message); Suspend(); state.Dismiss(id,true); UnreadChanged?.Invoke(); clicked(message); } else Dismiss(id,true); }
    void DispatchSystem() {
        if(stopped||!preferences.UsesSystem||nativeTimeout.IsEnabled) return;
        while(systemQueue.Next(DateTimeOffset.UtcNow) is { } next) {
            if(!valid(next)) continue;
            nativeActive=next; nativeTimeout.Start();
            try { if(SystemDelivery is { } send) send(next,success=> { if(stopped||!messages.TryGetValue(next.Id,out var current)||current.DeliveryToken!=next.DeliveryToken||!valid(next)) return; if(success && preferences.UsesSystem && next.Valid(DateTimeOffset.UtcNow)) Receipt(next); else if(!success) MarkFailed(next); if(nativeActive?.DeliveryToken==next.DeliveryToken) { nativeActive=null; nativeTimeout.Stop(); DispatchSystem(); } }); else tray.ShowBalloonTip(10000,next.Title,next.Body,Forms.ToolTipIcon.Info); }
            catch(InvalidOperationException) { nativeActive=null; nativeTimeout.Stop(); MarkFailed(next); continue; }
            break;
        }
    }
    void Shown(object? sender,EventArgs e) { if(nativeActive is { } m&&m.Valid(DateTimeOffset.UtcNow)) Receipt(m); }
    void Clicked(object? sender,EventArgs e) { if(nativeActive is { } m) Activate(m.Id,m.DeliveryToken); nativeActive=null; /* cooldown guards trailing native events */ }
    void Closed(object? sender,EventArgs e) { if(nativeActive is { } m&&!receipted.Contains(m.Id)) MarkFailed(m); nativeActive=null; }
    public void CancelMessage(string id) {
        var active=state.ActiveId==id; state.Forget(id); systemQueue.CancelId(id); messages.Remove(id); receipted.Remove(id); previews.Remove(id); consumed.Remove(id); failedDeliveries.Remove(id);
        if(nativeActive?.Id==id) { nativeActive=null; if(SystemDelivery!=null) nativeTimeout.Stop(); }
        if(active) { HideBubble?.Invoke(); bubbleTimer.Stop(); } UnreadChanged?.Invoke();
    }
    public void CancelAuthenticationEpoch(string epoch) {
        systemQueue.Cancel(epoch); var active=state.ActiveId;
        state.Cancel(epoch); foreach(var id in messages.Values.Where(m=>m.Epoch==epoch).Select(m=>m.Id).ToArray()) { messages.Remove(id); receipted.Remove(id); consumed.Remove(id); failedDeliveries.Remove(id); }
        if(nativeActive?.Epoch==epoch) nativeActive=null;
        if(active!=state.ActiveId) { HideBubble?.Invoke(); bubbleTimer.Stop(); }
        UnreadChanged?.Invoke(); Dispatch();
    }
    public void Dispose() { if(stopped) return; stopped=true; state.Stop(); nativeTimeout.Stop(); bubbleTimer.Stop(); nativeActive=null; HideBubble?.Invoke(); messages.Clear(); receipted.Clear(); previews.Clear(); consumed.Clear(); failedDeliveries.Clear(); tray.BalloonTipClicked-=Clicked; tray.BalloonTipShown-=Shown; tray.BalloonTipClosed-=Closed; }
}
