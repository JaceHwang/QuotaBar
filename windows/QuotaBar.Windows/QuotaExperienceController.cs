namespace QuotaBar.Windows;
internal sealed class QuotaExperienceController {
    readonly Coordinator owner;
    readonly QuotaExperienceStore store;
    readonly QuotaExperienceEngine engine;
    readonly QuotaWarningStore warningStore;
    QuotaWarningEngine warningEngine;
    HashSet<NotificationCategory> warningCategories=[];
    HashSet<int>? bankHours;
    QuotaObservation? lastObservation;
    long sequence;
    TextBlock? statusLabel;
    bool storageReady;
    enum SettingsStatus { None, StorageUnavailable, NotificationsUnavailable }
    SettingsStatus settingsStatus;
    string CurrentStatus=>settingsStatus switch {
        SettingsStatus.StorageUnavailable=>Copy.Text("Could not save reminder state; no alert sent","无法保存提醒状态，本次未发提醒","無法儲存提醒狀態，本次未發提醒"),
        SettingsStatus.NotificationsUnavailable=>Copy.Text("System notifications unavailable; check system settings","系统提醒不可用，请检查系统设置","系統提醒不可用，請檢查系統設定"),
        _=>""
    };
    public QuotaExperienceController(Coordinator owner,string root) {
        this.owner=owner; warningStore=new(Path.Combine(root,"warning-state.json")); warningEngine=new(warningStore.Load()); store=new(Path.Combine(root,"experience-state.json")); var state=store.Load(); engine=new(state,store.Corrupted); engine.Configure(owner.Preferences.Experience); Persist();
    }
    ExperienceCopy Copy=>new(owner.Preferences.Language);
    bool Persist() {
        try { store.Save(engine.State); warningStore.Save(warningEngine.State); storageReady=true; if(settingsStatus==SettingsStatus.StorageUnavailable) Status(SettingsStatus.None); return true; }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException) { storageReady=false; Status(SettingsStatus.StorageUnavailable); return false; }
    }
    void Status(SettingsStatus status) { settingsStatus=status; if(statusLabel is not null) statusLabel.Text=CurrentStatus; }
    public void NotificationFailed()=>Status(SettingsStatus.NotificationsUnavailable);
    bool HasRule(NotificationCategory category)=>category is NotificationCategory.BankExpiring72h or NotificationCategory.BankExpiring24h?owner.Notifications.PolicyPreferences.ConfiguredBankHours.Any(h=>owner.Notifications.PolicyPreferences.BankChannels(h).Count>0):owner.Notifications.PolicyPreferences.Rules.TryGetValue(category,out var channels)&&channels.Count>0;
    public void Configure() {
        var p=owner.Preferences.Experience;
        if(owner.Notifications.PolicyActive) {
            p=p with { Recovery=HasRule(NotificationCategory.QuotaRecovered)||HasRule(NotificationCategory.QuotaExhausted),Bank=true };
            var selectedBank=owner.Notifications.PolicyPreferences.ConfiguredBankHours.Where(h=>owner.Notifications.PolicyPreferences.BankChannels(h).Count>0).ToHashSet();
            if(bankHours is {} previousBank) { var added=selectedBank.Except(previousBank).ToArray(); if(added.Length>0) { engine.SuppressBankStages(added); Persist(); } }
            bankHours=selectedBank;
            var categories=new[]{NotificationCategory.QuotaLow,NotificationCategory.QuotaExhausted}.Where(HasRule).ToHashSet();
            if(categories.Contains(NotificationCategory.QuotaExhausted)!=warningCategories.Contains(NotificationCategory.QuotaExhausted)) warningEngine.ResetBaseline();
            warningCategories=categories;
            warningEngine.ConfigureLowThresholds(HasRule(NotificationCategory.QuotaLow)?owner.Notifications.PolicyPreferences.ConfiguredLowThresholds:[]);
        }
        engine.Configure(p); if(!engine.Preferences.Celebration) owner.CancelCelebration(); }
    public void ResetBaseline() { owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); engine.ResetBaseline(); warningEngine.ResetBaseline(); lastObservation=null; owner.CancelCelebration(); }
    public void ClearAccount() {
        owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); engine.RotateEpoch(); warningEngine=new(); sequence=0; lastObservation=null; owner.CancelCelebration(); Persist();
    }
    public void Receive(QuotaObservation observation) {
        Configure();
        var o=observation with { Epoch=engine.State.Epoch,Sequence=++sequence }; lastObservation=o; owner.Notifications.ObserveQuota(o);
        var result=engine.Observe(o,DateTimeOffset.UtcNow,owner.Notifications.PolicyActive?owner.Notifications.PolicyPreferences.ConfiguredBankHours:null);
        var warnings=owner.Notifications.PolicyActive?warningEngine.Observe(o,owner.Notifications.PolicyPreferences.ConfiguredLowThresholds,DateTimeOffset.UtcNow):Array.Empty<QuotaWarningEvent>();
        warningEngine.ConfirmRecovery(result.Recoveries);
        if(!Persist()) return;
        foreach(var warning in warnings) Enqueue(ExperienceNotificationKind.Recovery,warning.Category==NotificationCategory.QuotaLow?Copy.Text("Quota low","额度偏低","額度偏低"):Copy.Text("Quota depleted","额度已耗尽","額度已耗盡"),Copy.RecoveryBody(o.Quota),category:warning.Category,warning:warning);
        if(result.Recoveries.Count>0) {
            if(engine.Preferences.Celebration) owner.PreviewCelebration();
            if(owner.Notifications.PolicyActive?HasRule(NotificationCategory.QuotaRecovered):engine.Preferences.RecoveryNotificationsEnabled) Enqueue(ExperienceNotificationKind.Recovery,Copy.Text("Quota restored","额度已恢复","額度已恢復"),Copy.RecoveryBody(o.Quota),category:owner.Notifications.PolicyActive?NotificationCategory.QuotaRecovered:null);
        }
        if(owner.Notifications.PolicyActive) {
            foreach(var stage in owner.Notifications.PolicyPreferences.ConfiguredBankHours) {
                var events=result.Bank.Where(e=>e.Stage==stage).ToArray();
                if(events.Length>0) Enqueue(ExperienceNotificationKind.Bank,Copy.Text("Bank credits expiring","Bank 权益即将到期","Bank 權益即將到期"),Copy.BankBody(events),events.Min(e=>e.ExpiresAt),events,stage==24?NotificationCategory.BankExpiring24h:NotificationCategory.BankExpiring72h);
            }
        } else if(result.Bank.Count>0) Enqueue(ExperienceNotificationKind.Bank,Copy.Text("Bank credits expiring","Bank 权益即将到期","Bank 權益即將到期"),Copy.BankBody(result.Bank),result.Bank.Min(e=>e.ExpiresAt),result.Bank);
    }
    void Enqueue(ExperienceNotificationKind kind,string title,string body,DateTimeOffset? expires=null,IReadOnlyList<BankExpiryEvent>? bank=null,NotificationCategory? category=null,QuotaWarningEvent? warning=null) {
        var deadline=kind==ExperienceNotificationKind.Bank?(expires<DateTimeOffset.UtcNow.AddSeconds(120)?expires:DateTimeOffset.UtcNow.AddSeconds(120)):null;
        owner.Notifications.Enqueue(new(warning is null?"quotabar-"+Guid.NewGuid():"quotabar-warning-"+warning.IncidentID,kind,engine.State.Epoch,title,body,DateTimeOffset.UtcNow,warning is null?deadline:DateTimeOffset.UtcNow.AddSeconds(120),bank,Category:category,Warning:warning,ReminderThreshold:warning?.Threshold??bank?.FirstOrDefault()?.Stage));
    }
    public bool Valid(ExperienceNotification message) {
        if(message.Kind==ExperienceNotificationKind.Test) return true;
        if(!storageReady || message.Epoch!=engine.State.Epoch) return false;
        if(message.Warning is {} warning) {
            if(warning.Category==NotificationCategory.QuotaLow&&!owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.Contains(warning.Threshold)) return false;
            if(lastObservation is not {} latest||(DateTimeOffset.UtcNow-latest.ReceivedAt).TotalSeconds>120) return false;
            return warning.PeriodIDs.Any(id=> { var w=id=="primary"?latest.Quota.Primary:latest.Quota.Secondary; return w is not null&&(warning.Category==NotificationCategory.QuotaExhausted?w.UsedPercent>=100:w.UsedPercent>=100-warning.Threshold&&w.UsedPercent<100); });
        }
        if(message.Kind==ExperienceNotificationKind.Recovery) return owner.Notifications.PolicyActive?HasRule(NotificationCategory.QuotaRecovered):engine.Preferences.RecoveryNotificationsEnabled;
        return (owner.Notifications.PolicyActive?message.Category is {} c&&HasRule(c):engine.Preferences.Bank) && lastObservation is { } o && message.BankEvents is { } events && engine.BankEventsAreCurrent(events,o,DateTimeOffset.UtcNow,owner.Notifications.PolicyActive?owner.Notifications.PolicyPreferences.ConfiguredBankHours:null);
    }
    public void Stop() { owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); owner.CancelCelebration(); }
    public void PreviewCelebration() {
        owner.PreviewCelebration();
        owner.Notifications.Preview(new("preview-"+Guid.NewGuid(),ExperienceNotificationKind.Test,null,Copy.Text("Example notification","示例通知","範例通知"),Copy.Text("Example only. Quota and reminder history are unchanged.","仅为示例，不改变真实额度及提醒记录。","僅為範例，不改變真實額度及提醒記錄。"),DateTimeOffset.UtcNow));
    }
    public void TestNotification()=>SendTest("QuotaBar "+Copy.Text("test notification","测试通知","測試通知"),Copy.Text("Example only — your quota and reminder history are unchanged.","这是一条示例通知，不改变真实额度及提醒记录。","這是一條範例通知，不改變真實額度及提醒記錄。"));
    void SendTest(string title,string body) {
        if(owner.Notifications.PolicyActive) owner.Notifications.SendTestNotification(title,body);
        else Enqueue(ExperienceNotificationKind.Test,title,body);
    }
    public UIElement MakeSettingsView() {
        var copy=owner.Copy; var p=owner.Preferences.Experience; var stack=new StackPanel(); var dark=Platform.IsDark(owner.Preferences); var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark);
        stack.Children.Add(new NotificationSettingsView(owner));
        var rows=new StackPanel();
        var titles=new[]{copy.Text("Quota mood mode","额度表情模式","額度表情模式"),copy.Text("Notify when quota is restored","额度恢复时提醒","額度恢復時提醒"),copy.Text("Celebrate quota recovery","额度恢复时播放小庆祝","額度恢復時播放小慶祝"),copy.Text("Bank expiry reminders","Bank 到期提醒","Bank 到期提醒")};
        var hints=new[]{copy.Text("Show the battery character for your current quota.","根据当前额度状态，显示对应的电池表情。","根據目前額度狀態，顯示對應的電池表情。"),copy.Text("A reminder after confirmed recovery.","额度确认恢复时，按所选方式提醒。","額度確認恢復時，依所選方式提醒。"),copy.Text("A brief animation, independent of reminders.","播放短暂庆祝，与提醒独立。","播放短暫慶祝，與提醒獨立。"),copy.Text("Known credits only; never redeem automatically.","仅提醒已知权益，不会自动兑换。","僅提醒已知權益，不會自動兌換。")};
        var values=new[]{p.Moods,p.Recovery,p.Celebration,p.Bank};
        foreach(var i in new[]{0,2}) {
            var index=i; var row=new StackPanel { Margin=new Thickness(0,8,0,12) };
            row.Children.Add(SettingsVisual.Toggle(titles[i],values[i],fg,on=> {
                var next=owner.Preferences.Experience;
                next=index switch { 0=>next with { Moods=on },1=>next with { Recovery=on },2=>next with { Celebration=on },_=>next with { Bank=on } };
                owner.Save(owner.Preferences with { Experience=next },false);
            }));
            var hint=Ui.Text(hints[i],11,muted); hint.TextWrapping=TextWrapping.Wrap; hint.Margin=new Thickness(0,0,0,10); row.Children.Add(hint);
            UIElement right;
            if(i==0) {
                var legend=new System.Windows.Controls.Primitives.UniformGrid { Columns=5,Width=360,HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Center };
                var states=new[]{QuotaMood.Good,QuotaMood.Low,QuotaMood.Exhausted,QuotaMood.Unavailable,QuotaMood.Recovered};
                var labels=new[]{copy.Text("Good","充足","充足"),copy.Text("Low","偏低","偏低"),copy.Text("Empty","耗尽","耗盡"),copy.Text("Unavailable","不可用","無法使用"),copy.Text("Restored","恢复","恢復")};
                for(var j=0;j<states.Length;j++) {
                    var item=new StackPanel { HorizontalAlignment=HorizontalAlignment.Center,Margin=new Thickness(2,0,2,0) }; var icon=new QuotaMoodView { Width=36,Height=36,Mood=states[j],Dark=dark,Stars=states[j]==QuotaMood.Recovered };
                    System.Windows.Automation.AutomationProperties.SetName(icon,Copy.MoodLabel(states[j])); item.Children.Add(icon);
                    var label=Ui.Text(labels[j],10,fg); label.HorizontalAlignment=HorizontalAlignment.Center; label.Margin=new Thickness(0,5,0,0); item.Children.Add(label); legend.Children.Add(item);
                } right=legend;
            } else if(i==1) {
                right=Ui.Text(copy.Text("Example: Quota restored · 5h 80% · 7d 36%","示例：额度已恢复 · 5 小时 80% · 7 天 36%","範例：額度已恢復 · 5 小時 80% · 7 天 36%"),11,muted);
            } else if(i==2) {
                var preview=new StackPanel { Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center };
                preview.Children.Add(new QuotaMoodView { Width=36,Height=36,Mood=QuotaMood.Recovered,Dark=dark,Stars=true,Margin=new Thickness(0,0,12,0) }); preview.Children.Add(Ui.Button(copy.Text("Preview celebration","预览庆祝","預覽慶祝"),PreviewCelebration)); right=preview;
            } else {
                right=Ui.Text(copy.Text("Thresholds are configured above; credits are grouped.","在上方设置提醒阈值，同批权益合并。","在上方設定提醒閾值，同批權益合併。"),11,muted);
            }
            row.Children.Add(right); rows.Children.Add(row); if(i!=3) { var divider=Ui.Divider(); divider.Margin=new Thickness(0,5,0,5); rows.Children.Add(divider); }
        }
        stack.Children.Add(SettingsVisual.Card(rows,dark));
        var note=Ui.Text(copy.Text("Celebrations play only while the floating button is visible. Tests use example notifications and do not change reminder history.","小庆祝仅在悬浮按钮可见时播放；测试使用示例通知，不改变提醒记录。","小慶祝僅在懸浮按鈕可見時播放；測試使用範例通知，不改變提醒記錄。"),11,muted); note.TextWrapping=TextWrapping.Wrap; note.Margin=new Thickness(0,0,0,10); stack.Children.Add(note);
        statusLabel=Ui.Text(CurrentStatus,11,muted); statusLabel.TextWrapping=TextWrapping.Wrap; stack.Children.Add(statusLabel);
        var settings=Ui.Button(copy.Text("Notification settings…","通知设置…","通知設定…"),()=> {
            try { Platform.OpenUrl("ms-settings:notifications"); }
            catch(Exception e) when(e is System.ComponentModel.Win32Exception or InvalidOperationException) { NotificationFailed(); }
        }); settings.HorizontalAlignment=HorizontalAlignment.Left; settings.Tag="settings-notifications"; stack.Children.Add(settings); return stack;
    }
}
