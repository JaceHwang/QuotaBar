namespace QuotaBar.Windows;
internal sealed class BarkSettingsDraft { public string Value=""; }
internal sealed class BarkSettingsView {
    readonly Coordinator owner;
    readonly BarkSettingsDraft draft;
    readonly TextBlock status;
    readonly Button test,guideTest,clear,save,reveal;
    readonly CheckBox enabled;
    readonly PasswordBox password;
    readonly TextBox visibleKey;
    bool syncing,revealed,savedReveal;
    public StackPanel View { get; }
    public BarkSettingsView(Coordinator owner,BarkSettingsDraft draft,bool dark) {
        this.owner=owner; this.draft=draft; var c=owner.Copy; var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark);
        TextBlock Text(string text,int size=12) { var result=Ui.Text(text,size,fg); result.TextWrapping=TextWrapping.Wrap; return result; }
        View=new StackPanel(); var title=Text(c.Text("Mobile push","手机推送","手機推播"),22); title.FontWeight=FontWeights.Bold; View.Children.Add(title);
        var introduction=Text(c.Text("Receive quota reminders on iPhone through Bark.","通过 Bark 在 iPhone 接收额度提醒。","透過 Bark 在 iPhone 接收額度提醒。")); introduction.Foreground=muted; introduction.Margin=new Thickness(0,8,0,16); View.Children.Add(introduction);
        var connection=new StackPanel(); var header=new Grid(); header.ColumnDefinitions.Add(new()); header.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
        var brand=new StackPanel { Orientation=Orientation.Horizontal }; brand.Children.Add(new Border { Background=new SolidColorBrush(Color.FromRgb(247,71,100)),CornerRadius=new CornerRadius(10),Child=new SettingsIllustration { Width=34,Height=34,Dark=true },Padding=new Thickness(4),Margin=new Thickness(0,0,10,0) }); var brandCopy=new StackPanel { VerticalAlignment=VerticalAlignment.Center }; var bark=Text("Bark",17); bark.FontWeight=FontWeights.Bold; brandCopy.Children.Add(bark); brandCopy.Children.Add(Text(c.Text("Quota reminders on iPhone","在 iPhone 接收额度提醒","在 iPhone 接收額度提醒"))); brand.Children.Add(brandCopy); header.Children.Add(brand);
        enabled=SettingsVisual.Toggle(c.Text("Enable mobile push","启用手机推送","啟用手機推播"),owner.Mobile.Preferences.Enabled,fg,value=> { owner.Notifications.SetChannelEnabled(NotificationChannel.Mobile,value); Refresh(); }); enabled.Tag="bark-enabled"; enabled.Margin=new Thickness(12,0,0,0); Grid.SetColumn(enabled,1); header.Children.Add(enabled); connection.Children.Add(header);
        status=Text(""); status.Foreground=muted; status.Margin=new Thickness(0,5,0,10); status.Tag="bark-status"; System.Windows.Automation.AutomationProperties.SetLiveSetting(status,System.Windows.Automation.AutomationLiveSetting.Polite); connection.Children.Add(status);
        connection.Children.Add(Text("Device Key",13));
        var keyRow=new Grid { Margin=new Thickness(0,6,0,4) }; keyRow.ColumnDefinitions.Add(new()); keyRow.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
        password=new PasswordBox { Password=draft.Value,MaxLength=512,MinHeight=32,Padding=new Thickness(8,6,8,6),Background=dark?new SolidColorBrush(Color.FromRgb(38,40,46)):Brushes.White,Foreground=fg,Tag="bark-device-key" };
        System.Windows.Automation.AutomationProperties.SetName(password,c.Text("Bark Device Key, secure input","Bark Device Key，安全输入","Bark Device Key，安全輸入"));
        visibleKey=new TextBox { Visibility=Visibility.Collapsed,MaxLength=512,MinHeight=32,Padding=new Thickness(8,6,8,6),Background=password.Background,Foreground=fg,Tag="bark-visible-key" };
        System.Windows.Automation.AutomationProperties.SetName(visibleKey,c.Text("Visible Device Key","明文 Device Key","明文 Device Key"));
        password.PasswordChanged+=(_,_)=> { if(!syncing) draft.Value=password.Password; };
        visibleKey.TextChanged+=(_,_)=> { if(!syncing&&!savedReveal) { draft.Value=visibleKey.Text; syncing=true; password.Password=draft.Value; syncing=false; } };
        reveal=Ui.Button("◉",()=> { if(revealed) { HideSecret(); return; } var key=draft.Value; savedReveal=string.IsNullOrWhiteSpace(key); if(savedReveal) key=owner.Mobile.RevealKeyForUser()??""; if(string.IsNullOrEmpty(key)) { HideSecret(); Refresh(); return; } syncing=true; visibleKey.Text=key; syncing=false; visibleKey.IsReadOnly=savedReveal; visibleKey.Visibility=Visibility.Visible; password.Visibility=Visibility.Collapsed; revealed=true; Refresh(); reveal!.ToolTip=c.Text("Hide key","隐藏 Key","隱藏 Key"); }); reveal.Content=new System.Windows.Shapes.Path { Data=Geometry.Parse("M 1,7 Q 9,-3 17,7 Q 9,17 1,7 Z M 12,7 A 3,3 0 1 0 6,7 A 3,3 0 1 0 12,7"),Stroke=muted,StrokeThickness=1.5,Width=18,Height=14,Stretch=Stretch.Uniform }; reveal.Tag="bark-reveal"; reveal.ToolTip=c.Text("Show key","显示 Key","顯示 Key"); System.Windows.Automation.AutomationProperties.SetName(reveal,c.Text("Show or hide Device Key","显示或隐藏 Device Key","顯示或隱藏 Device Key")); Grid.SetColumn(reveal,1); keyRow.Children.Add(password); keyRow.Children.Add(visibleKey); keyRow.Children.Add(reveal); connection.Children.Add(keyRow);
        var actions=new WrapPanel { Margin=new Thickness(0,6,0,4) };
        save=Ui.Button(c.Text("Save key","保存 Key","儲存 Key"),()=> { if(savedReveal) return; if(owner.Mobile.SaveKey(draft.Value)) { draft.Value=""; syncing=true; password.Password=""; syncing=false; HideSecret(); } Refresh(); }); save.Tag="bark-save"; SettingsVisual.Primary(save); actions.Children.Add(save);
        clear=Ui.Button(c.Text("Clear key","清除 Key","清除 Key"),()=> { if(owner.Mobile.ClearKey()) { owner.Notifications.SetChannelEnabled(NotificationChannel.Mobile,false); draft.Value=""; syncing=true; password.Password=""; syncing=false; } HideSecret(); Refresh(); }); clear.Tag="bark-clear"; actions.Children.Add(clear);
        test=TestButton("bark-test"); actions.Children.Add(test); connection.Children.Add(actions);
        var security=Text(c.Text("Official server: https://api.day.app · Key secured in Windows Credential Manager.","官方服务器：https://api.day.app · Key 安全保存在 Windows 凭据管理器。","官方伺服器：https://api.day.app · Key 安全儲存在 Windows 認證管理員。")); security.Foreground=muted; connection.Children.Add(security); View.Children.Add(SettingsVisual.Card(connection,dark));
        var guide=new StackPanel(); var heading=Text(c.Text("Connection guide","连接向导","連線指南"),15); heading.FontWeight=FontWeights.SemiBold; guide.Children.Add(heading);
        var strip=new Grid();
        var steps=new[]{c.Text("Install Bark","安装 Bark","安裝 Bark"),c.Text("Get Key","获取 Key","取得 Key"),c.Text("Connect & test","连接测试","連線測試")};
        for(var i=0;i<5;i++) strip.ColumnDefinitions.Add(new() { Width=i%2==0?new GridLength(1,GridUnitType.Star):new GridLength(18) });
        for(var i=0;i<3;i++) {
            var item=new Grid(); item.ColumnDefinitions.Add(new() { Width=new GridLength(26) }); item.ColumnDefinitions.Add(new());
            var number=Ui.Text((i+1).ToString(),12,i<2?Brushes.White:fg); number.HorizontalAlignment=HorizontalAlignment.Center; number.VerticalAlignment=VerticalAlignment.Center;
            item.Children.Add(new Border { Width=24,Height=24,CornerRadius=new CornerRadius(12),Background=new SolidColorBrush(i<2?Color.FromRgb(8,127,91):dark?Color.FromRgb(67,72,83):Color.FromRgb(226,230,236)),Child=number,VerticalAlignment=VerticalAlignment.Center });
            var label=Text(steps[i],12); label.Margin=new Thickness(6,0,0,0); label.VerticalAlignment=VerticalAlignment.Center; Grid.SetColumn(label,1); item.Children.Add(label); Grid.SetColumn(item,i*2); strip.Children.Add(item);
            if(i<2) { var separator=new Border { Height=1,Background=muted,Margin=new Thickness(3,0,3,0),VerticalAlignment=VerticalAlignment.Center }; Grid.SetColumn(separator,i*2+1); strip.Children.Add(separator); }
        }
        strip.Margin=new Thickness(0,12,0,10); guide.Children.Add(strip);
        var diagram=new Grid { Height=156,Background=dark?new SolidColorBrush(Color.FromRgb(32,38,48)):new SolidColorBrush(Color.FromRgb(244,247,253)),Margin=new Thickness(0,0,0,12) }; diagram.ColumnDefinitions.Add(new() { Width=new GridLength(130) }); diagram.ColumnDefinitions.Add(new());
        diagram.Children.Add(new BarkPhoneIllustration { Dark=dark,Margin=new Thickness(8,6,8,0) });
        var urlPanel=new StackPanel { VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(4,8,10,8) }; urlPanel.Children.Add(Text(c.Text("Illustration · Example only","操作示意 · 仅为示例","操作示意 · 僅為範例"),11));
        var url=Text("",13); url.Margin=new Thickness(0,10,0,8); url.Inlines.Add("https://api.day.app/"); url.Inlines.Add(new System.Windows.Documents.Run("DEMO_KEY") { Background=new SolidColorBrush(Color.FromRgb(255,203,220)),Foreground=new SolidColorBrush(Color.FromRgb(175,21,73)),FontWeight=FontWeights.SemiBold }); url.Inlines.Add("/test"); urlPanel.Children.Add(url);
        var keyHint=Text(c.Text("↑ Copy only this Key segment. Your key will differ.","↑ 只复制这一段 Key，实际内容可能不同。","↑ 只複製這一段 Key，實際內容可能不同。"));
        var prefixWidth=new FormattedText("https://api.day.app/",System.Globalization.CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),13,fg,VisualTreeHelper.GetDpi(View).PixelsPerDip).Width;
        keyHint.Margin=new Thickness(prefixWidth,0,0,0); urlPanel.Children.Add(keyHint); Grid.SetColumn(urlPanel,1); diagram.Children.Add(urlPanel); guide.Children.Add(diagram);
        var columns=new UniformGridCompat();
        var first=Step(1,steps[0],c.Text("Install Bark from the iPhone App Store and allow notifications.","在 iPhone App Store 安装 Bark，并允许通知。","在 iPhone App Store 安裝 Bark，並允許通知。")); var install=Ui.Button(c.Text("Get Bark ↗","获取 Bark ↗","取得 Bark ↗"),()=>Platform.OpenUrl("https://apps.apple.com/app/bark-custom-notifications/id1403753865")); SettingsVisual.Primary(install); first.Children.Add(install); columns.Children.Add(first);
        var second=Step(2,c.Text("Get Device Key","获取 Device Key","取得 Device Key"),c.Text("Open Bark. Copy the first segment after api.day.app/ up to the next /. Do not paste the full URL.","打开 Bark，复制 api.day.app/ 后的第一段（到下一个 / 为止），不要粘贴完整网址。","開啟 Bark，複製 api.day.app/ 後的第一段（到下一個 / 為止），請勿貼上完整網址。")); columns.Children.Add(second);
        var third=Step(3,steps[2],c.Text("Paste Key → Save → Enable. Send a sample test, then check your phone. Service acceptance does not confirm display.","粘贴 Key → 保存 → 开启推送。发送示例测试后检查手机；服务接受不代表手机已展示。","貼上 Key → 儲存 → 開啟推播。傳送範例測試後檢查手機；服務接受不代表手機已顯示。")); guideTest=TestButton("bark-guide-test"); third.Children.Add(guideTest); columns.Children.Add(third); guide.Children.Add(columns); View.Children.Add(SettingsVisual.Card(guide,dark));
        var footer=Ui.Button(c.Text("Read official tutorial ↗","查看官方教程 ↗","查看官方教學 ↗"),()=>Platform.OpenUrl("https://bark.day.app/#/tutorial")); footer.HorizontalAlignment=HorizontalAlignment.Left; View.Children.Add(footer);
        var privacy=Text(c.Text("Mobile push is independent of desktop bubbles. Enabled reminders send titles and bodies over HTTPS to Bark and APNs. Blank input keeps the saved key. Tests use sample data only.","手机推送独立于桌面气泡。启用后，标题和正文经 HTTPS 发送到 Bark 与 APNs。留空保留已保存 Key；测试仅发送示例数据。","手機推播獨立於桌面氣泡。啟用後，標題和內文經 HTTPS 傳送至 Bark 與 APNs。留空保留已儲存 Key；測試僅傳送範例資料。")); privacy.Foreground=muted; privacy.Margin=new Thickness(0,4,0,8); View.Children.Add(privacy); Refresh();
        Button TestButton(string tag) { var button=Ui.Button(c.Text("Send test push","发送测试推送","傳送測試推播"),async()=> { await owner.Mobile.Test(c.Text("QuotaBar test","QuotaBar 测试","QuotaBar 測試"),c.Text("This is a sample reminder. No account data is included.","这是一条示例提醒，不包含账号数据。","這是一則範例提醒，不包含帳號資料。")); Refresh(); }); button.Tag=tag; button.Content=Text(c.Text("Send test push","发送测试推送","傳送測試推播")); return button; }
        StackPanel Step(int number,string caption,string description) { var panel=new StackPanel { Margin=new Thickness(0,0,10,0) }; var label=Text(number+"  "+caption,13); label.FontWeight=FontWeights.SemiBold; panel.Children.Add(label); var body=Text(description); body.Foreground=muted; body.Margin=new Thickness(0,6,0,6); panel.Children.Add(body); return panel; }
    }
    public void HideSecret() { syncing=true; visibleKey.Text=""; syncing=false; visibleKey.Visibility=Visibility.Collapsed; password.Visibility=Visibility.Visible; revealed=false; savedReveal=false; save.IsEnabled=!owner.Mobile.Testing; reveal.ToolTip=owner.Copy.Text("Show key","显示 Key","顯示 Key"); }
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
        if(mobile.LastOperation is { } at) status.Text+=" · "+at.ToLocalTime().ToString("HH:mm:ss");
        enabled.IsChecked=mobile.Preferences.Enabled; enabled.IsEnabled=mobile.HasKey; test.IsEnabled=guideTest.IsEnabled=mobile.HasKey&&!mobile.Testing; clear.IsEnabled=mobile.HasKey||mobile.Preferences.Enabled; save.IsEnabled=!mobile.Testing&&!savedReveal;
    }
}
// Equal columns use the native UniformGrid layout and reflow their text at narrow widths.
internal sealed class UniformGridCompat : System.Windows.Controls.Primitives.UniformGrid { public UniformGridCompat() { Columns=3; } }
