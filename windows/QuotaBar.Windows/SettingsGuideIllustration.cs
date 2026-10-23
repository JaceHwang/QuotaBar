namespace QuotaBar.Windows;
// Native drawing, deliberately an instructional diagram rather than an official Bark screenshot.
internal sealed class BarkPhoneIllustration : FrameworkElement {
    public bool Dark { get; init; }
    protected override void OnRender(DrawingContext dc) {
        dc.PushTransform(new ScaleTransform(ActualWidth/112,ActualHeight/150));
        var pen=new Pen(new SolidColorBrush(Color.FromRgb(32,39,49)),3);
        dc.DrawRoundedRectangle(Brushes.White,pen,new Rect(13,2,86,146),15,15);
        dc.DrawRoundedRectangle(Brushes.Black,null,new Rect(37,4,38,7),4,4);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(247,71,100)),null,new Rect(24,24,20,20),5,5);
        var bell=Geometry.Parse("M 29,38 L 39,38 C 36,35 39,29 34,29 C 29,29 32,35 29,38 M 33,40 L 35,40"); dc.DrawGeometry(null,new Pen(Brushes.White,1.4),bell);
        Label("Bark",48,28,11,Brushes.Black); Label("DEMO",24,53,9,Brushes.Gray);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(239,243,248)),null,new Rect(23,68,66,34),5,5);
        for(var i=0;i<3;i++) dc.DrawLine(new Pen(Brushes.LightGray,2),new Point(28,76+i*8),new Point(82-i*8,76+i*8));
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(0,139,253)),null,new Rect(23,112,66,23),5,5); Label("TEST",43,117,10,Brushes.White);
        dc.Pop();
        void Label(string text,double x,double y,double size,Brush brush) { var formatted=new FormattedText(text,System.Globalization.CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),size,brush,VisualTreeHelper.GetDpi(this).PixelsPerDip); dc.DrawText(formatted,new Point(x,y)); }
    }
}
internal sealed class AboutBatteryIllustration : FrameworkElement {
    protected override void OnRender(DrawingContext dc) {
        dc.PushTransform(new ScaleTransform(ActualWidth/84,ActualHeight/84));
        var ink=new Pen(new SolidColorBrush(Color.FromRgb(34,65,55)),2.4);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(206,253,229)),null,new Rect(0,0,84,84),22,22);
        dc.DrawRoundedRectangle(Brushes.White,ink,new Rect(36,10,12,9),3,3);
        dc.DrawLine(ink,new Point(29,70),new Point(27,76)); dc.DrawLine(ink,new Point(50,70),new Point(53,76));
        dc.DrawLine(ink,new Point(20,51),new Point(14,57)); dc.DrawLine(ink,new Point(61,43),new Point(69,36));
        dc.DrawRoundedRectangle(Brushes.White,ink,new Rect(21,18,40,52),8,8);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(136,231,184)),null,new Rect(25,23,32,42),5,5);
        dc.DrawEllipse(ink.Brush,null,new Point(34,43),1.8,2.1); dc.DrawEllipse(ink.Brush,null,new Point(49,43),1.8,2.1);
        dc.DrawGeometry(null,ink,Geometry.Parse("M 37,49 Q 42,55 47,49"));
        dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(248,165,171)),null,new Point(30,49),3,2); dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(248,165,171)),null,new Point(53,49),3,2); dc.Pop();
    }
}
