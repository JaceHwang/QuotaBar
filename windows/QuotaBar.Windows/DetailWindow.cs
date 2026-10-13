using System.Windows.Controls.Primitives;
using System.Windows.Documents;

namespace QuotaBar.Windows;
internal sealed class DetailWindow : Window {
    readonly ScrollViewer scroll=new() { VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
    string? avatarKey;
    FrameworkElement? avatar;
    public event Action? LockRequested,SettingsRequested,CloseRequested;
    public event Action<double>? HeightChanged;
    public DetailWindow() {
        Title="QuotaBar"; Width=360; Height=580; WindowStyle=WindowStyle.None; AllowsTransparency=true; Background=Brushes.Transparent;
        ShowInTaskbar=false; ShowActivated=false; ResizeMode=ResizeMode.NoResize; Topmost=true; Platform.Passive(this);
    }
    public void Render(QuotaSnapshot quota,TokenUsage? tokens,AccountIdentity? identity,RefreshState state,Preferences prefs,Copy copy,bool dark,bool locked,Rect anchor) {
        if(IsMouseCaptureWithin) return;
        var p=DetailPalette.For(dark); var top=new StackPanel();
        var header=new Grid { Margin=new Thickness(16,13,16,9) };
        foreach(var width in new[]{new GridLength(32),new GridLength(1,GridUnitType.Star),GridLength.Auto,GridLength.Auto,GridLength.Auto}) header.ColumnDefinitions.Add(new() { Width=width });
        header.Children.Add(Ui.Icon(dark,28));
        var title=DetailVisual.Text(copy.Text("Quota details","额度详情","額度詳情"),18,p.Primary,true); title.MaxWidth=190; title.TextWrapping=TextWrapping.NoWrap; title.TextTrimming=TextTrimming.CharacterEllipsis; Grid.SetColumn(title,1); header.Children.Add(title);
        var pin=DetailVisual.Button("\uE718",()=>LockRequested?.Invoke(),locked?copy.Text("Unlock details","解锁详情","解除鎖定詳情"):copy.Text("Lock details","锁定详情","鎖定詳情"),p,true,locked); pin.Width=26; pin.Height=26; pin.Margin=new Thickness(0,0,6,0); Grid.SetColumn(pin,2); header.Children.Add(pin);
        var version=typeof(DetailWindow).Assembly.GetName().Version?.ToString(3)??"0.6.0";
        var badge=new Border { Height=18,CornerRadius=new CornerRadius(8),BorderThickness=new Thickness(.75),BorderBrush=p.Badge,Padding=new Thickness(5,0,5,0),VerticalAlignment=VerticalAlignment.Center,Child=DetailVisual.Text("v"+version,9,p.Badge) }; Grid.SetColumn(badge,3); header.Children.Add(badge);
        var close=DetailVisual.Button("×",()=>CloseRequested?.Invoke(),copy.Text("Close details","关闭详情","關閉詳情"),p); Grid.SetColumn(close,4); header.Children.Add(close); top.Children.Add(header);
        foreach(var window in new[]{quota.Primary,quota.Secondary}.OfType<QuotaWindow>()) {
            var row=new Grid { Margin=new Thickness(16,6,16,3) }; row.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) }); row.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
            row.Children.Add(DetailVisual.Text(copy.Period(window.WindowMinutes),14,p.Primary,true)); var pct=DetailVisual.Text($"{window.RemainingPercent}%",28,Ui.Accent(window.RemainingPercent),true); Grid.SetColumn(pct,1); row.Children.Add(pct); top.Children.Add(row);
            top.Children.Add(new DetailProgress { Height=4,Margin=new Thickness(16,0,16,13),Percent=window.RemainingPercent,Track=p.Track });
        }
        top.Children.Add(DetailVisual.Separator(p)); top.Children.Add(TokenBand(tokens,quota,copy,p)); top.Children.Add(DetailVisual.Separator(p));
        var rows=new StackPanel { Margin=new Thickness(16,8,16,8) };
        if(quota.Plan is not null) Row(rows,copy.Text("Plan","套餐","方案"),Value(quota.Plan,p),p);
        foreach(var window in new[]{quota.Primary,quota.Secondary}.OfType<QuotaWindow>()) Row(rows,copy.Text("Next reset","下次重置","下次重設")+"（"+copy.Period(window.WindowMinutes)+"）",Countdown(window.ResetsAt,copy,p,Ui.Accent(window.RemainingPercent)),p);
        Row(rows,copy.Text("Bank available","Bank 可用次数","Bank 可用次數"),Value(quota.Bank?.AvailableCount.ToString()??copy.NoData,p),p);
        if(quota.Bank?.Credits is { } credits) {
            var index=0;
            foreach(var credit in credits.OrderBy(c=>c.ExpiresAt??DateTimeOffset.MaxValue)) {
                var accent=credit.ExpiresAt is { } expiry?Ui.Accent((expiry-DateTimeOffset.Now).TotalDays<=3?10:(expiry-DateTimeOffset.Now).TotalDays<=7?49:100):p.Primary;
                Row(rows,$"Bank {++index}",credit.ExpiresAt is { } reset?Countdown(reset,copy,p,accent):Value(copy.NoData,p),p);
            }
        }
        Row(rows,"Credits",Value(quota.Credits is { } balance?balance.Unlimited?copy.Text("Unlimited","无限","無限"):balance.HasCredits?balance.Balance??copy.Text("Available","可用"):copy.Text("None","无","無"):copy.NoData,p),p);
        if(tokens is not null) {
            Row(rows,copy.Text("Lifetime tokens","累计 Token","累計 Token"),Value(tokens.LifetimeTokens?.ToString("N0")??copy.NoData,p),p);
            Row(rows,copy.Text("Peak daily tokens","最高单日 Token","最高單日 Token"),Value(tokens.PeakDailyTokens?.ToString("N0")??copy.NoData,p),p);
            Row(rows,copy.Text("Longest turn","最长运行时长","最長執行時長"),Value(tokens.LongestTurnSeconds is long sec?$"{sec/3600}:{sec%3600/60:00}:{sec%60:00}":copy.NoData,p),p);
            Row(rows,copy.Text("Current streak","当前连续天数","目前連續天數"),Value(tokens.CurrentStreakDays?.ToString()??copy.NoData,p),p);
            Row(rows,copy.Text("Longest streak","最长连续天数","最長連續天數"),Value(tokens.LongestStreakDays?.ToString()??copy.NoData,p),p);
        }
        Row(rows,copy.Text("Updated","更新时间","更新時間"),Value(copy.PhaseLabel(state.Phase)+" · "+quota.ReceivedAt.ToLocalTime().ToString("HH:mm:ss"),p),p);
        var footer=Footer(identity,copy,p); var bottom=new StackPanel();
        var resize=new Thumb { Height=14,Cursor=Cursors.SizeNS,Background=Brushes.Transparent,Template=ResizeTemplate(p) };
        resize.ToolTip=copy.Text("Drag to resize details","拖动调整详情高度","拖曳調整詳情高度"); System.Windows.Automation.AutomationProperties.SetName(resize,(string)resize.ToolTip);
        resize.DragDelta+=(_,e)=> { var area=Platform.WorkArea(Platform.Bounds(this).Location); Height=Math.Clamp(Height+e.VerticalChange,220,Math.Max(220,area.Height/VisualTreeHelper.GetDpi(this).DpiScaleY)); HeightChanged?.Invoke(Height); };
        bottom.Children.Add(resize); bottom.Children.Add(DetailVisual.Separator(p)); bottom.Children.Add(footer);
        var offset=scroll.VerticalOffset; scroll.Content=rows; if(scroll.Parent is Panel old) old.Children.Remove(scroll);
        var grid=new Grid(); grid.RowDefinitions.Add(new() { Height=GridLength.Auto }); grid.RowDefinitions.Add(new() { Height=new GridLength(1,GridUnitType.Star) }); grid.RowDefinitions.Add(new() { Height=GridLength.Auto }); grid.Children.Add(top); Grid.SetRow(scroll,1); grid.Children.Add(scroll); Grid.SetRow(bottom,2); grid.Children.Add(bottom);
        Content=new Border { Background=p.Surface,BorderBrush=p.Border,BorderThickness=new Thickness(.5),CornerRadius=new CornerRadius(12),Child=grid };
        if(!IsVisible) Show();
        var work=Platform.WorkArea(anchor.Location); var scale=VisualTreeHelper.GetDpi(this).DpiScaleY; Height=Math.Min(Math.Max(220,prefs.DetailHeight),work.Height/scale);
        // On very short work areas keep every section reachable instead of clipping fixed bands.
        top.Measure(new Size(358,double.PositiveInfinity)); bottom.Measure(new Size(358,double.PositiveInfinity));
        if(top.DesiredSize.Height+bottom.DesiredSize.Height+64>Height) {
            grid.Children.Clear(); var compact=new StackPanel(); scroll.Content=null; compact.Children.Add(top); compact.Children.Add(rows); compact.Children.Add(bottom);
            ((Border)Content).Child=new ScrollViewer { Content=compact,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
        }
        var y=anchor.Bottom+5; if(y+Height*scale>work.Y+work.Height) y=anchor.Top-Height*scale-5; Platform.Place(this,new(anchor.Right-Width*scale,y)); scroll.ScrollToVerticalOffset(offset);
    }
    static TextBlock Value(string text,DetailPalette p) { var value=DetailVisual.Text(text,13,p.Primary); value.TextAlignment=TextAlignment.Right; return value; }
    static TextBlock Countdown(DateTimeOffset reset,Copy copy,DetailPalette p,Brush accent) {
        var text=Value("",p); text.Inlines.Add(new Run(copy.Reset(reset)+"\n") { FontSize=13,Foreground=p.Primary });
        foreach(var part in System.Text.RegularExpressions.Regex.Split(copy.Countdown(reset,DateTimeOffset.Now),"([0-9]+)")) text.Inlines.Add(new Run(part) { FontSize=part.Length>0 && char.IsDigit(part[0])?16:11,FontWeight=part.Length>0 && char.IsDigit(part[0])?FontWeights.SemiBold:FontWeights.Normal,Foreground=part.Length>0 && char.IsDigit(part[0])?accent:p.Secondary }); return text;
    }
    static void Row(Panel rows,string label,TextBlock value,DetailPalette p) {
        if(rows.Children.Count>0) rows.Children.Add(DetailVisual.Separator(p)); var row=new Grid { MinHeight=value.Inlines.OfType<Run>().Any(r=>r.Text.Contains('\n'))?46:32 };
        row.ColumnDefinitions.Add(new() { Width=new GridLength(126) }); row.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) }); row.Children.Add(DetailVisual.Text(label,13,p.Primary,true)); Grid.SetColumn(value,1); row.Children.Add(value); rows.Children.Add(row);
    }
    static Border TokenBand(TokenUsage? tokens,QuotaSnapshot quota,Copy copy,DetailPalette p) {
        var panel=new StackPanel { Margin=new Thickness(16,7,16,9) }; var heading=new Grid(); heading.ColumnDefinitions.Add(new() { Width=GridLength.Auto }); heading.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) }); heading.Children.Add(DetailVisual.Text(copy.Text("Token usage","Token 用量","Token 用量"),17,p.Primary,true));
        IReadOnlyList<TokenDay>? days=null; try { if(tokens is not null) days=TokenWindow.Days(tokens,quota,DateTimeOffset.Now); } catch(FormatException) { }
        string total; try { total=days is null?copy.NoData:copy.Text("This period total ","本周期总计 ","本週期總計 ")+TokenCount(TokenWindow.Total(days))+" tokens"; } catch(FormatException) { days=null; total=copy.NoData; }
        var sum=DetailVisual.Text(total,13,p.Secondary); sum.TextAlignment=TextAlignment.Right; Grid.SetColumn(sum,1); heading.Children.Add(sum); panel.Children.Add(heading);
        var chart=new UniformGrid { Columns=7,Height=96,Margin=new Thickness(0,10,0,0) }; var max=days is null?1:Math.Max(1,days.Max(d=>d.Tokens));
        foreach(var day in days??Enumerable.Range(0,7).Select(i=>new TokenDay(DateOnly.FromDateTime(DateTime.Now).AddDays(i-6),0)).ToArray()) {
            var current=day.Date==DateOnly.FromDateTime(DateTime.Now); var labels=new StackPanel { VerticalAlignment=VerticalAlignment.Bottom }; var amount=DetailVisual.Text(days is null?"—":TokenCount(day.Tokens),10,current?Ui.Accent(quota.Primary.RemainingPercent):p.Secondary); amount.HorizontalAlignment=HorizontalAlignment.Center; labels.Children.Add(amount);
            labels.Children.Add(new Border { Width=18,Height=day.Tokens==0?2:Math.Max(4,Math.Min(42,42d*day.Tokens/max)),Background=current?Ui.Accent(quota.Primary.RemainingPercent):p.Border,CornerRadius=new CornerRadius(3),Margin=new Thickness(0,4,0,4),HorizontalAlignment=HorizontalAlignment.Center,ToolTip=$"{day.Date}: {day.Tokens:N0}" }); var date=DetailVisual.Text(day.Date.ToString("M/d"),9,p.Secondary); date.HorizontalAlignment=HorizontalAlignment.Center; labels.Children.Add(date); chart.Children.Add(labels);
        }
        panel.Children.Add(chart); return new Border { Child=panel };
    }
    static string TokenCount(long tokens)=>tokens>=1_000_000_000?$"{tokens/1_000_000_000d:0.##}B":tokens>=1_000_000?$"{tokens/1_000_000d:0.##}M":tokens>=1_000?$"{tokens/1_000d:0.##}K":tokens.ToString(System.Globalization.CultureInfo.InvariantCulture);
    static ControlTemplate ResizeTemplate(DetailPalette p) {
        var shell=new FrameworkElementFactory(typeof(Border)); shell.SetValue(Border.BackgroundProperty,Brushes.Transparent); var grip=new FrameworkElementFactory(typeof(Border)); grip.SetValue(FrameworkElement.WidthProperty,20d); grip.SetValue(FrameworkElement.HeightProperty,3d); grip.SetValue(FrameworkElement.HorizontalAlignmentProperty,HorizontalAlignment.Center); grip.SetValue(FrameworkElement.VerticalAlignmentProperty,VerticalAlignment.Center); grip.SetValue(Border.BackgroundProperty,p.Secondary); grip.SetValue(Border.CornerRadiusProperty,new CornerRadius(1.5)); grip.SetValue(UIElement.OpacityProperty,.72); shell.AppendChild(grip); return new ControlTemplate(typeof(Thumb)) { VisualTree=shell };
    }
    Grid Footer(AccountIdentity? identity,Copy copy,DetailPalette p) {
        var footer=new Grid { Margin=new Thickness(16,8,12,10) }; foreach(var width in new[]{GridLength.Auto,new GridLength(1,GridUnitType.Star),GridLength.Auto,GridLength.Auto}) footer.ColumnDefinitions.Add(new() { Width=width });
        var key=(identity?.PreferredName??"")+"|"+(identity?.AvatarUrl??"");
        if(key!=avatarKey || avatar is null) {
            avatarKey=key; var initials=(identity?.PreferredName??"Q").Trim(); initials=initials.Length==0?"Q":initials[..1].ToUpperInvariant();
            avatar=new Border { Width=26,Height=26,CornerRadius=new CornerRadius(13),Background=new SolidColorBrush(Color.FromRgb(81,93,136)),Child=new TextBlock { Text=initials,Foreground=Brushes.White,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,FontWeight=FontWeights.Bold } };
            if(Uri.TryCreate(identity?.AvatarUrl,UriKind.Absolute,out var url) && url.Scheme=="https") try { avatar=new Image { Width=26,Height=26,Source=new System.Windows.Media.Imaging.BitmapImage(url),Clip=new EllipseGeometry(new Point(13,13),13,13) }; } catch(Exception e) when(e is IOException or System.Net.WebException or NotSupportedException) { }
        }
        if(avatar.Parent is Panel oldParent) oldParent.Children.Remove(avatar); footer.Children.Add(avatar);
        var name=DetailVisual.Text(identity?.PreferredName??"QuotaBar",13,p.Primary); name.Margin=new Thickness(8,0,8,0); name.TextWrapping=TextWrapping.NoWrap; name.TextTrimming=TextTrimming.CharacterEllipsis; Grid.SetColumn(name,1); footer.Children.Add(name);
        var github=DetailVisual.Button("GitHub",()=>Platform.OpenUrl("https://github.com/JaceHwang/codex-usage-sidebar"),"GitHub",p); var githubContent=new StackPanel { Orientation=Orientation.Horizontal }; githubContent.Children.Add(new System.Windows.Shapes.Path { Data=Geometry.Parse("M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.084-.73.084-.73 1.205.084 1.84 1.237 1.84 1.237 1.07 1.834 2.807 1.304 3.492.997.108-.775.418-1.305.762-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.292-1.552 3.296-1.23 3.296-1.23.647 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.43.372.81 1.102.81 2.222 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.595 24 12.297c0-6.627-5.373-12-12-12z"),Width=15,Height=15,Stretch=Stretch.Uniform,Fill=p.Secondary,Margin=new Thickness(0,0,5,0) }); githubContent.Children.Add(DetailVisual.Text("GitHub",11,p.Secondary)); github.Content=githubContent; Grid.SetColumn(github,2); footer.Children.Add(github);
        var settings=DetailVisual.Button("\uE713",()=>SettingsRequested?.Invoke(),copy.Text("Settings","设置","設定"),p,true); Grid.SetColumn(settings,3); footer.Children.Add(settings);
        var all=new Grid(); all.RowDefinitions.Add(new() { Height=GridLength.Auto }); all.RowDefinitions.Add(new() { Height=GridLength.Auto }); all.Children.Add(footer); var info=DetailVisual.Button(copy.Text("Tibo on X","Tibo 的 X 动态","Tibo 的 X 動態"),()=>Platform.OpenUrl("https://x.com/thsottiaux"),"Tibo on X",p); Grid.SetRow(info,1); all.Children.Add(info); return all;
    }
}
