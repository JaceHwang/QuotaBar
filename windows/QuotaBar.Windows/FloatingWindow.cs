namespace QuotaBar.Windows;
internal sealed class FloatingWindow : Window {
    readonly Grid content=new();
    readonly Border surface=new() { CornerRadius=new CornerRadius(10),Padding=new Thickness(6,0,4,0),Background=Brushes.Transparent };
    readonly Button close;
    internal Button CloseControl=>close;
    Point? down,origin;
    bool dragging;
    public event Action? Primary,Secondary,Entered,CloseRequested;
    public event Action<Point>? PositionChanged;
    public FloatingWindow() {
        Title="QuotaBar"; Height=30; Width=320; WindowStyle=WindowStyle.None; AllowsTransparency=true; Background=Brushes.Transparent;
        ShowInTaskbar=false; ShowActivated=false; ResizeMode=ResizeMode.NoResize; Topmost=true;
        Platform.Passive(this);
        close=Ui.Button("×",()=>CloseRequested?.Invoke());
        close.FontSize=16; close.Padding=new Thickness(0); close.Margin=new Thickness(2,0,0,0); close.MinHeight=20; close.Height=20; close.Width=20;
        close.Background=Brushes.Transparent; close.BorderThickness=new Thickness(0); close.Visibility=Visibility.Hidden;
        content.ColumnDefinitions.Add(new() { Width=new GridLength(26) });
        content.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
        content.ColumnDefinitions.Add(new() { Width=new GridLength(24) });
        surface.Child=content; Content=surface;
        MouseEnter+=(_,_)=> { close.Visibility=Visibility.Visible; Entered?.Invoke(); };
        MouseLeave+=(_,_)=>close.Visibility=Visibility.Hidden;
        MouseRightButtonUp+=(_,e)=> { e.Handled=true; Secondary?.Invoke(); };
        MouseLeftButtonDown+=(_,e)=> { down=Platform.Cursor; var b=Platform.Bounds(this); origin=b.Location; dragging=false; CaptureMouse(); e.Handled=true; };
        MouseMove+=(_,_)=> {
            if(down is not Point start || origin is not Point saved || Mouse.LeftButton!=MouseButtonState.Pressed) return;
            var delta=Platform.Cursor-start;
            if(!dragging && delta.Length<4*VisualTreeHelper.GetDpi(this).DpiScaleX) return;
            dragging=true; Cursor=Cursors.SizeAll; Platform.Place(this,saved+delta);
        };
        MouseLeftButtonUp+=(_,e)=> {
            if(down is null) return;
            var wasDragging=dragging;
            ReleaseMouseCapture(); down=null; Cursor=Cursors.Hand;
            if(wasDragging) PositionChanged?.Invoke(Platform.Bounds(this).Location); else Primary?.Invoke();
            dragging=false; e.Handled=true;
        };
        LostMouseCapture+=(_,_)=> { down=null; dragging=false; Cursor=Cursors.Hand; };
    }
    public void Render(QuotaSnapshot? quota,RefreshState state,Preferences preferences,Copy copy,bool dark) {
        if(!preferences.FloatingEnabled) { HideFloat(); return; }
        var fg=Ui.Foreground(dark);
        surface.Background=dark?new SolidColorBrush(Color.FromArgb(230,30,31,35)):new SolidColorBrush(Color.FromArgb(235,245,245,245));
        close.Foreground=fg; close.ToolTip=copy.Text("Close floating button","关闭悬浮按钮","關閉懸浮按鈕");
        System.Windows.Automation.AutomationProperties.SetName(close,(string)close.ToolTip);
        foreach(var child in content.Children.Cast<UIElement>().Where(v=>v!=close).ToArray()) content.Children.Remove(child);
        var icon=Ui.Icon(dark); content.Children.Add(icon);
        var rows=new StackPanel { VerticalAlignment=VerticalAlignment.Center };
        if(quota is null) rows.Children.Add(Ui.Text(copy.PhaseLabel(state.Phase),11,fg));
        else foreach(var window in new[]{quota.Primary,quota.Secondary}.OfType<QuotaWindow>()) {
            var row=new Grid(); row.ColumnDefinitions.Add(new() { Width=new GridLength(50) }); row.ColumnDefinitions.Add(new() { Width=new GridLength(42) }); row.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
            var label=Ui.Text(copy.Period(window.WindowMinutes),11,fg); label.FontWeight=FontWeights.Medium;
            var pct=Ui.Text($"{window.RemainingPercent}%",12,Ui.Accent(window.RemainingPercent)); pct.FontWeight=FontWeights.Bold;
            var reset=Ui.Text("· "+copy.Reset(window.ResetsAt),11,fg); reset.TextWrapping=TextWrapping.NoWrap;
            row.Children.Add(label); Grid.SetColumn(pct,1); row.Children.Add(pct); Grid.SetColumn(reset,2); row.Children.Add(reset); rows.Children.Add(row);
        }
        Grid.SetColumn(rows,1); content.Children.Add(rows); Grid.SetColumn(close,2); if(!content.Children.Contains(close)) content.Children.Add(close);
        rows.Measure(new Size(double.PositiveInfinity,30)); Width=Math.Min(440,Math.Max(220,rows.DesiredSize.Width+60));
        Opacity=state.Phase==Phase.Ready?1:.55;
        ToolTip=copy.Indicator(quota,state.Phase)+"\n"+copy.PhaseLabel(state.Phase);
        if(!IsVisible) { close.Visibility=Visibility.Hidden; Show(); }
        if(!dragging) {
            var area=Platform.WorkArea(new Point(preferences.FloatingX??int.MaxValue,preferences.FloatingY??0));
            Platform.Place(this,new(preferences.FloatingX??area.X+area.Width-Width-24,preferences.FloatingY??area.Y+24));
        }
    }
    public void HideFloat() { close.Visibility=Visibility.Hidden; down=null; dragging=false; if(IsMouseCaptured) ReleaseMouseCapture(); Hide(); }
}
