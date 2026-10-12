using System.Windows.Automation;
using System.Windows.Media.Imaging;

namespace QuotaBar.Windows;
internal static class Ui {
    public static Brush Foreground(bool dark) => SystemParameters.HighContrast?SystemColors.WindowTextBrush:dark?Brushes.White:new SolidColorBrush(Color.FromRgb(32,32,34));
    public static Brush Surface(bool dark) => SystemParameters.HighContrast?SystemColors.WindowBrush:dark?new SolidColorBrush(Color.FromRgb(30,31,35)):Brushes.White;
    public static Brush Accent(int percent) { var (r,g,b)=QuotaColors.ForPercent(percent); return new SolidColorBrush(Color.FromRgb(r,g,b)); }
    public static TextBlock Text(string text,double size=13,Brush? brush=null) => new() { Text=text,FontSize=size,Foreground=brush??Brushes.Black,TextWrapping=TextWrapping.Wrap,VerticalAlignment=VerticalAlignment.Center };
    public static Button Button(string text,Action action,string? accessibleName=null) {
        var button=new Button { Content=text,Foreground=SystemColors.ControlTextBrush,Padding=new Thickness(10,5,10,5),Margin=new Thickness(3),MinHeight=28,Cursor=Cursors.Arrow };
        AutomationProperties.SetName(button,accessibleName??text); button.ToolTip=accessibleName;
        button.Click+=(_,e)=> { e.Handled=true; action(); }; return button;
    }
    public static Image Icon(bool dark,double size=20) => new() {
        Source=new BitmapImage(new Uri("pack://application:,,,/QuotaBar;component/Assets/quota-icon-"+(dark?"dark":"light")+".png")),
        Width=size,Height=size,Stretch=Stretch.Uniform,Clip=new EllipseGeometry(new Point(size/2,size/2),size/2,size/2),IsHitTestVisible=false
    };
    public static Border Divider() => new() { Height=1,Background=new SolidColorBrush(Color.FromArgb(25,128,128,128)),Margin=new Thickness(0,10,0,10) };
    public static Border Shell(UIElement content,bool dark,double radius=14) => new() { Child=content,Background=Surface(dark),CornerRadius=new CornerRadius(radius),BorderThickness=new Thickness(1),BorderBrush=new SolidColorBrush(Color.FromArgb(40,128,128,128)),Padding=new Thickness(16) };
}
