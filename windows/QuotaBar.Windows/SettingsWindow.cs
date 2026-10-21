namespace QuotaBar.Windows;
internal sealed class SettingsWindow : Window {
    readonly Coordinator owner;
    readonly StackPanel stack=new() { Margin=new Thickness(24) };
    TextBlock? updateStatus;
    StackPanel? updateActions;
    Button? updateCheck;
    TextBlock status=Ui.Text("");
    public SettingsWindow(Coordinator owner) {
        this.owner=owner; Icon=Ui.ApplicationIcon; Title="QuotaBar"; Width=510; SizeToContent=SizeToContent.Height; ResizeMode=ResizeMode.NoResize;
        MaxHeight=Math.Max(400,SystemParameters.WorkArea.Height-40); WindowStartupLocation=WindowStartupLocation.CenterScreen; Content=new ScrollViewer { Content=stack,VerticalScrollBarVisibility=ScrollBarVisibility.Auto }; Build();
    }
    public void UpdateStatus() { status.Text=owner.Copy.PhaseLabel(owner.State.Phase)+"\n"+(owner.Identity?.PreferredName??"")+(owner.State.LastSuccess is { } t?"\n"+t.ToLocalTime().ToString("HH:mm:ss"):""); }
    public void UpdateUpdateStatus() {
        if(updateStatus is null) return;
        var copy=owner.Copy; var updates=owner.Updates;
        updateStatus.Text=copy.Text("Current version","当前版本","目前版本")+" "+updates.DisplayVersion+(updates.Available is { } release?" · "+copy.Text("Available","可用更新","可用更新")+" "+release.Version:"")+"\n"+updates.Status;
        var notes=updates.Available?.ReleaseNotes;
        if(string.IsNullOrWhiteSpace(notes)) notes=updates.Available?.NotificationSummary;
        if(!string.IsNullOrWhiteSpace(notes)) updateStatus.Text+="\n\n"+notes;
        if(updateActions is not null) updateActions.Visibility=updates.Available is null?Visibility.Collapsed:Visibility.Visible;
        if(updateCheck is not null) updateCheck.IsEnabled=!updates.Checking;
    }
    public void Build() {
        var copy=owner.Copy; var p=owner.Preferences; var dark=Platform.IsDark(p); var fg=Ui.Foreground(dark);
        Background=Ui.Surface(dark); Foreground=fg; stack.Children.Clear(); Title="QuotaBar — "+copy.Text("Settings","设置","設定");
        status=Ui.Text("",14,fg); stack.Children.Add(status); UpdateStatus();
        var actions=new WrapPanel { Margin=new Thickness(0,12,0,12) };
        actions.Children.Add(Ui.Button(copy.Text("Sign in","登录","登入"),()=>owner.Login()));
        actions.Children.Add(Ui.Button(copy.Text("Cancel","取消"),()=>owner.CancelLogin()));
        actions.Children.Add(Ui.Button(copy.Text("Sign out","退出账号","登出帳號"),()=>owner.Logout()));
        actions.Children.Add(Ui.Button(copy.Text("Refresh","刷新","重新整理"),()=>owner.Refresh()));
        actions.Children.Add(Ui.Button(copy.Text("Quota details","额度详情","額度詳情"),()=>owner.ToggleTrayDetail()));
        actions.Children.Add(Ui.Button(copy.Text("Reload runtime","重新加载运行时","重新載入執行環境"),()=>owner.Reload())); stack.Children.Add(actions);
        var theme=new ComboBox { Foreground=SystemColors.ControlTextBrush,Background=SystemColors.ControlBrush,Margin=new Thickness(0,5,0,5),MinHeight=28 };
        var themes=new[]{"system","light","dark"}; theme.ItemsSource=new[]{copy.Text("System theme","跟随系统主题","跟隨系統主題"),copy.Text("Light","浅色","淺色"),copy.Text("Dark","深色")}; theme.SelectedIndex=Array.IndexOf(themes,p.Theme);
        theme.SelectionChanged+=(_,_)=> { if(theme.SelectedIndex>=0) owner.Save(owner.Preferences with { Theme=themes[theme.SelectedIndex] }); }; stack.Children.Add(theme);
        var language=new ComboBox { Foreground=SystemColors.ControlTextBrush,Background=SystemColors.ControlBrush,Margin=new Thickness(0,5,0,5),MinHeight=28 };
        var languages=new[]{"system","zh-CN","zh-TW","en"}; language.ItemsSource=new[]{copy.Text("System language","跟随系统语言","跟隨系統語言"),"简体中文","繁體中文","English"}; language.SelectedIndex=Array.IndexOf(languages,p.Language);
        language.SelectionChanged+=(_,_)=> { if(language.SelectedIndex>=0) owner.Save(owner.Preferences with { Language=languages[language.SelectedIndex] }); }; stack.Children.Add(language);
        var quota=new CheckBox { Content=copy.Text("Show quota information in taskbar tooltip","任务栏显示额度信息","工作列顯示額度資訊"),IsChecked=p.ShowsQuotaInformation,Margin=new Thickness(0,10,0,5),Foreground=fg };
        quota.ToolTip=copy.Text("The tray always shows an icon. This option adds quota to its tooltip.","托盘始终显示图标；此选项控制悬停提示中的额度。","系統匣始終顯示圖示；此選項控制提示中的額度。");
        quota.Click+=(_,_)=>owner.Save(owner.Preferences with { ShowsQuotaInformation=quota.IsChecked==true },false); stack.Children.Add(quota);
        var startup=new CheckBox { Content=copy.Text("Launch at login","登录时启动","登入時啟動"),IsChecked=Platform.StartupEnabled,Margin=new Thickness(0,5,0,10),Foreground=fg };
        startup.Click+=(_,_)=> { try { Platform.SetStartup(startup.IsChecked==true); } catch(Exception e) when(e is UnauthorizedAccessException or IOException) { startup.IsChecked=Platform.StartupEnabled; MessageBox.Show(copy.Text("Startup registration failed","启动项设置失败","啟動項設定失敗")); } }; stack.Children.Add(startup);
        stack.Children.Add(owner.Experience.MakeSettingsView());
        stack.Children.Add(new Separator { Margin=new Thickness(0,12,0,8) });
        stack.Children.Add(Ui.Text(copy.Text("Software update","软件更新","軟體更新"),13,fg));
        var automatic=new CheckBox { Content=copy.Text("Automatically check for updates","自动检查更新","自動檢查更新"),IsChecked=p.AutomaticUpdates,Foreground=fg,Margin=new Thickness(0,8,0,5) };
        automatic.Click+=(_,_)=> { owner.Save(owner.Preferences with { AutomaticUpdates=automatic.IsChecked==true },false); if(automatic.IsChecked==true) owner.Updates.Check(true); }; stack.Children.Add(automatic);
        var reminders=new CheckBox { Content=copy.Text("Update reminders","更新提醒","更新提醒"),IsChecked=p.UpdateReminders,Foreground=fg,Margin=new Thickness(0,0,0,8) };
        reminders.Click+=(_,_)=> { owner.Save(owner.Preferences with { UpdateReminders=reminders.IsChecked==true },false); owner.Updates.PreferencesChanged(); }; stack.Children.Add(reminders);
        updateStatus=Ui.Text("",12,fg); updateStatus.TextWrapping=TextWrapping.Wrap; stack.Children.Add(updateStatus);
        updateCheck=Ui.Button(copy.Text("Check for updates","检查更新","檢查更新"),()=>owner.Updates.Check(true)); stack.Children.Add(updateCheck);
        updateActions=new StackPanel { Orientation=Orientation.Horizontal,Margin=new Thickness(0,6,0,10) };
        updateActions.Children.Add(Ui.Button(copy.Text("View update","查看更新","查看更新"),owner.Updates.Open));
        updateActions.Children.Add(Ui.Button(copy.Text("Remind later","稍后提醒","稍後提醒"),owner.Updates.Snooze));
        updateActions.Children.Add(Ui.Button(copy.Text("Skip version","跳过此版本","跳過此版本"),owner.Updates.Skip)); stack.Children.Add(updateActions); UpdateUpdateStatus();
        stack.Children.Add(Ui.Text(copy.Text("QuotaBar uses a bundled official runtime. Credentials stay in a local isolated account folder.","通过内嵌官方运行时读取额度，凭据保存在本机隔离账号目录。","透過內嵌官方執行環境讀取額度，憑證儲存在本機隔離帳號目錄。"),12,fg));
    }
}
