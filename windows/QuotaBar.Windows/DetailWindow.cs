using System.Windows.Controls.Primitives;

namespace QuotaBar.Windows;
internal sealed class DetailWindow : Window {
    readonly ScrollViewer scroll=new() { VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
    string? avatarKey;
    FrameworkElement? avatar;
    public event Action? LockRequested,SettingsRequested,CloseRequested;
    public event Action<double>? HeightChanged;
    public DetailWindow() {
        Title="QuotaBar"; Width=340; Height=580; WindowStyle=WindowStyle.None; AllowsTransparency=true; Background=Brushes.Transparent;
        ShowInTaskbar=false; ShowActivated=false; ResizeMode=ResizeMode.NoResize; Topmost=true; Platform.Passive(this);
    }
    public void Render(QuotaSnapshot quota,TokenUsage? tokens,AccountIdentity? identity,RefreshState state,Preferences prefs,Copy copy,bool dark,bool locked,Rect anchor) {
        if(IsMouseCaptureWithin) return;
        var fg=Ui.Foreground(dark); var body=new StackPanel();
        var heading=new DockPanel(); var controls=new StackPanel { Orientation=Orientation.Horizontal };
        controls.Children.Add(Ui.Button(locked?"🔒":"🔓",()=>LockRequested?.Invoke()));
        controls.Children.Add(Ui.Button("×",()=>CloseRequested?.Invoke())); DockPanel.SetDock(controls,Dock.Right); heading.Children.Add(controls);
        var title=Ui.Text(copy.Text("Quota details","额度详情","額度詳情"),20,fg); title.FontWeight=FontWeights.SemiBold; heading.Children.Add(title); body.Children.Add(heading);
        foreach(var window in new[]{quota.Primary,quota.Secondary}.OfType<QuotaWindow>()) {
            var row=new DockPanel { Margin=new Thickness(0,12,0,5) };
            var pct=Ui.Text($"{window.RemainingPercent}%",18,Ui.Accent(window.RemainingPercent)); pct.FontWeight=FontWeights.Bold; DockPanel.SetDock(pct,Dock.Right); row.Children.Add(pct);
            row.Children.Add(Ui.Text(copy.Period(window.WindowMinutes),13,fg)); body.Children.Add(row);
            var bar=new ProgressBar { Value=window.RemainingPercent,Maximum=100,Height=7,Foreground=Ui.Accent(window.RemainingPercent),Background=new SolidColorBrush(Color.FromArgb(30,128,128,128)) }; body.Children.Add(bar);
            body.Children.Add(Ui.Text(copy.Countdown(window.ResetsAt,DateTimeOffset.Now)+" · "+copy.Reset(window.ResetsAt),11,fg));
        }
        body.Children.Add(Ui.Divider());
        body.Children.Add(Ui.Text(copy.Text("Token usage","Token 用量","Token 用量"),15,fg));
        if(tokens is not null) {
            try {
                var days=TokenWindow.Days(tokens,quota,DateTimeOffset.Now); var max=Math.Max(1,days.Max(d=>d.Tokens));
                body.Children.Add(Ui.Text(TokenWindow.Total(days).ToString("N0")+" Tokens",20,fg));
                var chart=new UniformGrid { Columns=7,Height=110,Margin=new Thickness(0,8,0,5) };
                foreach(var day in days) {
                    var column=new Grid(); column.RowDefinitions.Add(new() { Height=new GridLength(85) }); column.RowDefinitions.Add(new() { Height=new GridLength(20) });
                    var bar=new Border { Height=Math.Max(2,day.Tokens/(double)max*80),Background=new SolidColorBrush(Color.FromRgb(64,128,220)),CornerRadius=new CornerRadius(3),VerticalAlignment=VerticalAlignment.Bottom,Margin=new Thickness(5,0,5,0),ToolTip=$"{day.Date}: {day.Tokens:N0}" };
                    column.Children.Add(bar); var label=Ui.Text(day.Date.ToString("M/d"),10,fg); label.TextAlignment=TextAlignment.Center; Grid.SetRow(label,1); column.Children.Add(label); chart.Children.Add(column);
                }
                body.Children.Add(chart);
                Row(body,copy.Text("Lifetime tokens","累计 Token","累計 Token"),tokens.LifetimeTokens?.ToString("N0")??copy.NoData,fg);
                Row(body,copy.Text("Peak daily tokens","最高单日 Token","最高單日 Token"),tokens.PeakDailyTokens?.ToString("N0")??copy.NoData,fg);
                Row(body,copy.Text("Longest turn","最长运行时长","最長執行時長"),tokens.LongestTurnSeconds is long sec ? $"{sec/3600}:{sec%3600/60:00}:{sec%60:00}":copy.NoData,fg);
                Row(body,copy.Text("Current streak","当前连续天数","目前連續天數"),tokens.CurrentStreakDays?.ToString()??copy.NoData,fg);
                Row(body,copy.Text("Longest streak","最长连续天数","最長連續天數"),tokens.LongestStreakDays?.ToString()??copy.NoData,fg);
            } catch(FormatException) { body.Children.Add(Ui.Text(copy.NoData,13,fg)); }
        } else body.Children.Add(Ui.Text(copy.NoData,13,fg));
        body.Children.Add(Ui.Divider());
        if(quota.Plan is not null) Row(body,copy.Text("Plan","套餐","方案"),quota.Plan,fg);
        Row(body,copy.Text("Bank available","Bank 可用次数","Bank 可用次數"),quota.Bank?.AvailableCount.ToString()??copy.NoData,fg);
        if(quota.Bank?.Credits is { } credits) {
            var index=0;
            foreach(var credit in credits.OrderBy(c=>c.ExpiresAt??DateTimeOffset.MaxValue)) {
                Row(body,$"Bank {++index}",credit.ExpiresAt is { } expiry ? copy.Countdown(expiry,DateTimeOffset.Now)+" · "+copy.Reset(expiry):copy.NoData,fg);
            }
        }
        Row(body,"Credits",quota.Credits is { } balance ? balance.Unlimited?copy.Text("Unlimited","无限","無限"):balance.HasCredits?balance.Balance??copy.Text("Available","可用"):copy.Text("None","无","無"):copy.NoData,fg);
        Row(body,copy.Text("Updated","更新时间","更新時間"),copy.PhaseLabel(state.Phase)+" · "+quota.ReceivedAt.ToLocalTime().ToString("HH:mm:ss"),fg);
        body.Children.Add(Ui.Divider());
        var footer=new DockPanel(); var settings=Ui.Button("⚙",()=>SettingsRequested?.Invoke()); settings.ToolTip=copy.Text("Settings","设置","設定"); DockPanel.SetDock(settings,Dock.Right); footer.Children.Add(settings);
        var github=Ui.Button("GitHub",()=>Platform.OpenUrl("https://github.com/JaceHwang/codex-usage-sidebar")); DockPanel.SetDock(github,Dock.Right); footer.Children.Add(github);
        var account=new DockPanel(); var key=(identity?.PreferredName??"")+"|"+(identity?.AvatarUrl??"");
        if(key!=avatarKey || avatar is null) {
            avatarKey=key;
            var initials=(identity?.PreferredName??"Q").Trim(); initials=initials.Length==0?"Q":initials[..1].ToUpperInvariant();
            avatar=new Border { Width=26,Height=26,CornerRadius=new CornerRadius(13),Background=new SolidColorBrush(Color.FromRgb(81,93,136)),Child=new TextBlock { Text=initials,Foreground=Brushes.White,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,FontWeight=FontWeights.Bold } };
            if(Uri.TryCreate(identity?.AvatarUrl,UriKind.Absolute,out var url) && url.Scheme=="https") {
                try {
                    var image=new System.Windows.Media.Imaging.BitmapImage(); image.BeginInit(); image.UriSource=url; image.DecodePixelWidth=52; image.EndInit();
                    var fallback=avatar;
                    var picture=new Image { Source=image,Width=26,Height=26,Clip=new EllipseGeometry(new Point(13,13),13,13) };
                    image.DownloadFailed+=(_,_)=> { if(avatar==picture) avatar=fallback; };
                    avatar=picture;
                } catch(Exception e) when(e is IOException or System.Net.WebException or NotSupportedException) { }
            }
        }
        // Reparent the cached avatar when a refreshed card replaces its footer.
        if(avatar.Parent is Panel oldParent) oldParent.Children.Remove(avatar);
        avatar.Margin=new Thickness(0,0,8,0); DockPanel.SetDock(avatar,Dock.Left); account.Children.Add(avatar);
        account.Children.Add(Ui.Text(identity?.PreferredName??"QuotaBar",12,fg)); footer.Children.Add(account); body.Children.Add(footer);
        var info=Ui.Button(copy.Text("Tibo on X","Tibo 的 X 动态","Tibo 的 X 動態"),()=>Platform.OpenUrl("https://x.com/thsottiaux")); body.Children.Add(info);
        var offset=scroll.VerticalOffset; scroll.Content=body;
        var dock=new DockPanel();
        var resize=new Thumb { Height=9,Cursor=Cursors.SizeNS,Background=new SolidColorBrush(Color.FromArgb(40,128,128,128)) };
        resize.DragDelta+=(_,e)=> { var area=Platform.WorkArea(Platform.Bounds(this).Location); Height=Math.Clamp(Height+e.VerticalChange,220,Math.Max(220,area.Height/VisualTreeHelper.GetDpi(this).DpiScaleY)); HeightChanged?.Invoke(Height); };
        DockPanel.SetDock(resize,Dock.Bottom); dock.Children.Add(resize); dock.Children.Add(scroll); Content=Ui.Shell(dock,dark);
        if(!IsVisible) Show();
        var work=Platform.WorkArea(anchor.Location); var scale=VisualTreeHelper.GetDpi(this).DpiScaleY;
        Height=Math.Min(Math.Max(220,prefs.DetailHeight),work.Height/scale);
        var y=anchor.Bottom+5; if(y+Height*scale>work.Y+work.Height) y=anchor.Top-Height*scale-5;
        Platform.Place(this,new(anchor.Right-Width*scale,y)); scroll.ScrollToVerticalOffset(offset);
    }
    private static void Row(Panel panel,string label,string value,Brush fg) {
        var row=new Grid { Margin=new Thickness(0,5,0,5) }; row.ColumnDefinitions.Add(new() { Width=new GridLength(120) }); row.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) });
        row.Children.Add(Ui.Text(label,12,fg)); var text=Ui.Text(value,12,fg); Grid.SetColumn(text,1); row.Children.Add(text); panel.Children.Add(row);
    }
}
