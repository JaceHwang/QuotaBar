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
            if(engine.Preferences.RecoveryNotificationsEnabled) Enqueue(ExperienceNotificationKind.Recovery,Copy.Text("Quota restored","额度已恢复","額度已恢復"),Copy.RecoveryBody(o.Quota));
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
        if(message.Kind==ExperienceNotificationKind.Recovery) return engine.Preferences.RecoveryNotificationsEnabled;
        return engine.Preferences.Bank && lastObservation is { } o && message.BankEvents is { } events && engine.BankEventsAreCurrent(events,o,DateTimeOffset.UtcNow);
    }
    public void Stop() { owner.Notifications.CancelAuthenticationEpoch(engine.State.Epoch); owner.CancelCelebration(); }
    public void PreviewCelebration() { owner.PreviewCelebration(); TestNotification(); }
    public void TestNotification()=>Enqueue(ExperienceNotificationKind.Test,"QuotaBar "+Copy.Text("test notification","测试通知","測試通知"),Copy.Text("Example only — your quota and reminder history are unchanged.","这是一条示例通知，不改变真实额度及提醒记录。","這是一條範例通知，不改變真實額度及提醒記錄。"));
    public UIElement MakeSettingsView() {
        var copy=owner.Copy; var p=owner.Preferences.Experience; var stack=new StackPanel(); var dark=Platform.IsDark(owner.Preferences); var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark);
        var rows=new StackPanel();
        var titles=new[]{copy.Text("Quota mood mode","额度表情模式","額度表情模式"),copy.Text("Notify when quota is restored","额度恢复时提醒","額度恢復時提醒"),copy.Text("Celebrate quota recovery","额度恢复时播放小庆祝","額度恢復時播放小慶祝"),copy.Text("Bank expiry reminders","Bank 到期提醒","Bank 到期提醒")};
        var hints=new[]{copy.Text("Show the battery character for your current quota.","根据当前额度状态，显示对应的电池表情。","根據目前額度狀態，顯示對應的電池表情。"),copy.Text("A system notification after confirmed recovery.","额度确认恢复时，显示系统通知。","額度確認恢復時，顯示系統通知。"),copy.Text("A brief celebration with one recovery notification.","播放短暂庆祝，并同步一条恢复通知。","播放短暫慶祝，並同步一條恢復通知。"),copy.Text("Known credits only; never redeem automatically.","仅提醒已知权益，不会自动兑换。","僅提醒已知權益，不會自動兌換。")};
        var values=new[]{p.Moods,p.Recovery,p.Celebration,p.Bank};
        for(var i=0;i<4;i++) {
            var index=i; var row=new Grid { Margin=new Thickness(0,10,0,10) }; row.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) }); row.ColumnDefinitions.Add(new() { Width=new GridLength(1.1,GridUnitType.Star) });
            var left=new StackPanel { VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,16,0) };
            left.Children.Add(SettingsVisual.Toggle(titles[i],values[i],fg,on=> {
                var next=owner.Preferences.Experience;
                next=index switch { 0=>next with { Moods=on },1=>next with { Recovery=on },2=>next with { Celebration=on },_=>next with { Bank=on } };
                owner.Save(owner.Preferences with { Experience=next },false);
            }));
            var hint=Ui.Text(hints[i],11,muted); hint.TextWrapping=TextWrapping.Wrap; hint.Margin=new Thickness(0,10,0,0); left.Children.Add(hint); row.Children.Add(left);
            UIElement right;
            if(i==0) {
                var legend=new System.Windows.Controls.Primitives.UniformGrid { Columns=5,VerticalAlignment=VerticalAlignment.Center };
                var states=new[]{QuotaMood.Good,QuotaMood.Low,QuotaMood.Exhausted,QuotaMood.Unavailable,QuotaMood.Recovered};
                var labels=new[]{copy.Text("Good","充足","充足"),copy.Text("Low","偏低","偏低"),copy.Text("Empty","耗尽","耗盡"),copy.Text("Unavailable","不可用","無法使用"),copy.Text("Restored","恢复","恢復")};
                for(var j=0;j<states.Length;j++) {
                    var item=new StackPanel { HorizontalAlignment=HorizontalAlignment.Center,Margin=new Thickness(2,0,2,0) }; var icon=new QuotaMoodView { Width=42,Height=42,Mood=states[j],Dark=dark,Stars=states[j]==QuotaMood.Recovered };
                    System.Windows.Automation.AutomationProperties.SetName(icon,Copy.MoodLabel(states[j])); item.Children.Add(icon);
                    var label=Ui.Text(labels[j],10,fg); label.HorizontalAlignment=HorizontalAlignment.Center; label.Margin=new Thickness(0,5,0,0); item.Children.Add(label); legend.Children.Add(item);
                } right=legend;
            } else if(i==1) {
                var illustration=new StackPanel { Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center };
                illustration.Children.Add(new SettingsIllustration { Dark=dark,Width=34,Height=40,Margin=new Thickness(0,0,10,0) });
                var example=new StackPanel(); var title=Ui.Text("QuotaBar · "+copy.Text("Quota restored","额度已恢复","額度已恢復"),12,fg); title.FontWeight=FontWeights.SemiBold; example.Children.Add(title);
                example.Children.Add(Ui.Text(copy.Text("Example: 5h 80% · 7d 36%","示例：5 小时 80% · 7 天 36%","範例：5 小時 80% · 7 天 36%"),11,muted)); illustration.Children.Add(SettingsVisual.Card(example,dark,new Thickness(10))); right=illustration;
            } else if(i==2) {
                var preview=new StackPanel { Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center };
                preview.Children.Add(new QuotaMoodView { Width=58,Height=58,Mood=QuotaMood.Recovered,Dark=dark,Stars=true,Margin=new Thickness(0,0,16,0) }); preview.Children.Add(Ui.Button(copy.Text("Preview","预览","預覽"),PreviewCelebration)); right=preview;
            } else {
                var bank=new StackPanel { Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center }; bank.Children.Add(new SettingsIllustration { Bank=true,Dark=dark,Width=42,Height=42,Margin=new Thickness(0,0,12,0) }); bank.Children.Add(Ui.Text(copy.Text("72 hours / 24 hours before expiry","提前 72 小时 / 24 小时","提前 72 小時 / 24 小時"),12,fg)); right=bank;
            }
            Grid.SetColumn(right,1); row.Children.Add(right); rows.Children.Add(row); if(i!=3) { var divider=Ui.Divider(); divider.Margin=new Thickness(0,5,0,5); rows.Children.Add(divider); }
        }
        stack.Children.Add(SettingsVisual.Card(rows,dark));
        var actions=new DockPanel(); var buttons=new StackPanel { Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right }; buttons.Children.Add(Ui.Button(copy.Text("Preview celebration","预览庆祝","預覽慶祝"),PreviewCelebration)); buttons.Children.Add(Ui.Button(copy.Text("Send test notification","发送测试通知","傳送測試通知"),TestNotification)); DockPanel.SetDock(buttons,Dock.Right); actions.Children.Add(buttons); actions.Children.Add(Ui.Text(copy.Text("Preview and test","预览与测试","預覽與測試"),12,fg)); stack.Children.Add(SettingsVisual.Card(actions,dark));
        var note=Ui.Text(copy.Text("Celebrations play only while the floating button is visible. Previews use example notifications.","小庆祝仅在悬浮按钮可见时播放；预览同步发送示例通知。","小慶祝僅在懸浮按鈕可見時播放；預覽同步傳送範例通知。"),11,muted); note.TextWrapping=TextWrapping.Wrap; note.Margin=new Thickness(0,0,0,10); stack.Children.Add(note);
        statusLabel=Ui.Text("",11,muted); stack.Children.Add(statusLabel); return stack;
    }
}
