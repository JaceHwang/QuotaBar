using Forms=System.Windows.Forms;
namespace QuotaBar.Windows;
internal sealed class AppNotificationRouter : IDisposable {
    readonly Forms.NotifyIcon tray;
    readonly ExperienceNotificationQueue systemQueue=new();
    readonly NotificationPresentationState state=new();
    readonly Dictionary<string,ExperienceNotification> messages=[];
    readonly HashSet<string> receipted=[];
    readonly HashSet<BarkEventIdentity> semanticReceipts=[];
    public BarkNotificationController? Mobile { get; set; }
    public IEnumerable<ExperienceNotification> CurrentMessages=>messages.Values;
    readonly HashSet<string> previews=[];
    readonly HashSet<string> consumed=[];
    readonly HashSet<string> failedDeliveries=[];
    readonly DispatcherTimer nativeTimeout=new() { Interval=TimeSpan.FromSeconds(15) };
    readonly DispatcherTimer bubbleTimer=new() { Interval=TimeSpan.FromSeconds(1) };
    readonly Func<ExperienceNotification,bool> valid;
    readonly Action<ExperienceNotification> clicked,shown;
    ExperienceNotification? nativeActive;
    NotificationPresentationPreferences preferences=new();
    public bool PolicyActive { get; private set; }
    public NotificationPolicyPreferences PolicyPreferences { get; private set; }=new();
    NotificationPolicyStore? policyStore;
    LegacyNotificationPreferences? policyLegacy;
    public bool PolicyLoadFailed { get; private set; }
    public string? PolicyFailure { get; private set; }
    readonly Dictionary<BarkEventIdentity,NotificationDeliverySnapshot> snapshots=[];
    readonly Queue<BarkEventIdentity> snapshotOrder=[];
    public MessageCenterStore? MessageStore { get; private set; }
    string? currentMessageEpoch;
    public string? CurrentMessageEpoch { get=>currentMessageEpoch; set { if(currentMessageEpoch==value) return;currentMessageEpoch=value;MessageChanged(); } }
    public IReadOnlyList<MessageCenterRecord> MessageHistory=>MessageStore?.Records??[];
    public int MessageUnreadCount=>MessageStore?.UnreadCount??Unread.Count;
    public string? MessageStorageError=>MessageStore?.Error;
    public bool MessageHasUnpersistedMessages=>MessageStore?.HasUnpersistedMessages??false;
    public bool IsMessagePersisted(MessageCenterKey key)=>MessageStore?.IsPersisted(key)??false;
    public event Action? MessageCenterChanged;
    public Action? MessageDetailsRequested;
    void MessageChanged() { UnreadChanged?.Invoke();MessageCenterChanged?.Invoke(); }
    public void BindMessageCenter(MessageCenterStore store) {
        MessageStore=store;
        var active=messages.Values.Where(m=>valid(m)&&!previews.Contains(m.Id)).Select(MessageRecord).OfType<MessageCenterRecord>().ToArray();
        if(active.Length>0) store.Append(active);MessageChanged();
    }
    MessageCenterRecord? MessageRecord(ExperienceNotification message) {
        if(message.Kind==ExperienceNotificationKind.Test) return null;
        var category=message.Category??(message.Kind==ExperienceNotificationKind.Bank?NotificationCategory.BankExpiring72h:message.Kind==ExperienceNotificationKind.Update?NotificationCategory.UpdateAvailable:NotificationCategory.QuotaRecovered);
        HashSet<NotificationChannel> channels=[];
        if(message.Category!=null) {
            var threshold=message.ReminderThreshold??message.Warning?.Threshold??message.BankEvents?.FirstOrDefault()?.Stage;
            foreach(var channel in Enum.GetValues<NotificationChannel>()) if(NotificationPolicy.Decision(category,channel,PolicyPreferences,DateTimeOffset.UtcNow,threshold) is NotificationDecision.Allowed or NotificationDecision.Paused) channels.Add(channel);
        } else {
            if(preferences.UsesBubble) channels.Add(NotificationChannel.Bubble);if(preferences.UsesSystem) channels.Add(NotificationChannel.System);if(Mobile?.Preferences.Enabled==true) channels.Add(NotificationChannel.Mobile);
        }
        if(channels.Count==0) return null;
        return new(new(message.Id,message.ReminderGeneration,message.Epoch),category,message.Title,message.Body,message.CreatedAt.ToUnixTimeMilliseconds(),consumed.Contains(message.Id)?DateTimeOffset.UtcNow.ToUnixTimeMilliseconds():null,channels);
    }
    void CaptureMessage(ExperienceNotification message) { if(MessageStore is {} store&&MessageRecord(message) is {} row) { store.Append(row);MessageChanged(); } }
    void SaveLiveRead(ExperienceNotification message) { if(message.Kind!=ExperienceNotificationKind.Test&&!previews.Contains(message.Id)) MessageStore?.MarkRead(new(message.Id,message.ReminderGeneration,message.Epoch),DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()); }
    public bool MarkMessageRead(MessageCenterKey key) {
        var saved=MessageStore?.MarkRead(key,DateTimeOffset.UtcNow.ToUnixTimeMilliseconds())??false;
        if(saved&&messages.TryGetValue(key.Id,out var live)&&live.ReminderGeneration==key.Generation&&live.Epoch==key.Epoch) {
            consumed.Add(key.Id);var active=state.ActiveId==key.Id;state.Dismiss(key.Id,true);if(active) { HideBubble?.Invoke();bubbleTimer.Stop(); }
        }
        MessageChanged();return saved;
    }
    public bool MarkAllMessagesRead() {
        var saved=MessageStore?.MarkAllRead(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds())??false;
        if(saved) {
            var keys=MessageHistory.Select(r=>r.Key).ToHashSet();foreach(var live in messages.Values) if(keys.Contains(new(live.Id,live.ReminderGeneration,live.Epoch))) { consumed.Add(live.Id);state.Dismiss(live.Id,true); }
            HideBubble?.Invoke();bubbleTimer.Stop();
        }
        MessageChanged();return saved;
    }
    public bool RetryMessageStorage() { var saved=MessageStore?.Reload()??false;MessageChanged();return saved; }
    public bool OpenMessageLatest(MessageCenterRecord record) {
        var open=record.Category==NotificationCategory.UpdateAvailable?SystemUpdateRequested:MessageDetailsRequested;
        if(open is null) return false;open();MarkMessageRead(record.Key);return true;
    }
    public bool PolicyError { get; private set; }
    public Action? PolicyChanged;
    public bool LoadPolicy(NotificationPolicyStore store,LegacyNotificationPreferences? legacy) {
        // Retain the store even after failure: edits must never report an in-memory-only save.
        policyStore=store; policyLegacy=legacy;
        try {
            var p=store.LoadOrMigrate(legacy); PolicyLoadFailed=false; PolicyFailure=null; PolicyError=store.Corrupted; ApplyPolicy(p); return true;
        } catch(Exception e) when(e is System.IO.IOException or UnauthorizedAccessException) {
            PolicyLoadFailed=true; PolicyError=true; PolicyFailure=e.Message; return false;
        }
    }
    public bool RetryPolicy()=>policyStore is {} store&&LoadPolicy(store,policyLegacy);
    public bool ConfigurePolicy(NotificationPolicyPreferences value) {
        // A failed read may hide existing rules. Reload them before permitting a replacement.
        if(PolicyLoadFailed) return false;
        try { policyStore?.Save(value); } catch(Exception e) when(e is System.IO.IOException or UnauthorizedAccessException) { PolicyError=true; PolicyFailure=e.Message; return false; }
        PolicyError=false; PolicyFailure=null; ApplyPolicy(value); return true;
    }
    public bool SetChannelEnabled(NotificationChannel channel,bool enabled) {
        if(PolicyLoadFailed) return false;
        var channels=new HashSet<NotificationChannel>(PolicyPreferences.EnabledChannels); var oldMobile=Mobile?.Preferences.Enabled??false;
        if(channel==NotificationChannel.Mobile&&(Mobile is null||!Mobile.SetEnabled(enabled))) return false;
        if(enabled) channels.Add(channel); else channels.Remove(channel);
        if(ConfigurePolicy(PolicyPreferences with { EnabledChannels=channels })) return true;
        if(channel==NotificationChannel.Mobile) Mobile?.SetEnabled(oldMobile);
        return false;
    }
    void ApplyPolicy(NotificationPolicyPreferences value) {
        PolicyActive=true; PolicyPreferences=value;
        foreach(var snapshot in snapshots.Values) snapshot.Restrict(value,DateTimeOffset.UtcNow);
        foreach(var m in messages.Values.Where(m=>m.Category!=null||(m.Kind==ExperienceNotificationKind.Test&&!previews.Contains(m.Id))).ToArray()) {
            if(!ChannelAllowed(m,NotificationChannel.Bubble)) { var active=state.ActiveId==m.Id; state.Dismiss(m.Id,false); if(active) { HideBubble?.Invoke(); bubbleTimer.Stop(); } }
            if(!ChannelAllowed(m,NotificationChannel.System)) { systemQueue.CancelId(m.Id); if(nativeActive?.Id==m.Id) { nativeActive=null; if(SystemDelivery!=null) nativeTimeout.Stop(); } }
        }
        Mobile?.Revalidate(); PolicyChanged?.Invoke(); Dispatch(); DispatchSystem();
    }
    public void SendTestNotification(string title,string body) {
        if(stopped||PolicyPreferences.EnabledChannels.Count==0) return;
        Enqueue(new("channel-test-"+Guid.NewGuid(),ExperienceNotificationKind.Test,null,title,body,DateTimeOffset.UtcNow,DateTimeOffset.UtcNow.AddSeconds(30)));
        if(PolicyPreferences.EnabledChannels.Contains(NotificationChannel.Mobile)&&Mobile is {} mobile) _=mobile.Test(title,body);
    }
    bool ChannelAllowed(ExperienceNotification m,NotificationChannel channel) {
        if(m.Category is null && PolicyActive && m.Kind==ExperienceNotificationKind.Test) return PolicyPreferences.EnabledChannels.Contains(channel)&&(channel!=NotificationChannel.Bubble||!(PolicyPreferences.BubblePausedUntil>DateTimeOffset.UtcNow));
        if(m.Category is not {} category) return channel switch { NotificationChannel.Bubble=>preferences.UsesBubble&&!preferences.Paused(DateTimeOffset.UtcNow),NotificationChannel.System=>preferences.UsesSystem,_=>true };
        return snapshots.TryGetValue(new(m.Id,m.ReminderGeneration),out var snapshot)&&snapshot.Eligible(channel)&&NotificationPolicy.Decision(category,channel,PolicyPreferences,DateTimeOffset.UtcNow,m.ReminderThreshold??m.Warning?.Threshold??m.BankEvents?.FirstOrDefault()?.Stage)==NotificationDecision.Allowed;
    }
    bool CanStartChannel(ExperienceNotification m,NotificationChannel channel) {
        if(m.Category is null) return ChannelAllowed(m,channel);
        return snapshots.TryGetValue(new(m.Id,m.ReminderGeneration),out var snapshot)&&snapshot.Allows(channel,PolicyPreferences,DateTimeOffset.UtcNow);
    }
    void Snapshot(ExperienceNotification m) {
        if(m.Category is not {} category) return;
        var identity=new BarkEventIdentity(m.Id,m.ReminderGeneration);
        if(snapshots.ContainsKey(identity)) return;
        snapshots[identity]=new(category,PolicyPreferences,DateTimeOffset.UtcNow,m.ReminderThreshold??m.Warning?.Threshold??m.BankEvents?.FirstOrDefault()?.Stage); snapshotOrder.Enqueue(identity);
        if(snapshotOrder.Count>256) snapshots.Remove(snapshotOrder.Dequeue());
    }
    void RecordChannel(ExperienceNotification m,NotificationChannel channel) { if(snapshots.TryGetValue(new(m.Id,m.ReminderGeneration),out var snapshot)) snapshot.RecordAccepted(channel); }
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
        var retry=candidates.Where(id=>messages.ContainsKey(id)&&messages[id].Category==null&&!receipted.Contains(id)&&!consumed.Contains(id)).Select(id=>messages[id]).ToArray(); failedDeliveries.Clear();
        foreach(var m in retry) { CancelMessage(m.Id,false); if(valid(m)&&m.Valid(DateTimeOffset.UtcNow)) Enqueue(m); }
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
        if(stopped||messages.ContainsKey(message.Id)||!forceBubble&&!valid(message)||!message.Valid(DateTimeOffset.UtcNow)) return;
        if(!forceBubble) CaptureMessage(message);
        messages[message.Id]=message;
        if(messages.Count>128) { var oldest=messages.Values.Where(m=>m.Id!=state.ActiveId&&m.Id!=nativeActive?.Id).OrderBy(m=>m.CreatedAt).First(); messages.Remove(oldest.Id); receipted.Remove(oldest.Id); semanticReceipts.Remove(new(oldest.Id,oldest.ReminderGeneration)); }
        Snapshot(message);
        if(!forceBubble&&CanStartChannel(message,NotificationChannel.Mobile)) Mobile?.Enqueue(message,m=>valid(m)&&ChannelAllowed(m,NotificationChannel.Mobile),m=> { RecordChannel(m,NotificationChannel.Mobile); MobileReceipt(m); });
        if(CanStartChannel(message,NotificationChannel.Bubble)||forceBubble) state.Enqueue(message,canPresent,DateTimeOffset.UtcNow);
        if(CanStartChannel(message,NotificationChannel.System)&&!forceBubble) systemQueue.Enqueue(message);
        UnreadChanged?.Invoke(); Dispatch(); DispatchSystem();
    }
    void Receipt(ExperienceNotification message) { if(stopped||!messages.TryGetValue(message.Id,out var current)||current.DeliveryToken!=message.DeliveryToken||!valid(message)||!receipted.Add(message.Id)) return; SemanticReceipt(message); }
    void SemanticReceipt(ExperienceNotification message) { if(semanticReceipts.Add(new(message.Id,message.ReminderGeneration))) shown(message); }
    void MobileReceipt(ExperienceNotification message) { if(!stopped&&message.Valid(DateTimeOffset.UtcNow)&&valid(message)) SemanticReceipt(message); }
    void Dispatch() {
        if(stopped||!canPresent) return;
        while(state.Next(true,DateTimeOffset.UtcNow) is { } message) {
            if((!valid(message)||!ChannelAllowed(message,NotificationChannel.Bubble))&&!previews.Contains(message.Id)) { state.Dismiss(message.Id,false); continue; }
            if(PresentBubble?.Invoke(message)!=true) { state.Suspend(); break; }
            state.Shown(message.Id,DateTimeOffset.UtcNow); RecordChannel(message,NotificationChannel.Bubble); Receipt(message); bubbleTimer.Start(); break;
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
        if(read) { if(messages.TryGetValue(id,out var message)) SaveLiveRead(message);consumed.Add(id); }
        var active=state.ActiveId==id; state.Dismiss(id,read); previews.Remove(id); if(active) { bubbleTimer.Stop(); HideBubble?.Invoke(); } MessageChanged(); Dispatch();
    }
    public Action? SystemUpdateRequested;
    public void ActivateLatest(string id,string? token=null) { if(consumed.Contains(id)||!messages.TryGetValue(id,out var m)||token!=null&&token!=m.DeliveryToken) return; if(m.Kind==ExperienceNotificationKind.Update) { if(valid(m)) { Dismiss(id,true,token); SystemUpdateRequested?.Invoke(); } return; } Dismiss(id,true); clicked(m); }
    public void Activate(string id,string? token=null) { if(consumed.Contains(id)) return; if(token!=null&&(!messages.TryGetValue(id,out var d)||d.DeliveryToken!=token)) return; if(messages.TryGetValue(id,out var message)&&(valid(message)||previews.Contains(id))) { SaveLiveRead(message);consumed.Add(id); Receipt(message); Suspend(); state.Dismiss(id,true); MessageChanged(); clicked(message); } else Dismiss(id,true); }
    void DispatchSystem() {
        if(stopped||nativeTimeout.IsEnabled) return;
        while(systemQueue.Next(DateTimeOffset.UtcNow) is { } next) {
            if(!valid(next)||!ChannelAllowed(next,NotificationChannel.System)) continue;
            nativeActive=next; nativeTimeout.Start();
            try { if(SystemDelivery is { } send) send(next,success=> { if(stopped||!messages.TryGetValue(next.Id,out var current)||current.DeliveryToken!=next.DeliveryToken||!valid(next)) return; if(success && ChannelAllowed(next,NotificationChannel.System) && next.Valid(DateTimeOffset.UtcNow)) { RecordChannel(next,NotificationChannel.System); Receipt(next); } else if(!success) MarkFailed(next); if(nativeActive?.DeliveryToken==next.DeliveryToken) { nativeActive=null; nativeTimeout.Stop(); DispatchSystem(); } }); else tray.ShowBalloonTip(10000,next.Title,next.Body,Forms.ToolTipIcon.Info); }
            catch(InvalidOperationException) { nativeActive=null; nativeTimeout.Stop(); MarkFailed(next); continue; }
            break;
        }
    }
    void Shown(object? sender,EventArgs e) { if(nativeActive is { } m&&m.Valid(DateTimeOffset.UtcNow)&&ChannelAllowed(m,NotificationChannel.System)) { RecordChannel(m,NotificationChannel.System); Receipt(m); } }
    void Clicked(object? sender,EventArgs e) { if(nativeActive is { } m) { if(m.Kind==ExperienceNotificationKind.Update) { if(valid(m)) { Dismiss(m.Id,true,m.DeliveryToken); SystemUpdateRequested?.Invoke(); } } else Activate(m.Id,m.DeliveryToken); } nativeActive=null; /* cooldown guards trailing native events */ }
    void Closed(object? sender,EventArgs e) { if(nativeActive is { } m&&!receipted.Contains(m.Id)) MarkFailed(m); nativeActive=null; }
    public void CancelMessage(string id,bool cancelMobile=true) {
        if(cancelMobile) Mobile?.Cancel(id);
        var active=state.ActiveId==id; state.Forget(id); systemQueue.CancelId(id); messages.Remove(id); receipted.Remove(id); previews.Remove(id); consumed.Remove(id); failedDeliveries.Remove(id);
        if(nativeActive?.Id==id) { nativeActive=null; if(SystemDelivery!=null) nativeTimeout.Stop(); }
        if(active) { HideBubble?.Invoke(); bubbleTimer.Stop(); } UnreadChanged?.Invoke();
    }
    public void CancelAuthenticationEpoch(string epoch) {
        Mobile?.CancelAuthenticationEpoch(epoch);
        systemQueue.Cancel(epoch); var active=state.ActiveId;
        state.Cancel(epoch); foreach(var id in messages.Values.Where(m=>m.Epoch==epoch).Select(m=>m.Id).ToArray()) { messages.Remove(id); receipted.Remove(id); consumed.Remove(id); failedDeliveries.Remove(id); }
        if(nativeActive?.Epoch==epoch) nativeActive=null;
        if(active!=state.ActiveId) { HideBubble?.Invoke(); bubbleTimer.Stop(); }
        UnreadChanged?.Invoke(); Dispatch();
    }
    public void Dispose() { if(stopped) return; stopped=true; Mobile?.Dispose(); semanticReceipts.Clear(); state.Stop(); nativeTimeout.Stop(); bubbleTimer.Stop(); nativeActive=null; HideBubble?.Invoke(); messages.Clear(); receipted.Clear(); previews.Clear(); consumed.Clear(); failedDeliveries.Clear(); tray.BalloonTipClicked-=Clicked; tray.BalloonTipShown-=Shown; tray.BalloonTipClosed-=Closed; }
}
