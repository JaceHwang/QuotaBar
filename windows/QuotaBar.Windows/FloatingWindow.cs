namespace QuotaBar.Windows;
internal sealed class FloatingWindow : Window {
    readonly Grid content=new();
    readonly Grid iconHost=new() { Width=28,Height=28,VerticalAlignment=VerticalAlignment.Center };
    readonly QuotaMoodView moodView=new() { Width=28,Height=28 };
    readonly RecoveryCelebrationController celebration=new();
    QuotaMood currentMood;
    internal bool IsCelebrating=>celebration.Active;
    internal void Celebrate()=>celebration.Play(IsVisible);
    internal void CancelCelebration()=>celebration.Cancel();
    readonly Border surface=new() { CornerRadius=new CornerRadius(10),Padding=new Thickness(6,0,4,0),Background=Brushes.Transparent };
    readonly Button close;
    internal Button CloseControl=>close;
    Point? down,origin;
    bool dragging;
    public event Action? Primary,Secondary,Entered,Exited,CloseRequested,DragStarted,DragFinished;
    readonly Border unreadDot=new() { Width=5,Height=5,CornerRadius=new CornerRadius(3),Background=Brushes.Orange,HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Top,IsHitTestVisible=false,Visibility=Visibility.Collapsed };
    public bool HasUnread { set=>unreadDot.Visibility=value?Visibility.Visible:Visibility.Collapsed; }
    public event Action<Point>? PositionChanged;
    public FloatingWindow() {
        Title="QuotaBar"; Height=30; Width=320; WindowStyle=WindowStyle.None; AllowsTransparency=true; Background=Brushes.Transparent;
        ShowInTaskbar=false; ShowActivated=false; ResizeMode=ResizeMode.NoResize; Topmost=true;
        Platform.Passive(this);
        celebration.Changed=(active,phase)=> { moodView.Stars=active; moodView.Phase=phase; moodView.Mood=active&&moodView.ShowCharacter?QuotaMood.Recovered:currentMood; moodView.InvalidateVisual(); };
        close=Ui.Button("×",()=>CloseRequested?.Invoke());
        close.FontSize=16; close.Padding=new Thickness(0); close.Margin=new Thickness(2,0,0,0); close.MinHeight=20; close.Height=20; close.Width=20;
        close.Background=Brushes.Transparent; close.BorderThickness=new Thickness(0); close.Visibility=Visibility.Hidden;
        content.ColumnDefinitions.Add(new() { Width=new GridLength(34) });
        content.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
        content.ColumnDefinitions.Add(new() { Width=new GridLength(24) });
        surface.Child=content; Content=surface; iconHost.Children.Add(unreadDot);
        MouseEnter+=(_,_)=> { close.Visibility=Visibility.Visible; Entered?.Invoke(); };
        MouseLeave+=(_,_)=> { close.Visibility=Visibility.Hidden; Exited?.Invoke(); };
        MouseRightButtonUp+=(_,e)=> { e.Handled=true; Secondary?.Invoke(); };
        MouseLeftButtonDown+=(_,e)=> { down=Platform.Cursor; var b=Platform.Bounds(this); origin=b.Location; dragging=false; CaptureMouse(); e.Handled=true; };
        MouseMove+=(_,_)=> {
            if(down is not Point start || origin is not Point saved || Mouse.LeftButton!=MouseButtonState.Pressed) return;
            var delta=Platform.Cursor-start;
            if(!dragging && delta.Length<4*VisualTreeHelper.GetDpi(this).DpiScaleX) return;
            if(!dragging) DragStarted?.Invoke(); CancelCelebration(); dragging=true; Cursor=Cursors.SizeAll; Platform.Place(this,saved+delta);
        };
        MouseLeftButtonUp+=(_,e)=> { if(down is null) return; FinishPointer(true);e.Handled=true; };
        LostMouseCapture+=(_,_)=>FinishPointer(false);
    }
    void FinishPointer(bool allowClick) {
        if(down is null) return;
        var wasDragging=dragging;
        var finalPosition=wasDragging?Platform.Bounds(this).Location:(Point?)null;
        // Clear state first: ReleaseMouseCapture raises LostMouseCapture synchronously.
        down=null;origin=null;dragging=false;Cursor=Cursors.Hand;
        if(finalPosition is {} position) PositionChanged?.Invoke(position);
        if(IsMouseCaptured) ReleaseMouseCapture();
        if(wasDragging) DragFinished?.Invoke();else if(allowClick) Primary?.Invoke();
    }

    public void Render(QuotaSnapshot? quota,RefreshState state,Preferences preferences,Copy copy,bool dark) {
        if(!preferences.FloatingEnabled) { HideFloat(); return; }
        var fg=Ui.Foreground(dark);
        var alpha=(byte)Math.Round(255*(1-preferences.Validated().FloatingBackgroundTransparency/100));
        surface.Background=new SolidColorBrush(dark?Color.FromArgb(alpha,0,0,0):Color.FromArgb(alpha,255,255,255));
        // Alpha-zero pixels in a layered HWND pass native mouse input through.
        // A 2/255 backing remains nonzero after unavailable-state dimming while
        // appearing transparent; the configured surface itself still reaches zero.
        Background=alpha==0?new SolidColorBrush(dark?Color.FromArgb(2,0,0,0):Color.FromArgb(2,255,255,255)):Brushes.Transparent;
        close.Foreground=fg; close.ToolTip=copy.Text("Close floating button","关闭悬浮按钮","關閉懸浮按鈕");
        System.Windows.Automation.AutomationProperties.SetName(close,(string)close.ToolTip);
        foreach(var child in content.Children.Cast<UIElement>().Where(v=>v!=close).ToArray()) content.Children.Remove(child);
        currentMood=QuotaMoods.Resolve(quota,state.Phase==Phase.Ready,DateTimeOffset.UtcNow);
        if(currentMood==QuotaMood.Unavailable) CancelCelebration();
        moodView.ShowCharacter=preferences.Experience.Moods; moodView.Dark=dark;
        moodView.Mood=celebration.Active&&moodView.ShowCharacter?QuotaMood.Recovered:currentMood;
        iconHost.Children.Clear(); if(!preferences.Experience.Moods) iconHost.Children.Add(Ui.Icon(dark));
        iconHost.Children.Add(moodView); moodView.InvalidateVisual(); content.Children.Add(iconHost);
        var rows=new StackPanel { VerticalAlignment=VerticalAlignment.Center };
        if(quota is null) rows.Children.Add(Ui.Text(copy.PhaseLabel(state.Phase),11,fg));
        else {
        var windows=new[]{quota.Primary,quota.Secondary}.OfType<QuotaWindow>().ToArray();
        var labels=windows.Select(w=> { var label=Ui.Text(copy.Period(w.WindowMinutes),11,fg); label.TextWrapping=TextWrapping.NoWrap; label.FontWeight=FontWeights.Medium; label.Measure(new Size(double.PositiveInfinity,double.PositiveInfinity)); return label; }).ToArray();
        var labelWidth=Math.Max(50,labels.Max(label=>Math.Ceiling(label.DesiredSize.Width)));
        for(var i=0;i<windows.Length;i++) {
            var window=windows[i]; var label=labels[i];
            var row=new Grid(); row.ColumnDefinitions.Add(new() { Width=new GridLength(labelWidth) }); row.ColumnDefinitions.Add(new() { Width=new GridLength(42) }); row.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
            var pct=Ui.Text($"{window.RemainingPercent}%",12,Ui.Accent(window.RemainingPercent)); pct.FontWeight=FontWeights.Bold;
            var reset=Ui.Text("· "+copy.Reset(window.ResetsAt),11,fg); reset.TextWrapping=TextWrapping.NoWrap;
            row.Children.Add(label); Grid.SetColumn(pct,1); row.Children.Add(pct); Grid.SetColumn(reset,2); row.Children.Add(reset); rows.Children.Add(row);
        }
        }
        Grid.SetColumn(rows,1); content.Children.Add(rows); Grid.SetColumn(close,2); if(!content.Children.Contains(close)) content.Children.Add(close);
        rows.Measure(new Size(double.PositiveInfinity,30)); Width=Math.Min(440,Math.Max(220,rows.DesiredSize.Width+68));
        Opacity=currentMood==QuotaMood.Unavailable?.55:1;
        ToolTip=copy.Indicator(quota,state.Phase)+"\n"+copy.PhaseLabel(state.Phase)+(preferences.Experience.Moods?"\n"+new ExperienceCopy(preferences.Language).MoodLabel(currentMood):"");
        System.Windows.Automation.AutomationProperties.SetName(this,ToolTip.ToString());
        if(!IsVisible) { close.Visibility=Visibility.Hidden; Show(); }
        if(!dragging) {
            var area=Platform.WorkArea(new Point(preferences.FloatingX??int.MaxValue,preferences.FloatingY??0));
            Platform.Place(this,new(preferences.FloatingX??area.X+area.Width-Width-24,preferences.FloatingY??area.Y+24));
        }
    }
    public void HideFloat() { FinishPointer(false); CancelCelebration(); close.Visibility=Visibility.Hidden; Hide(); }
}
