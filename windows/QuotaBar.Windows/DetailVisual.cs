namespace QuotaBar.Windows;

// Visual metrics and palette retained from the Windows plugin v0.4.1.
internal sealed record DetailPalette(Brush Primary,Brush Secondary,Brush Surface,Brush Border,Brush Track,Brush Badge) {
    public static DetailPalette For(bool dark) => SystemParameters.HighContrast ? new(SystemColors.WindowTextBrush,SystemColors.GrayTextBrush,SystemColors.WindowBrush,SystemColors.ActiveBorderBrush,SystemColors.ControlBrush,SystemColors.HighlightBrush) : dark ? new(Rgb(230,230,230),Rgb(154,154,154),Rgb(30,30,30),Rgb(63,63,63),Rgb(58,58,58),Rgb(10,132,255)) : new(Rgb(23,23,23),Rgb(112,112,112),Brushes.White,Rgb(208,208,208),Rgb(231,231,231),Rgb(0,122,255));
    static Brush Rgb(byte r,byte g,byte b)=>new SolidColorBrush(Color.FromRgb(r,g,b));
}
internal static class DetailVisual {
    public static TextBlock Text(string text,double size,Brush brush,bool bold=false)=>new() { Text=text,FontFamily=new FontFamily("Segoe UI"),FontSize=size,FontWeight=bold?FontWeights.SemiBold:FontWeights.Normal,Foreground=brush,VerticalAlignment=VerticalAlignment.Center,TextWrapping=TextWrapping.Wrap };
    public static Border Separator(DetailPalette p)=>new() { Height=1,Background=p.Border,Opacity=.6 };
    public static Button Button(string content,Action action,string name,DetailPalette p,bool glyph=false,bool active=false) {
        var button=Ui.Button(content,action,name); button.FontFamily=new FontFamily(glyph?"Segoe Fluent Icons, Segoe MDL2 Assets":"Segoe UI"); button.FontSize=glyph?13:11;
        button.Foreground=active?p.Badge:p.Secondary; button.Background=Brushes.Transparent; button.BorderThickness=new Thickness(0); button.Margin=new Thickness(0); button.Padding=new Thickness(6,4,6,4); button.MinHeight=26; button.Cursor=Cursors.Hand;
        var chrome=new FrameworkElementFactory(typeof(Border)); chrome.Name="Chrome"; chrome.SetValue(Border.CornerRadiusProperty,new CornerRadius(8)); chrome.SetValue(Border.BackgroundProperty,active?new SolidColorBrush(Color.FromArgb(31,10,132,255)):Brushes.Transparent); chrome.SetValue(Border.PaddingProperty,new Thickness(6,4,6,4));
        var presenter=new FrameworkElementFactory(typeof(ContentPresenter)); presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty,HorizontalAlignment.Center); presenter.SetValue(ContentPresenter.VerticalAlignmentProperty,VerticalAlignment.Center); chrome.AppendChild(presenter);
        var template=new ControlTemplate(typeof(Button)) { VisualTree=chrome }; var hover=new Trigger { Property=System.Windows.Controls.Button.IsMouseOverProperty,Value=true }; hover.Setters.Add(new Setter(Border.BackgroundProperty,new SolidColorBrush(Color.FromArgb(24,128,128,128)),"Chrome")); template.Triggers.Add(hover); button.Template=template; return button;
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
