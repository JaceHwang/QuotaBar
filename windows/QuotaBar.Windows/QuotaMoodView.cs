namespace QuotaBar.Windows;
internal sealed class QuotaMoodView : FrameworkElement {
    public QuotaMood Mood { get; set; }=QuotaMood.Unavailable;
    public bool Dark { get; set; }
    public bool Stars { get; set; }
    public bool ShowCharacter { get; set; }=true;
    public double Phase { get; set; }
    public QuotaMoodView() { Width=20; Height=20; IsHitTestVisible=false; }
    protected override void OnRender(DrawingContext dc) {
        dc.PushTransform(new ScaleTransform(ActualWidth/20,ActualHeight/20));
        var ink=Dark?Brushes.WhiteSmoke:new SolidColorBrush(Color.FromRgb(26,59,54)); var pen=new Pen(ink,1.2);
        var fill=new SolidColorBrush(Mood switch { QuotaMood.Good=>Color.FromRgb(122,224,168),QuotaMood.Recovered=>Color.FromRgb(192,150,245),QuotaMood.Low=>Color.FromRgb(255,201,92),QuotaMood.Exhausted=>Color.FromRgb(250,145,143),_=>Color.FromRgb(166,166,166) });
        if(ShowCharacter) {
            dc.DrawRoundedRectangle(ink,null,new Rect(8,1,4,3),1,1);
            dc.DrawRoundedRectangle(fill,pen,new Rect(4,3,12,14),3.2,3.2);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(100,255,255,255)),null,new Rect(5.5,4,1.6,6),.8,.8);
            if(Mood==QuotaMood.Recovered) {
                dc.DrawLine(new Pen(ink,1.6),new Point(4,11),new Point(1.8,7.5)); dc.DrawLine(new Pen(ink,1.6),new Point(16,11),new Point(18.2,7.5));
                dc.DrawEllipse(ink,null,new Point(1.8,7.5),1.2,1.2); dc.DrawEllipse(ink,null,new Point(18.2,7.5),1.2,1.2);
            } else { dc.DrawEllipse(ink,null,new Point(3.5,12.5),1.5,1.5); dc.DrawEllipse(ink,null,new Point(16.5,12.5),1.5,1.5); }
            dc.DrawRoundedRectangle(ink,null,new Rect(6,16.5,2.8,2),.8,.8); dc.DrawRoundedRectangle(ink,null,new Rect(11,16.5,2.8,2),.8,.8);
            var face=new SolidColorBrush(Color.FromRgb(26,59,54)); var facePen=new Pen(face,1);
            if(Mood==QuotaMood.Unavailable) dc.DrawText(new FormattedText("?",System.Globalization.CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),10,face,VisualTreeHelper.GetDpi(this).PixelsPerDip),new Point(7,4));
            else {
                foreach(var x in new[]{7.2,11.2}) {
                    if(Mood==QuotaMood.Recovered) DrawStar(dc,new Point(x+.8,8.6),2,Brushes.Gold);
                    else if(Mood==QuotaMood.Exhausted) dc.DrawLine(facePen,new Point(x,9),new Point(x+1.5,10));
                    else dc.DrawEllipse(face,null,new Point(x+.8,8.6),.8,.9);
                }
                if(Mood==QuotaMood.Recovered) { dc.DrawEllipse(face,null,new Point(10,12.5),2,1.6); dc.DrawEllipse(Brushes.Coral,null,new Point(10,13.2),1.1,.5); }
                else { var mouth=new StreamGeometry(); using(var context=mouth.Open()) { context.BeginFigure(new Point(8.4,12),false,false); var y=Mood is QuotaMood.Good or QuotaMood.Recovered?14.3:11; context.BezierTo(new Point(9,y),new Point(11,y),new Point(11.6,12),true,false); } dc.DrawGeometry(null,facePen,mouth); }
            }
        }
        if(Stars || Mood==QuotaMood.Recovered) {
            var star=new SolidColorBrush(Color.FromArgb((byte)(170+85*Math.Abs(Math.Sin(Phase))),255,198,0));
            foreach(var (x,y) in new[]{(2d,4d),(18d,7d),(17.5,17d)}) {
                var shape=new StreamGeometry(); using(var c=shape.Open()) { c.BeginFigure(new Point(x,y-2),true,true); foreach(var p in new[]{new Point(x+.7,y-.7),new Point(x+2,y),new Point(x+.7,y+.7),new Point(x,y+2),new Point(x-.7,y+.7),new Point(x-2,y),new Point(x-.7,y-.7)}) c.LineTo(p,true,false); } dc.DrawGeometry(star,null,shape);
            }
        }
        dc.Pop();
    }
    static void DrawStar(DrawingContext dc,Point center,double radius,Brush fill) {
        var shape=new StreamGeometry(); using(var c=shape.Open()) {
            for(var i=0;i<10;i++) { var angle=-Math.PI/2+i*Math.PI/5; var r=i%2==0?radius:radius*.44; var p=new Point(center.X+Math.Cos(angle)*r,center.Y+Math.Sin(angle)*r); if(i==0) c.BeginFigure(p,true,true); else c.LineTo(p,true,false); }
        } dc.DrawGeometry(fill,null,shape);
    }
}
internal sealed class RecoveryCelebrationController : IDisposable {
    readonly DispatcherTimer timer=new(); DateTimeOffset? deadline; DateTimeOffset start;
    public Action<bool,double>? Changed { get; set; }
    public bool Active=>deadline is not null;
    public RecoveryCelebrationController() { timer.Tick+=(_,_)=> { if(DateTimeOffset.UtcNow>=deadline) Cancel(); else Changed?.Invoke(true,(DateTimeOffset.UtcNow-start).TotalSeconds*8); }; }
    public void Play(bool visible) {
        if(!visible || Active) return; start=DateTimeOffset.UtcNow; deadline=start.AddSeconds(2); Changed?.Invoke(true,0);
        timer.Interval=TimeSpan.FromSeconds(SystemParameters.ClientAreaAnimation ? .08 : 2); timer.Start();
    }
    public void Cancel() { timer.Stop(); deadline=null; Changed?.Invoke(false,0); }
    public void Dispose()=>Cancel();
}
