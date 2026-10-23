namespace QuotaBar.Windows;
internal sealed class SettingsWindow : Window {
    readonly Coordinator owner;
    readonly Grid shell=new();
    readonly BarkSettingsDraft mobileDraft=new();
    BarkSettingsView? mobile;
    public void UpdateMobileStatus()=>mobile?.Refresh();
    TextBlock? updateStatus,updateNotes;
    StackPanel? updateActions;
    Button? updateCheck,installButton,cancelInstallButton;
    public void ShowAbout() { selectedPage="updates"; Build(); }
    TextBlock status=Ui.Text("");
    TextBlock accountName=Ui.Text("");
    ProgressBar? updateProgress;
    readonly Dictionary<string,Button> accountActions=new();
    string selectedPage="moods";
    public SettingsWindow(Coordinator owner) {
        this.owner=owner; Icon=Ui.ApplicationIcon; Title="QuotaBar"; Width=920; Height=800; MinWidth=840; MinHeight=560;
        MaxHeight=Math.Max(380,SystemParameters.WorkArea.Height-40); MinHeight=Math.Min(MinHeight,MaxHeight); Height=Math.Min(Height,MaxHeight); WindowStartupLocation=WindowStartupLocation.CenterScreen; Content=shell; Deactivated+=(_,_)=>mobile?.HideSecret(); IsVisibleChanged+=(_,_)=> { if(!IsVisible) mobile?.HideSecret(); }; Closed+=(_,_)=>mobile?.HideSecret(); Build();
    }
    public void UpdateStatus() {
        accountName.Text=owner.Identity?.PreferredName??owner.Copy.Text("No account","暂无账户","尚無帳號");
        status.Text=owner.Copy.PhaseLabel(owner.State.Phase)+(owner.Snapshot?.Plan is { Length:>0 } plan?" · "+plan:"")+(owner.State.LastSuccess is { } t?"\n"+t.ToLocalTime().ToString("HH:mm:ss"):"");
        var signedIn=owner.Identity is not null && owner.State.Phase is not (Phase.NeedsLogin or Phase.SigningIn);
        foreach(var (key,button) in accountActions) button.Visibility=(key switch { "login"=>!signedIn && owner.State.Phase is not (Phase.SigningIn or Phase.Loading),"cancel"=>owner.State.Phase==Phase.SigningIn,_=>signedIn })?Visibility.Visible:Visibility.Collapsed;
    }
    public void UpdateUpdateStatus() {
        if(updateStatus is null) return;
        var copy=owner.Copy; var updates=owner.Updates;
        updateStatus.Text=copy.Text("Current version","当前版本","目前版本")+" "+updates.DisplayVersion+(updates.Available is { } release?" · "+copy.Text("Available","可用更新","可用更新")+" "+release.Version:"")+"\n"+updates.Status;
        var notes=updates.Available?.ReleaseNotes;
        if(string.IsNullOrWhiteSpace(notes)) notes=updates.Available?.NotificationSummary;
        if(updateNotes is not null) { updateNotes.Text=notes??""; updateNotes.Visibility=string.IsNullOrWhiteSpace(notes)?Visibility.Collapsed:Visibility.Visible; }
        if(updateActions is not null) updateActions.Visibility=updates.Available is null?Visibility.Collapsed:Visibility.Visible;
        var state=updates.Installer.Operation.Progress;
        var busy=state.Phase is ApplicationUpdatePhase.Resolving or ApplicationUpdatePhase.Downloading or ApplicationUpdatePhase.Verifying or ApplicationUpdatePhase.Preparing or ApplicationUpdatePhase.HandingOff or ApplicationUpdatePhase.Installing;
        if(installButton is not null) { installButton.IsEnabled=!busy; installButton.Content=state.Phase==ApplicationUpdatePhase.Failed?copy.Text("Retry update","重试更新","重試更新"):copy.Text("Update now","立即更新","立即更新"); }
        if(cancelInstallButton is not null) cancelInstallButton.Visibility=ApplicationUpdateOperation.CanCancel(state.Phase)?Visibility.Visible:Visibility.Collapsed;
        if(updateActions is not null) foreach(var button in updateActions.Children.OfType<Button>().Skip(1)) button.IsEnabled=!busy;
        if(updateCheck is not null) updateCheck.IsEnabled=!updates.Checking&&!busy;
        if(updateProgress is not null) { updateProgress.Visibility=updates.Checking||busy?Visibility.Visible:Visibility.Collapsed; updateProgress.IsIndeterminate=state.Phase!=ApplicationUpdatePhase.Downloading; updateProgress.Value=state.Total>0?100d*state.Received/state.Total:0; }
    }
    public void Build() {
        mobile?.HideSecret();
        var copy=owner.Copy; var p=owner.Preferences; var dark=Platform.IsDark(p); var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark);
        SettingsVisual.ApplyScrollbars(this,dark);
        Background=Ui.Surface(dark); Foreground=fg; shell.Children.Clear(); shell.ColumnDefinitions.Clear(); shell.ColumnDefinitions.Add(new() { Width=new GridLength(202) }); shell.ColumnDefinitions.Add(new());
        Title="QuotaBar — "+copy.Text("Settings","设置","設定");
        var sidebar=new DockPanel { Margin=new Thickness(12,22,12,16) };
        var brand=new StackPanel { Margin=new Thickness(8,6,0,28) }; var brandRow=new StackPanel { Orientation=Orientation.Horizontal }; brandRow.Children.Add(Ui.ApplicationLogo(42));
        var brandText=new StackPanel { Margin=new Thickness(10,0,0,0) }; var brandName=Ui.Text("QuotaBar",19,fg); brandName.FontWeight=FontWeights.Bold; brandText.Children.Add(brandName); var version=Ui.Text("v"+owner.Updates.Version,12,muted); version.ToolTip=owner.Updates.DisplayVersion; brandText.Children.Add(version); brandRow.Children.Add(brandText); brand.Children.Add(brandRow); DockPanel.SetDock(brand,Dock.Top); sidebar.Children.Add(brand);
        var navigation=new StackPanel(); var labels=new[]{copy.Text("Account","账户","帳戶"),copy.Text("Display","显示","顯示"),copy.Text("Quota experience","额度表情与管理","額度表情與管理"),copy.Text("Mobile push","手机推送","手機推播"),copy.Text("About app","关于应用","關於應用")}; var keys=new[]{"account","display","moods","mobile","updates"};
        for(var i=0;i<keys.Length;i++) {
            var key=keys[i]; var button=Ui.Button(labels[i],()=> { selectedPage=key; if(key=="mobile") owner.Mobile.RefreshConfiguration(); Build(); }); button.Tag="settings-nav-"+key; button.HorizontalContentAlignment=HorizontalAlignment.Left; button.Padding=new Thickness(10,8,6,8); button.BorderThickness=new Thickness(0); button.FontSize=13;
            button.Content=SettingsVisual.NavigationLabel(i,labels[i],fg);
            button.Background=key==selectedPage?new SolidColorBrush(dark?Color.FromRgb(43,81,53):Color.FromRgb(218,242,218)):Brushes.Transparent; button.Foreground=fg; if(key==selectedPage) button.FontWeight=FontWeights.Bold;
            System.Windows.Automation.AutomationProperties.SetName(button,labels[i]); navigation.Children.Add(button);
        } sidebar.Children.Add(navigation);
        var sideSurface=new Border { Background=dark?new SolidColorBrush(Color.FromRgb(25,27,32)):new SolidColorBrush(Color.FromRgb(240,242,245)),Child=new ScrollViewer { Content=sidebar,VerticalScrollBarVisibility=ScrollBarVisibility.Auto } }; shell.Children.Add(sideSurface);
        var pages=new Grid { Margin=new Thickness(24,26,24,18),MaxWidth=640,HorizontalAlignment=HorizontalAlignment.Stretch };
        var account=AccountView(dark); var display=DisplayView(dark); var moods=MoodsView(dark); var updates=UpdatesView(dark); mobile=new(owner,mobileDraft,dark);
        foreach(var (key,page) in new[]{("account",account),("display",display),("moods",moods),("updates",updates),("mobile",mobile.View)}) { var scroll=new ScrollViewer { Content=page,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,Visibility=selectedPage==key?Visibility.Visible:Visibility.Collapsed }; pages.Children.Add(scroll); }
        Grid.SetColumn(pages,1); shell.Children.Add(pages); UpdateStatus(); UpdateUpdateStatus(); SettingsVisual.ApplyButtons(shell,dark);
    }
    StackPanel Page(string heading,string description,bool dark) {
        var panel=new StackPanel(); var title=Ui.Text(heading,22,Ui.Foreground(dark)); title.FontWeight=FontWeights.Bold; panel.Children.Add(title); var text=Ui.Text(description,12,SettingsVisual.Muted(dark)); text.Margin=new Thickness(0,8,0,18); panel.Children.Add(text); return panel;
    }
    StackPanel AccountView(bool dark) {
        var c=owner.Copy; var fg=Ui.Foreground(dark); var page=Page(c.Text("Account","账户","帳戶"),c.Text("Manage your official Codex account and quota.","管理官方 Codex 账号与额度。","管理官方 Codex 帳號與額度。"),dark);
        var panel=new StackPanel(); accountName=Ui.Text("",16,fg); accountName.FontWeight=FontWeights.SemiBold; accountName.Margin=new Thickness(12,0,0,0); accountName.VerticalAlignment=VerticalAlignment.Center;
        var identityRow=new Grid { Margin=new Thickness(0,0,0,10) }; identityRow.ColumnDefinitions.Add(new() { Width=GridLength.Auto }); identityRow.ColumnDefinitions.Add(new());
        var accountIcon=new System.Windows.Shapes.Path { Data=Geometry.Parse("M 16,1 A 15,15 0 1 0 16,31 A 15,15 0 1 0 16,1 M 16,6 A 5,5 0 1 0 16,16 A 5,5 0 1 0 16,6 M 5,26 C 6,16 26,16 27,26"),Stroke=SettingsVisual.Muted(dark),StrokeThickness=1.6,Width=32,Height=32,Stretch=Stretch.Uniform,IsHitTestVisible=false }; identityRow.Children.Add(accountIcon); Grid.SetColumn(accountName,1); identityRow.Children.Add(accountName); panel.Children.Add(identityRow); status=Ui.Text("",12,SettingsVisual.Muted(dark)); status.LineHeight=22; panel.Children.Add(status); page.Children.Add(SettingsVisual.Card(panel,dark));
        accountActions.Clear();
        var actions=new WrapPanel { Margin=new Thickness(0,4,0,14) };
        void Add(string key,string title,Action action,Panel parent) { var button=Ui.Button(title,action); button.Tag="settings-account-"+key; accountActions[key]=button; parent.Children.Add(button); }
        Add("login",c.Text("Sign in","登录","登入"),owner.Login,actions);
        Add("cancel",c.Text("Cancel","取消"),owner.CancelLogin,actions);
        Add("details",c.Text("Quota details","额度详情","額度詳情"),owner.ToggleTrayDetail,actions);
        Add("refresh",c.Text("Refresh","刷新","重新整理"),owner.Refresh,actions);
        page.Children.Add(actions);
        var signOut=new WrapPanel { Margin=new Thickness(0,0,0,18) }; Add("logout",c.Text("Sign out","退出账号","登出帳號"),owner.Logout,signOut); page.Children.Add(signOut);
        var maintenance=new StackPanel(); var hint=Ui.Text(c.Text("Restart the bundled runtime if quota updates stop working.","额度持续无法更新时，可重新加载内嵌运行时。","額度持續無法更新時，可重新載入內嵌執行環境。"),12,SettingsVisual.Muted(dark)); hint.TextWrapping=TextWrapping.Wrap; maintenance.Children.Add(hint);
        maintenance.Children.Add(Ui.Button(c.Text("Reload runtime","重新加载运行时","重新載入執行環境"),owner.Reload));
        page.Children.Add(SettingsVisual.Card(new Expander { Header=c.Text("Troubleshooting","故障排查","疑難排解"),Content=maintenance,Foreground=fg },dark));
        var privacy=Ui.Text(c.Text("Credentials stay in a local isolated account folder.","凭据保存在本机隔离账号目录。","憑證儲存在本機隔離帳號目錄。"),12,SettingsVisual.Muted(dark)); privacy.TextWrapping=TextWrapping.Wrap; page.Children.Add(privacy); return page;
    }
    StackPanel DisplayView(bool dark) {
        var c=owner.Copy; var page=Page(c.Text("Display","显示","顯示"),c.Text("Appearance, language and everyday behavior.","外观、语言和日常行为。","外觀、語言和日常行為。"),dark); page.Children.Add(SettingsVisual.Section(c.Text("Appearance","外观","外觀"),Appearance(dark),dark)); page.Children.Add(SettingsVisual.Section(c.Text("Everyday behavior","常驻入口","常駐入口"),General(dark),dark)); return page;
    }
    UIElement Appearance(bool dark) {
        var c=owner.Copy; var p=owner.Preferences; var panel=new StackPanel();
        var themes=new[]{"system","light","dark"}; var theme=new ComboBox { ItemsSource=new[]{c.Text("System theme","跟随系统主题","跟隨系統主題"),c.Text("Light","浅色","淺色"),c.Text("Dark","深色")},SelectedIndex=Array.IndexOf(themes,p.Theme),MinHeight=28,Margin=new Thickness(0,8,0,3) }; theme.SelectionChanged+=(_,_)=> { if(theme.SelectedIndex>=0) owner.Save(owner.Preferences with { Theme=themes[theme.SelectedIndex] }); }; theme.MinWidth=150; panel.Children.Add(SettingsVisual.Row(c.Text("Theme","主题","主題"),theme,dark));
        var languages=new[]{"system","zh-CN","zh-TW","en"}; var language=new ComboBox { ItemsSource=new[]{c.Text("System language","跟随系统语言","跟隨系統語言"),"简体中文","繁體中文","English"},SelectedIndex=Array.IndexOf(languages,p.Language),MinHeight=28,Margin=new Thickness(0,3,0,0) }; language.SelectionChanged+=(_,_)=> { if(language.SelectedIndex>=0) owner.Save(owner.Preferences with { Language=languages[language.SelectedIndex] }); }; language.MinWidth=150; panel.Children.Add(SettingsVisual.Row(c.Text("Language","语言","語言"),language,dark)); return panel;
    }
    UIElement General(bool dark) {
        var c=owner.Copy; var p=owner.Preferences; var fg=Ui.Foreground(dark); var panel=new StackPanel();
        panel.Children.Add(SettingsVisual.Toggle(c.Text("Show floating button","显示悬浮按钮","顯示懸浮按鈕"),p.FloatingEnabled,fg,on=>owner.Save(owner.Preferences with { FloatingEnabled=on },false)));
        var quota=SettingsVisual.Toggle(c.Text("Show quota in tray","托盘显示额度","系統匣顯示額度"),p.ShowsQuotaInformation,fg,on=>owner.Save(owner.Preferences with { ShowsQuotaInformation=on },false)); quota.FontSize=13; panel.Children.Add(quota);
        var startup=SettingsVisual.Toggle(c.Text("Launch at login","登录时启动","登入時啟動"),Platform.StartupEnabled,fg,on=> { try { Platform.SetStartup(on); } catch(Exception e) when(e is UnauthorizedAccessException or IOException) { Build(); MessageBox.Show(c.Text("Startup registration failed","启动项设置失败","啟動項設定失敗")); } }); panel.Children.Add(startup); return panel;
    }
    StackPanel MoodsView(bool dark) {
        var c=owner.Copy; var page=Page(c.Text("Quota moods & management","额度表情与管理","額度表情與管理"),c.Text("Make quota status, reminders and interactions work for you.","管理额度相关的表情、提醒和互动效果，让 QuotaBar 更贴合你的使用习惯。","管理額度相關的表情、提醒和互動效果，讓 QuotaBar 更貼合你的使用習慣。"),dark);
        page.Children.Add(owner.Experience.MakeSettingsView());
        return page;
    }
    StackPanel UpdatesView(bool dark) {
        var c=owner.Copy; var p=owner.Preferences; var fg=Ui.Foreground(dark); var page=Page(c.Text("About app","关于应用","關於應用"),c.Text("Quota status, at a glance.","额度状态，一眼即知。","額度狀態，一眼即知。"),dark);
        var hero=new StackPanel { Orientation=Orientation.Horizontal };
        var heroLogo=Ui.ApplicationLogo(84); heroLogo.Margin=new Thickness(0,0,18,0); hero.Children.Add(heroLogo);
        var identity=new StackPanel { VerticalAlignment=VerticalAlignment.Center }; var brand=Ui.Text("QuotaBar  "+owner.Updates.Version,21,fg); brand.FontWeight=FontWeights.Bold; identity.Children.Add(brand); identity.Children.Add(Ui.Text(c.Text("Your quota companion","你的额度小伙伴","你的額度小夥伴"),13,SettingsVisual.Muted(dark))); hero.Children.Add(identity); page.Children.Add(SettingsVisual.Card(hero,dark));
        var panel=new StackPanel(); panel.Children.Add(Heading(c.Text("Version & updates","版本与更新","版本與更新"),fg));
        panel.Children.Add(SettingsVisual.Toggle(c.Text("Automatically check for updates","自动检查更新","自動檢查更新"),p.AutomaticUpdates,fg,on=> { owner.Save(owner.Preferences with { AutomaticUpdates=on },false); if(on) owner.Updates.Check(true); }));
        panel.Children.Add(SettingsVisual.Toggle(c.Text("Update reminders","更新提醒","更新提醒"),p.UpdateReminders,fg,on=> { owner.Save(owner.Preferences with { UpdateReminders=on },false); owner.Updates.PreferencesChanged(); }));
        var statusRow=new Grid { Margin=new Thickness(0,10,0,6) }; statusRow.ColumnDefinitions.Add(new()); statusRow.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
        updateStatus=Ui.Text("",12,fg); updateStatus.TextWrapping=TextWrapping.Wrap; updateStatus.Margin=new Thickness(0,0,12,0); updateStatus.VerticalAlignment=VerticalAlignment.Center; statusRow.Children.Add(updateStatus); updateCheck=Ui.Button(c.Text("Check for updates","检查更新","檢查更新"),()=>owner.Updates.Check(true)); updateCheck.VerticalAlignment=VerticalAlignment.Center; SettingsVisual.Primary(updateCheck); Grid.SetColumn(updateCheck,1); statusRow.Children.Add(updateCheck); panel.Children.Add(statusRow);
        updateProgress=new ProgressBar { IsIndeterminate=true,Height=3,Margin=new Thickness(0,8,0,8),Visibility=Visibility.Collapsed }; panel.Children.Add(updateProgress);
        updateActions=new StackPanel { Orientation=Orientation.Horizontal,Margin=new Thickness(0,6,0,10) }; installButton=Ui.Button(c.Text("Update now","立即更新","立即更新"),owner.Updates.Install); SettingsVisual.Primary(installButton); updateActions.Children.Add(installButton); updateActions.Children.Add(Ui.Button(c.Text("View release notes","查看更新内容","查看更新內容"),owner.Updates.Open)); updateActions.Children.Add(Ui.Button(c.Text("Remind later","稍后提醒","稍後提醒"),owner.Updates.Snooze)); updateActions.Children.Add(Ui.Button(c.Text("Skip version","跳过此版本","跳過此版本"),owner.Updates.Skip)); panel.Children.Add(updateActions); cancelInstallButton=Ui.Button(c.Text("Cancel download","取消下载","取消下載"),owner.Updates.CancelInstall); panel.Children.Add(cancelInstallButton); updateNotes=Ui.Text("",12,fg); updateNotes.TextWrapping=TextWrapping.Wrap; updateNotes.Margin=new Thickness(0,6,0,0); panel.Children.Add(updateNotes); page.Children.Add(SettingsVisual.Card(panel,dark));
        var links=new StackPanel(); links.Children.Add(Heading(c.Text("Related links","相关链接","相關連結"),fg));
        Link("GitHub", "github.com/JaceHwang/QuotaBar","https://github.com/JaceHwang/QuotaBar");
        Link(c.Text("Report an issue","问题反馈","問題回報"),c.Text("Share suggestions and problems","欢迎提出建议与问题","歡迎提出建議與問題"),"https://github.com/JaceHwang/QuotaBar/issues");
        var website=Ui.Button(c.Text("Official website · Coming soon","官方网站 · 敬请期待","官方網站 · 敬請期待"),()=>{}); website.Tag="settings-website"; website.IsEnabled=false; website.ToolTip=c.Text("Coming soon","待上线","待上線"); ToolTipService.SetShowOnDisabled(website,true); website.HorizontalContentAlignment=HorizontalAlignment.Left; website.Margin=new Thickness(0,8,0,0); links.Children.Add(website); page.Children.Add(SettingsVisual.Card(links,dark));
        var footer=Ui.Text(c.Text("Runs independently · Account and settings stored locally","独立运行 · 账户与设置保存在本机","獨立運作 · 帳號與設定儲存在本機"),12,SettingsVisual.Muted(dark)); footer.TextAlignment=TextAlignment.Center; page.Children.Add(footer); return page;
        void Link(string title,string subtitle,string url) { var button=Ui.Button(title+"  ↗",()=>Platform.OpenUrl(url)); button.HorizontalContentAlignment=HorizontalAlignment.Left; button.Margin=new Thickness(0,8,0,0); links.Children.Add(button); var hint=Ui.Text(subtitle,12,SettingsVisual.Muted(dark)); hint.Margin=new Thickness(8,2,0,8); hint.TextWrapping=TextWrapping.Wrap; links.Children.Add(hint); }
    }
    static TextBlock Heading(string text,Brush foreground) { var title=Ui.Text(text,15,foreground); title.FontWeight=FontWeights.SemiBold; title.Margin=new Thickness(0,0,0,10); return title; }
}
