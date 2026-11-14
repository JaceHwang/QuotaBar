namespace QuotaBar.Windows;

// Visual metrics and palette retained from the Windows plugin v0.4.1.
internal sealed record DetailPalette(Brush Primary,Brush Secondary,Brush Surface,Brush Border,Brush Track,Brush Badge,bool Dark) {
    public static DetailPalette For(bool dark) => SystemParameters.HighContrast ? new(SystemColors.WindowTextBrush,SystemColors.GrayTextBrush,SystemColors.WindowBrush,SystemColors.ActiveBorderBrush,SystemColors.ControlBrush,SystemColors.HighlightBrush,dark) : dark ? new(Rgb(230,230,230),Rgb(154,154,154),Rgb(30,30,30),Rgb(63,63,63),Rgb(58,58,58),Rgb(10,132,255),true) : new(Rgb(23,23,23),Rgb(112,112,112),Brushes.White,Rgb(208,208,208),Rgb(231,231,231),Rgb(0,122,255),false);
    static Brush Rgb(byte r,byte g,byte b)=>new SolidColorBrush(Color.FromRgb(r,g,b));
}
internal static class DetailVisual {
    public static TextBlock Text(string text,double size,Brush brush,bool bold=false)=>new() { Text=text,FontFamily=new FontFamily("Segoe UI"),FontSize=size,FontWeight=bold?FontWeights.SemiBold:FontWeights.Normal,Foreground=brush,VerticalAlignment=VerticalAlignment.Center,TextWrapping=TextWrapping.Wrap };
    public static Border Separator(DetailPalette p)=>new() { Height=1,Background=p.Border,Opacity=.6 };
    public static Button Button(string content,Action action,string name,DetailPalette p,bool glyph=false,bool active=false) {
        var button=Ui.Button(content,action,name); button.FontFamily=new FontFamily(glyph?"Segoe Fluent Icons, Segoe MDL2 Assets":"Segoe UI"); button.FontSize=glyph?13:11;
        SettingsVisual.ApplyVariant(button,active?SettingsVisual.ButtonVariant.Tertiary:glyph?SettingsVisual.ButtonVariant.Ghost:SettingsVisual.ButtonVariant.Text,p.Dark);
        if(!active) button.Foreground=p.Secondary;
        button.BorderThickness=new Thickness(0); button.Margin=new Thickness(0); button.Padding=new Thickness(6,4,6,4); button.MinHeight=26; button.Cursor=Cursors.Hand;
        return button;
    }
}
internal sealed class DetailProgress : FrameworkElement {
    public int Percent { get; init; }
    public Brush Track { get; init; }=Brushes.Gray;
    protected override void OnRender(DrawingContext dc) {
        base.OnRender(dc); var rect=new Rect(0,0,ActualWidth,ActualHeight); if(rect.IsEmpty || rect.Width<=0 || rect.Height<=0) return;
        dc.DrawRoundedRectangle(Track,null,rect,2,2);
        var width=rect.Width*Math.Clamp(Percent,0,100)/100; if(width<=0) return;
        var spectrum=new LinearGradientBrush { StartPoint=new Point(0,.5),EndPoint=new Point(1,.5) };
        foreach(var pct in new[]{0,10,49,100}) spectrum.GradientStops.Add(new GradientStop(((SolidColorBrush)Ui.Accent(pct)).Color,pct/100d));
        dc.PushClip(new RectangleGeometry(new Rect(0,0,width,rect.Height),2,2)); dc.DrawRoundedRectangle(spectrum,null,rect,2,2); dc.Pop();
    }
}
