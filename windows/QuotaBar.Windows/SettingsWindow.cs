namespace QuotaBar.Windows;
internal sealed class SettingsWindow : Window {
    readonly Coordinator owner;
    readonly Grid shell=new();
    TextBlock? updateStatus;
    StackPanel? updateActions;
    Button? updateCheck;
    TextBlock status=Ui.Text("");
    TextBlock? summaryStatus;
    string selectedPage="moods";
    public SettingsWindow(Coordinator owner) {
        this.owner=owner; Icon=Ui.ApplicationIcon; Title="QuotaBar"; Width=1040; Height=790; MinWidth=850; MinHeight=380;
        MaxHeight=Math.Max(380,SystemParameters.WorkArea.Height-40); Height=Math.Min(Height,MaxHeight); WindowStartupLocation=WindowStartupLocation.CenterScreen; Content=shell; Build();
    }
    public void UpdateStatus() {
        status.Text=owner.Copy.PhaseLabel(owner.State.Phase)+"\n"+(owner.Identity?.PreferredName??"")+(owner.State.LastSuccess is { } t?"\n"+t.ToLocalTime().ToString("HH:mm:ss"):"");
        if(summaryStatus is not null) summaryStatus.Text=owner.Copy.PhaseLabel(owner.State.Phase)+(owner.Identity?.PreferredName is { Length:>0 } name?" · "+name:"");
    }
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
        var copy=owner.Copy; var p=owner.Preferences; var dark=Platform.IsDark(p); var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark);
        Background=Ui.Surface(dark); Foreground=fg; shell.Children.Clear(); shell.ColumnDefinitions.Clear(); shell.ColumnDefinitions.Add(new() { Width=new GridLength(202) }); shell.ColumnDefinitions.Add(new());
        Title="QuotaBar — "+copy.Text("Settings","设置","設定");
        var sidebar=new DockPanel { Margin=new Thickness(12,22,12,16) };
        var brand=new StackPanel { Margin=new Thickness(8,6,0,28) }; var brandRow=new StackPanel { Orientation=Orientation.Horizontal }; brandRow.Children.Add(Ui.ApplicationLogo(42));
        var brandText=new StackPanel { Margin=new Thickness(10,0,0,0) }; var brandName=Ui.Text("QuotaBar",19,fg); brandName.FontWeight=FontWeights.Bold; brandText.Children.Add(brandName); brandText.Children.Add(Ui.Text("v"+owner.Updates.DisplayVersion,12,muted)); brandRow.Children.Add(brandText); brand.Children.Add(brandRow); DockPanel.SetDock(brand,Dock.Top); sidebar.Children.Add(brand);
        var updateLink=Ui.Button(copy.Text("Check for updates","检查更新","檢查更新")+"  ›",()=> { selectedPage="updates"; Build(); owner.Updates.Check(true); }); DockPanel.SetDock(updateLink,Dock.Bottom); sidebar.Children.Add(updateLink);
        var navigation=new StackPanel(); var labels=new[]{copy.Text("Account","账户","帳戶"),copy.Text("Display","显示","顯示"),copy.Text("Quota moods & management","额度表情与管理","額度表情與管理"),copy.Text("Updates","更新","更新")}; var keys=new[]{"account","display","moods","updates"}; var icons=new[]{"♙","▣","☺","↻"};
        for(var i=0;i<keys.Length;i++) {
            var key=keys[i]; var button=Ui.Button(icons[i]+"   "+labels[i],()=> { selectedPage=key; Build(); }); button.Tag="settings-nav-"+key; button.HorizontalContentAlignment=HorizontalAlignment.Left; button.Padding=new Thickness(10,12,6,12); button.BorderThickness=new Thickness(0); button.FontSize=13;
            button.Background=key==selectedPage?new SolidColorBrush(dark?Color.FromRgb(43,81,53):Color.FromRgb(218,242,218)):Brushes.Transparent; button.Foreground=fg; if(key==selectedPage) button.FontWeight=FontWeights.Bold;
            System.Windows.Automation.AutomationProperties.SetName(button,labels[i]); navigation.Children.Add(button);
        } sidebar.Children.Add(navigation);
        var sideSurface=new Border { Background=dark?new SolidColorBrush(Color.FromRgb(25,27,32)):new SolidColorBrush(Color.FromRgb(240,242,245)),Child=new ScrollViewer { Content=sidebar,VerticalScrollBarVisibility=ScrollBarVisibility.Auto } }; shell.Children.Add(sideSurface);
        var pages=new Grid { Margin=new Thickness(22,26,22,18) };
        var account=AccountView(dark); var display=DisplayView(dark); var moods=MoodsView(dark); var updates=UpdatesView(dark);
        foreach(var (key,page) in new[]{("account",account),("display",display),("moods",moods),("updates",updates)}) { var scroll=new ScrollViewer { Content=page,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,Visibility=selectedPage==key?Visibility.Visible:Visibility.Collapsed }; pages.Children.Add(scroll); }
        Grid.SetColumn(pages,1); shell.Children.Add(pages); UpdateStatus(); UpdateUpdateStatus(); SettingsVisual.ApplyButtons(shell,dark);
    }
    StackPanel Page(string heading,string description,bool dark) {
        var panel=new StackPanel(); var title=Ui.Text(heading,22,Ui.Foreground(dark)); title.FontWeight=FontWeights.Bold; panel.Children.Add(title); var text=Ui.Text(description,12,SettingsVisual.Muted(dark)); text.Margin=new Thickness(0,8,0,18); panel.Children.Add(text); return panel;
    }
    StackPanel AccountView(bool dark) {
        var c=owner.Copy; var fg=Ui.Foreground(dark); var page=Page(c.Text("Account","账户","帳戶"),c.Text("Manage your official Codex account and quota.","管理官方 Codex 账号与额度。","管理官方 Codex 帳號與額度。"),dark);
        var panel=new StackPanel(); status=Ui.Text("",14,fg); panel.Children.Add(status); var actions=new WrapPanel { Margin=new Thickness(0,12,0,12) };
        actions.Children.Add(Ui.Button(c.Text("Sign in","登录","登入"),()=>owner.Login())); actions.Children.Add(Ui.Button(c.Text("Cancel","取消"),()=>owner.CancelLogin())); actions.Children.Add(Ui.Button(c.Text("Sign out","退出账号","登出帳號"),()=>owner.Logout())); actions.Children.Add(Ui.Button(c.Text("Refresh","刷新","重新整理"),()=>owner.Refresh())); actions.Children.Add(Ui.Button(c.Text("Quota details","额度详情","額度詳情"),()=>owner.ToggleTrayDetail())); actions.Children.Add(Ui.Button(c.Text("Reload runtime","重新加载运行时","重新載入執行環境"),()=>owner.Reload())); panel.Children.Add(actions);
        panel.Children.Add(Ui.Text(c.Text("QuotaBar uses a bundled official runtime. Credentials stay in a local isolated account folder.","通过内嵌官方运行时读取额度，凭据保存在本机隔离账号目录。","透過內嵌官方執行環境讀取額度，憑證儲存在本機隔離帳號目錄。"),12,SettingsVisual.Muted(dark))); page.Children.Add(SettingsVisual.Card(panel,dark)); return page;
    }
    StackPanel DisplayView(bool dark) {
        var c=owner.Copy; var page=Page(c.Text("Display","显示","顯示"),c.Text("Appearance, language and everyday behavior.","外观、语言和日常行为。","外觀、語言和日常行為。"),dark); var panel=new StackPanel(); panel.Children.Add(Appearance(dark)); panel.Children.Add(Ui.Divider()); panel.Children.Add(General(dark)); page.Children.Add(SettingsVisual.Card(panel,dark)); return page;
    }
    UIElement Appearance(bool dark) {
        var c=owner.Copy; var p=owner.Preferences; var panel=new StackPanel(); panel.Children.Add(Ui.Text(c.Text("Appearance and language","外观与语言","外觀與語言"),13,Ui.Foreground(dark)));
        var themes=new[]{"system","light","dark"}; var theme=new ComboBox { ItemsSource=new[]{c.Text("System theme","跟随系统主题","跟隨系統主題"),c.Text("Light","浅色","淺色"),c.Text("Dark","深色")},SelectedIndex=Array.IndexOf(themes,p.Theme),MinHeight=28,Margin=new Thickness(0,8,0,3) }; theme.SelectionChanged+=(_,_)=> { if(theme.SelectedIndex>=0) owner.Save(owner.Preferences with { Theme=themes[theme.SelectedIndex] }); }; panel.Children.Add(theme);
        var languages=new[]{"system","zh-CN","zh-TW","en"}; var language=new ComboBox { ItemsSource=new[]{c.Text("System language","跟随系统语言","跟隨系統語言"),"简体中文","繁體中文","English"},SelectedIndex=Array.IndexOf(languages,p.Language),MinHeight=28,Margin=new Thickness(0,3,0,0) }; language.SelectionChanged+=(_,_)=> { if(language.SelectedIndex>=0) owner.Save(owner.Preferences with { Language=languages[language.SelectedIndex] }); }; panel.Children.Add(language); return panel;
    }
    UIElement General(bool dark) {
        var c=owner.Copy; var p=owner.Preferences; var fg=Ui.Foreground(dark); var panel=new StackPanel(); panel.Children.Add(Ui.Text(c.Text("General","通用","一般"),13,fg));
        panel.Children.Add(SettingsVisual.Toggle(c.Text("Show floating button","显示悬浮按钮","顯示懸浮按鈕"),p.FloatingEnabled,fg,on=>owner.Save(owner.Preferences with { FloatingEnabled=on },false)));
        var quota=SettingsVisual.Toggle(c.Text("Show quota information in taskbar tooltip","任务栏显示额度信息","工作列顯示額度資訊"),p.ShowsQuotaInformation,fg,on=>owner.Save(owner.Preferences with { ShowsQuotaInformation=on },false)); quota.FontSize=11; panel.Children.Add(quota);
        var startup=SettingsVisual.Toggle(c.Text("Launch at login","登录时启动","登入時啟動"),Platform.StartupEnabled,fg,on=> { try { Platform.SetStartup(on); } catch(Exception e) when(e is UnauthorizedAccessException or IOException) { Build(); MessageBox.Show(c.Text("Startup registration failed","启动项设置失败","啟動項設定失敗")); } }); panel.Children.Add(startup); return panel;
    }
    StackPanel MoodsView(bool dark) {
        var c=owner.Copy; var page=Page(c.Text("Quota moods & management","额度表情与管理","額度表情與管理"),c.Text("Make quota status, reminders and interactions work for you.","管理额度相关的表情、提醒和互动效果，让 QuotaBar 更贴合你的使用习惯。","管理額度相關的表情、提醒和互動效果，讓 QuotaBar 更貼合你的使用習慣。"),dark);
        page.Children.Add(owner.Experience.MakeSettingsView());
        var summary=new Grid(); for(var i=0;i<3;i++) summary.ColumnDefinitions.Add(new());
        var account=new StackPanel { Margin=new Thickness(0,0,12,0) }; account.Children.Add(Ui.Text(c.Text("Account status","账户状态","帳戶狀態"),13,Ui.Foreground(dark))); summaryStatus=Ui.Text("",11,SettingsVisual.Muted(dark)); summaryStatus.Margin=new Thickness(0,9,0,8); account.Children.Add(summaryStatus); var actions=new WrapPanel(); actions.Children.Add(Ui.Button(c.Text("Details","额度详情","額度詳情"),owner.ToggleTrayDetail)); actions.Children.Add(Ui.Button(c.Text("Refresh","刷新","重新整理"),owner.Refresh)); account.Children.Add(actions); summary.Children.Add(account);
        var appearance=new Border { Child=Appearance(dark),Padding=new Thickness(12,0,12,0),BorderThickness=new Thickness(1,0,1,0),BorderBrush=SettingsVisual.Muted(dark) }; Grid.SetColumn(appearance,1); summary.Children.Add(appearance);
        var general=new Border { Child=General(dark),Padding=new Thickness(12,0,0,0) }; Grid.SetColumn(general,2); summary.Children.Add(general); page.Children.Add(SettingsVisual.Card(summary,dark)); return page;
    }
    StackPanel UpdatesView(bool dark) {
        var c=owner.Copy; var p=owner.Preferences; var fg=Ui.Foreground(dark); var page=Page(c.Text("Updates","更新","更新"),c.Text("Keep QuotaBar up to date.","保持 QuotaBar 为最新版本。","保持 QuotaBar 為最新版本。"),dark); var panel=new StackPanel();
        var automatic=new CheckBox { Content=c.Text("Automatically check for updates","自动检查更新","自動檢查更新"),IsChecked=p.AutomaticUpdates,Foreground=fg,Margin=new Thickness(0,8,0,5) }; automatic.Click+=(_,_)=> { owner.Save(owner.Preferences with { AutomaticUpdates=automatic.IsChecked==true },false); if(automatic.IsChecked==true) owner.Updates.Check(true); }; panel.Children.Add(automatic);
        var reminders=new CheckBox { Content=c.Text("Update reminders","更新提醒","更新提醒"),IsChecked=p.UpdateReminders,Foreground=fg,Margin=new Thickness(0,0,0,8) }; reminders.Click+=(_,_)=> { owner.Save(owner.Preferences with { UpdateReminders=reminders.IsChecked==true },false); owner.Updates.PreferencesChanged(); }; panel.Children.Add(reminders);
        updateStatus=Ui.Text("",12,fg); panel.Children.Add(updateStatus); updateCheck=Ui.Button(c.Text("Check for updates","检查更新","檢查更新"),()=>owner.Updates.Check(true)); panel.Children.Add(updateCheck);
        updateActions=new StackPanel { Orientation=Orientation.Horizontal,Margin=new Thickness(0,6,0,10) }; updateActions.Children.Add(Ui.Button(c.Text("View update","查看更新","查看更新"),owner.Updates.Open)); updateActions.Children.Add(Ui.Button(c.Text("Remind later","稍后提醒","稍後提醒"),owner.Updates.Snooze)); updateActions.Children.Add(Ui.Button(c.Text("Skip version","跳过此版本","跳過此版本"),owner.Updates.Skip)); panel.Children.Add(updateActions); page.Children.Add(SettingsVisual.Card(panel,dark)); return page;
    }
}
