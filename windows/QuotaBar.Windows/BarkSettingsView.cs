namespace QuotaBar.Windows;
internal sealed class BarkSettingsDraft { public string Value=""; }
internal sealed class BarkSettingsView {
    readonly Coordinator owner;
    readonly BarkSettingsDraft draft;
    readonly TextBlock status;
    readonly Button test,clear,save;
    readonly CheckBox enabled;
    public StackPanel View { get; }
    public BarkSettingsView(Coordinator owner,BarkSettingsDraft draft,bool dark) {
        this.owner=owner; this.draft=draft; var c=owner.Copy; var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark);
        View=new StackPanel(); var title=Ui.Text(c.Text("Mobile push","手机推送","手機推播"),22,fg); title.FontWeight=FontWeights.Bold; View.Children.Add(title);
        var introduction=Ui.Text(c.Text("Receive quota recovery, Bank expiry and update reminders through Bark.","通过 Bark 接收额度恢复、Bank 到期和软件更新提醒。","透過 Bark 接收額度恢復、Bank 到期和軟體更新提醒。"),12,muted); introduction.Margin=new Thickness(0,8,0,18); introduction.TextWrapping=TextWrapping.Wrap; View.Children.Add(introduction);
        var connection=new StackPanel(); var brand=Ui.Text("Bark",16,fg); brand.FontWeight=FontWeights.SemiBold; connection.Children.Add(brand);
        enabled=SettingsVisual.Toggle(c.Text("Enable mobile push","启用手机推送","啟用手機推播"),owner.Mobile.Preferences.Enabled,fg,value=> { owner.Mobile.SetEnabled(value); Refresh(); }); enabled.Tag="bark-enabled"; connection.Children.Add(enabled);
        var server=Ui.Text(c.Text("Official server: ","官方服务器：","官方伺服器：")+"https://api.day.app",12,muted); server.Margin=new Thickness(0,8,0,14); connection.Children.Add(server);
        var label=Ui.Text("Device Key",13,fg); connection.Children.Add(label);
        var password=new PasswordBox { Password=draft.Value,MaxLength=512,MinHeight=32,Padding=new Thickness(8,6,8,6),Margin=new Thickness(0,8,0,6),Background=dark?new SolidColorBrush(Color.FromRgb(38,40,46)):Brushes.White,Foreground=fg,Tag="bark-device-key" };
        System.Windows.Automation.AutomationProperties.SetName(password,c.Text("Bark Device Key, secure input","Bark Device Key，安全输入","Bark Device Key，安全輸入")); password.PasswordChanged+=(_,_)=>draft.Value=password.Password; connection.Children.Add(password);
        var hint=Ui.Text(c.Text("Copy the Device Key from Bark, not the full URL. A blank field keeps the saved key.","从 Bark 复制 Device Key，请勿填完整网址。留空会保留已保存的 Key。","從 Bark 複製 Device Key，請勿填完整網址。留空會保留已儲存的 Key。"),12,muted); hint.TextWrapping=TextWrapping.Wrap; connection.Children.Add(hint);
        var actions=new WrapPanel { Margin=new Thickness(0,10,0,0) };
        save=Ui.Button(c.Text("Save key","保存 Key","儲存 Key"),()=> { if(owner.Mobile.SaveKey(draft.Value)) { draft.Value=""; password.Password=""; } Refresh(); }); save.Tag="bark-save"; actions.Children.Add(save);
        clear=Ui.Button(c.Text("Clear key","清除 Key","清除 Key"),()=> { owner.Mobile.ClearKey(); Refresh(); }); clear.Tag="bark-clear"; actions.Children.Add(clear);
        test=Ui.Button(c.Text("Send test push","发送测试推送","傳送測試推播"),async()=> { await owner.Mobile.Test(c.Text("QuotaBar test","QuotaBar 测试","QuotaBar 測試"),c.Text("This is a sample reminder. No account data is included.","这是一条示例提醒，不包含账号数据。","這是一則範例提醒，不包含帳號資料。")); Refresh(); }); test.Tag="bark-test"; actions.Children.Add(test); connection.Children.Add(actions); View.Children.Add(SettingsVisual.Card(connection,dark));
        status=Ui.Text("",12,fg); status.TextWrapping=TextWrapping.Wrap; System.Windows.Automation.AutomationProperties.SetLiveSetting(status,System.Windows.Automation.AutomationLiveSetting.Polite); View.Children.Add(SettingsVisual.Card(status,dark));
        var privacy=Ui.Text(c.Text("Mobile push works independently of desktop bubbles. When enabled, reminder titles and bodies are sent over HTTPS to Bark and APNs. The key stays in Windows Credential Manager and is never logged. Tests send sample data only. Bark service acceptance does not confirm phone display.","手机推送独立于桌面气泡。启用后，提醒标题和正文经 HTTPS 发送到 Bark 与 APNs。Key 保存在 Windows 凭据管理器，不写日志。测试仅发送示例数据。服务接受不代表手机已展示。","手機推播獨立於桌面氣泡。啟用後，提醒標題和內文經 HTTPS 傳送至 Bark 與 APNs。Key 儲存在 Windows 認證管理員，不寫日誌。測試僅傳送範例資料。服務接受不代表手機已顯示。"),12,muted); privacy.TextWrapping=TextWrapping.Wrap; privacy.Margin=new Thickness(0,8,0,14); View.Children.Add(privacy); Refresh();
    }
    public void Refresh() {
        var c=owner.Copy; var mobile=owner.Mobile;
        status.Text=mobile.Status switch {
            BarkStatus.NotConfigured=>c.Text("Not configured","未配置","尚未設定"),BarkStatus.Configured=>c.Text("Configured","已配置","已設定"),
            BarkStatus.StorageUnavailable=>c.Text("Secure storage unavailable","安全存储不可用","安全儲存空間無法使用"),BarkStatus.Sending=>c.Text("Sending…","请求中…","請求中…"),
            BarkStatus.Accepted=>c.Text("Bark service accepted the push","Bark 服务已接受","Bark 服務已接受"),BarkStatus.Rejected=>c.Text("Send failed","发送失败","傳送失敗"),
            BarkStatus.InvalidKey=>c.Text("Enter a valid Device Key, not a URL","请输入有效 Device Key，请勿填网址","請輸入有效 Device Key，請勿填網址"),
            BarkStatus.HistoryRecovery=>c.Text("Reminder history recovered; enable again to resume new reminders","提醒记录已恢复；请重新开启以接收新提醒","提醒記錄已恢復；請重新開啟以接收新提醒"),
            BarkStatus.PersistenceUnavailable=>c.Text("Could not save push state; automatic delivery paused","无法保存推送状态；自动推送已暂停","無法儲存推播狀態；自動推播已暫停"),
            _=>c.Text("Send failed or result unknown","发送失败或结果未知","傳送失敗或結果不明") };
        if(mobile.LastOperation is { } at) status.Text+="\n"+at.ToLocalTime().ToString("HH:mm:ss");
        enabled.IsChecked=mobile.Preferences.Enabled; enabled.IsEnabled=mobile.HasKey; test.IsEnabled=mobile.HasKey&&!mobile.Testing; clear.IsEnabled=mobile.HasKey||mobile.Preferences.Enabled; save.IsEnabled=!mobile.Testing;
    }
}
