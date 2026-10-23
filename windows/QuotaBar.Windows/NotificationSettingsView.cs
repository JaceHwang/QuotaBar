namespace QuotaBar.Windows;
internal sealed class NotificationSettingsView : StackPanel {
    public NotificationSettingsView(Coordinator owner) {
        var copy=owner.Copy; var dark=Platform.IsDark(owner.Preferences);
        var mode=new ComboBox { MinWidth=160,SelectedIndex=(int)owner.Preferences.Notifications.Mode,ItemsSource=new[]{copy.Text("Floating bubble","悬浮气泡","懸浮氣泡"),copy.Text("System notification","系统通知","系統通知"),copy.Text("Both","两者","兩者"),copy.Text("Off","关闭","關閉")},Tag="notification.channel" };
        System.Windows.Automation.AutomationProperties.SetName(mode,copy.Text("Reminder display","提醒展示方式","提醒顯示方式"));
        mode.SelectionChanged+=(_,_)=> { if(mode.SelectedIndex>=0) owner.Save(owner.Preferences with { Notifications=owner.Preferences.Notifications with { Mode=(NotificationDeliveryMode)mode.SelectedIndex } },false); };
        Children.Add(SettingsVisual.Row(copy.Text("Reminder display","提醒展示方式","提醒顯示方式"),mode,dark));
        var actions=new WrapPanel();
        string PauseTitle()=>owner.Preferences.Notifications.Paused(DateTimeOffset.UtcNow)?copy.Text("Resume bubbles","恢复气泡","恢復氣泡"):copy.Text("Pause for 1 hour","暂停气泡 1 小时","暫停氣泡 1 小時");
        Button? pause=null; pause=Ui.Button(PauseTitle(),()=> { var p=owner.Preferences.Notifications; owner.Save(owner.Preferences with { Notifications=p with { PausedUntil=p.Paused(DateTimeOffset.UtcNow)?null:DateTimeOffset.UtcNow.AddHours(1) } },false); pause!.Content=PauseTitle(); }); pause.Tag="notification.pause"; actions.Children.Add(pause);
        var status=Ui.Text("",11,SettingsVisual.Muted(dark)); status.TextWrapping=TextWrapping.Wrap;
        actions.Children.Add(Ui.Button(copy.Text("Preview bubble","预览气泡","預覽氣泡"),()=> {
            var m=new ExperienceNotification("preview-"+Guid.NewGuid(),ExperienceNotificationKind.Test,null,copy.Text("Example notification","示例通知","範例通知"),copy.Text("5 hours remaining 100%; 7 days remaining 36%. Example only.","5 小时剩余 100%；7 天剩余 36%。仅为示例。","5 小時剩餘 100%；7 天剩餘 36%。僅為範例。"),DateTimeOffset.UtcNow);
            status.Text=owner.Notifications.Preview(m)?"":copy.Text("Show the floating button and close quota details to preview.","请开启悬浮按钮并收起额度详情后预览。","請開啟懸浮按鈕並收起額度詳情後預覽。");
        }));
        actions.Children.Add(Ui.Button(copy.Text("Unread reminders","未读提醒","未讀提醒"),owner.ShowUnread)); Children.Add(actions);
        var note=Ui.Text(copy.Text("Bubbles stay quiet while hidden or locked. Unread reminders are kept for this run only. System Focus does not automatically mute bubbles; use Pause.","浮窗隐藏或锁屏时不冒泡；未读仅保留本次运行。气泡不自动继承系统免打扰，可使用暂停。","浮窗隱藏或鎖定時不冒泡；未讀僅保留本次執行。氣泡不自動繼承系統勿擾，可使用暫停。"),11,SettingsVisual.Muted(dark)); note.TextWrapping=TextWrapping.Wrap; note.Margin=new Thickness(0,8,0,8); Children.Add(note);
        if(!owner.Preferences.FloatingEnabled) Children.Add(Ui.Button(copy.Text("Enable floating button","开启悬浮按钮","開啟懸浮按鈕"),()=>owner.Save(owner.Preferences with { FloatingEnabled=true })));
        Children.Add(status);
    }
}
