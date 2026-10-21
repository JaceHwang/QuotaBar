namespace QuotaBar.Windows;
internal sealed class QuotaExperienceController {
    readonly Coordinator owner;
    readonly QuotaExperienceStore store;
    readonly QuotaExperienceEngine engine;
    QuotaObservation? lastObservation;
    long sequence;
    TextBlock? statusLabel;
    bool storageReady;
    public QuotaExperienceController(Coordinator owner,string root) {
        this.owner=owner; store=new(Path.Combine(root,"experience-state.json")); var state=store.Load(); engine=new(state,store.Corrupted); engine.Configure(owner.Preferences.Experience); Persist();
    }
    ExperienceCopy Copy=>new(owner.Preferences.Language);
    bool Persist() {
        try { store.Save(engine.State); storageReady=true; return true; }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException) { storageReady=false; Status(Copy.Text("Could not save reminder state; no alert sent","无法保存提醒状态，本次未发提醒","無法儲存提醒狀態，本次未發提醒")); return false; }
    }
    void Status(string text) { if(statusLabel is not null) statusLabel.Text=text; }
    public void NotificationFailed()=>Status(Copy.Text("System notifications unavailable; check system settings","系统提醒不可用，请检查系统设置","系統提醒不可用，請檢查系統設定"));
    public void Configure() { engine.Configure(owner.Preferences.Experience); if(!engine.Preferences.Celebration) owner.CancelCelebration(); }
    public void ResetBaseline() { owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); engine.ResetBaseline(); lastObservation=null; owner.CancelCelebration(); }
    public void ClearAccount() {
        owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); engine.RotateEpoch(); sequence=0; lastObservation=null; owner.CancelCelebration(); Persist();
    }
    public void Receive(QuotaObservation observation) {
        var o=observation with { Epoch=engine.State.Epoch,Sequence=++sequence }; lastObservation=o;
        var result=engine.Observe(o,DateTimeOffset.UtcNow);
        if(!Persist()) return;
        if(result.Recoveries.Count>0) {
            if(engine.Preferences.Celebration) owner.PreviewCelebration();
            if(engine.Preferences.Recovery) Enqueue(ExperienceNotificationKind.Recovery,Copy.Text("Quota restored","额度已恢复","額度已恢復"),Copy.RecoveryBody(o.Quota));
        }
        if(result.Bank.Count>0) Enqueue(ExperienceNotificationKind.Bank,Copy.Text("Bank credits expiring","Bank 权益即将到期","Bank 權益即將到期"),Copy.BankBody(result.Bank),result.Bank.Min(e=>e.ExpiresAt),result.Bank);
    }
    void Enqueue(ExperienceNotificationKind kind,string title,string body,DateTimeOffset? expires=null,IReadOnlyList<BankExpiryEvent>? bank=null) {
        var deadline=kind==ExperienceNotificationKind.Bank?(expires<DateTimeOffset.UtcNow.AddSeconds(120)?expires:DateTimeOffset.UtcNow.AddSeconds(120)):null;
        owner.Notifications.Enqueue(new("quotabar-"+Guid.NewGuid(),kind,engine.State.Epoch,title,body,DateTimeOffset.UtcNow,deadline,bank));
    }
    public bool Valid(ExperienceNotification message) {
        if(!storageReady || message.Epoch!=engine.State.Epoch) return false;
        if(message.Kind==ExperienceNotificationKind.Test) return true;
        if(message.Kind==ExperienceNotificationKind.Recovery) return engine.Preferences.Recovery;
        return engine.Preferences.Bank && lastObservation is { } o && message.BankEvents is { } events && engine.BankEventsAreCurrent(events,o,DateTimeOffset.UtcNow);
    }
    public void Stop() { owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); owner.CancelCelebration(); }
    public void TestNotification()=>Enqueue(ExperienceNotificationKind.Test,"QuotaBar "+Copy.Text("test notification","测试通知","測試通知"),Copy.Text("Example only — your quota and reminder history are unchanged.","这是一条示例通知，不改变真实额度及提醒记录。","這是一條範例通知，不改變真實額度及提醒記錄。"));
    public UIElement MakeSettingsView() {
        var copy=owner.Copy; var p=owner.Preferences.Experience; var stack=new StackPanel(); var fg=Ui.Foreground(Platform.IsDark(owner.Preferences));
        stack.Children.Add(new Separator { Margin=new Thickness(0,12,0,8) });
        stack.Children.Add(Ui.Text(copy.Text("Quota moods and reminders","额度表情与提醒","額度表情與提醒"),13,fg));
        var titles=new[]{copy.Text("Quota mood mode","额度表情模式","額度表情模式"),copy.Text("Notify when quota is restored","额度恢复时提醒","額度恢復時提醒"),copy.Text("Celebrate quota recovery","额度恢复时播放小庆祝","額度恢復時播放小慶祝"),copy.Text("Bank expiry reminders","Bank 到期提醒","Bank 到期提醒")};
        var values=new[]{p.Moods,p.Recovery,p.Celebration,p.Bank};
        for(var i=0;i<4;i++) {
            var index=i; var box=new CheckBox { Content=titles[i],IsChecked=values[i],Margin=new Thickness(0,4,0,4),Foreground=fg };
            box.Click+=(_,_)=> {
                var next=owner.Preferences.Experience; var on=box.IsChecked==true;
                next=index switch { 0=>next with { Moods=on },1=>next with { Recovery=on },2=>next with { Celebration=on },_=>next with { Bank=on } };
                owner.Save(owner.Preferences with { Experience=next },false);
            }; stack.Children.Add(box);
        }
        var note=Ui.Text(copy.Text("Bank: 72 and 24 hours before expiry. Celebrations play only while the floating button is visible.","Bank 提前72小时和24小时提醒，同批合并。小庆祝仅在悬浮按钮可见时播放。","Bank 提前72小時和24小時提醒，同批合併。小慶祝僅在懸浮按鈕可見時播放。"),11,fg); note.TextWrapping=TextWrapping.Wrap; stack.Children.Add(note);
        var row=new WrapPanel(); row.Children.Add(Ui.Button(copy.Text("Preview celebration","预览庆祝","預覽慶祝"),owner.PreviewCelebration)); row.Children.Add(Ui.Button(copy.Text("Send test notification","发送测试通知","傳送測試通知"),TestNotification)); stack.Children.Add(row);
        statusLabel=Ui.Text("",11,fg); stack.Children.Add(statusLabel); return stack;
    }
}
