using System.Windows.Media.Imaging;
using System.Windows.Markup;
namespace QuotaBar.Windows;
internal enum NotificationCharacterArtwork { Recovery, Bank, Neutral, Attention }
internal sealed class CharacterNotificationBubble : Window,IDisposable {
    internal const double DefaultWidth=420, MinimumWidth=340, CardLeft=112, ContentHeight=142;
    bool disposed;
    public Action<string,string?>? ActionRequested,Acknowledged;
    public Action<bool>? InteractionChanged;
    public CharacterNotificationBubble() {
        Width=DefaultWidth; Height=ContentHeight; WindowStyle=WindowStyle.None; AllowsTransparency=true; Background=Brushes.Transparent;
        ShowInTaskbar=false; ShowActivated=false; ResizeMode=ResizeMode.NoResize; Topmost=true; Platform.Passive(this);
        MouseEnter+=(_,_)=>InteractionChanged?.Invoke(true); MouseLeave+=(_,_)=>InteractionChanged?.Invoke(false);
    }
    static Brush ColorBrush(string color)=>(Brush)new BrushConverter().ConvertFromString(color)!;
    static double TextHeight(TextBlock text,double width,int maxLines) {
        var metrics=new FormattedText(text.Text,System.Globalization.CultureInfo.CurrentUICulture,FlowDirection.LeftToRight,new Typeface(text.FontFamily,text.FontStyle,text.FontWeight,text.FontStretch),text.FontSize,text.Foreground,1) { MaxTextWidth=width };
        var rows=new FormattedText(string.Join("\n",Enumerable.Repeat("Ag",maxLines)),System.Globalization.CultureInfo.CurrentUICulture,FlowDirection.LeftToRight,new Typeface(text.FontFamily,text.FontStyle,text.FontWeight,text.FontStretch),text.FontSize,text.Foreground,1);
        return Math.Ceiling(Math.Min(metrics.Height,rows.Height));
    }
    public void Build(ExperienceNotification message,bool dark,Copy copy,NotificationCharacterArtwork? artwork=null) {
        var fg=ColorBrush(dark?"#F5F6FF":"#10182F"); var muted=ColorBrush(dark?"#C2CBE0":"#596987");
        var innerWidth=Width-CardLeft-40;
        var title=Ui.Text(message.Title,17,fg); title.FontWeight=FontWeights.SemiBold; title.TextWrapping=TextWrapping.Wrap; title.TextTrimming=TextTrimming.CharacterEllipsis; title.ToolTip=message.Title;
        title.Height=Math.Max(24,TextHeight(title,innerWidth,2));
        var displayBody=message.Body;
        if(message.Kind is ExperienceNotificationKind.Recovery or ExperienceNotificationKind.Test) displayBody=displayBody.Replace("额度剩余","剩余").Replace("額度剩餘","剩餘").Replace("；"," · ");
        var text=Ui.Text(displayBody,13,muted); text.TextWrapping=TextWrapping.Wrap; text.TextTrimming=TextTrimming.CharacterEllipsis; text.ToolTip=message.Body;
        text.Height=Math.Max(18,TextHeight(text,innerWidth,4));
        System.Windows.Automation.AutomationProperties.SetName(text,message.Body);
        var bodyY=42+title.Height+2; var actionY=bodyY+text.Height+12;
        Height=Math.Max(ContentHeight,actionY+32+12);
        var canvas=new Canvas { Width=Width,Height=Height };
        var card=new Border { Width=Width-CardLeft,Height=Height,CornerRadius=new CornerRadius(20),Background=ColorBrush(dark?"#252936":"#FEFEFF"),BorderBrush=ColorBrush(dark?"#424958":"#F0F2F7"),BorderThickness=new Thickness(1) };
        Canvas.SetLeft(card,CardLeft); canvas.Children.Add(card);
        var tailY=Height*.54;
        canvas.Children.Add(new System.Windows.Shapes.Polygon { Points=new PointCollection([new(CardLeft+1,tailY-10),new(CardLeft-12,tailY),new(CardLeft+1,tailY+10)]),Fill=card.Background,IsHitTestVisible=false });
        var art=artwork?.ToString().ToLowerInvariant() ?? (message.Kind switch { ExperienceNotificationKind.Bank=>"bank",ExperienceNotificationKind.Update=>"neutral",_=>"recovery" });
        // Crop source-canvas whitespace only; preserve the shared original artwork bytes.
        var source=new BitmapImage(new Uri($"pack://application:,,,/QuotaBar;component/Assets/NotificationCharacters/{art}.png"));
        var crop=art switch { "attention"=>new Int32Rect(159,172,906,970), "bank"=>new Int32Rect(78,169,1040,980), "neutral"=>new Int32Rect(272,235,710,890), _=>new Int32Rect(256,135,957,882) };
        var mascot=new System.Windows.Controls.Image { Width=104,Height=116,Stretch=Stretch.Uniform,IsHitTestVisible=false,Source=new CroppedBitmap(source,crop) };
        Canvas.SetTop(mascot,Height-116); canvas.Children.Add(mascot);
        var category=artwork==NotificationCharacterArtwork.Attention?copy.Text("Quota reminder","额度提醒","額度提醒"):message.Kind switch {
            ExperienceNotificationKind.Bank=>copy.Text("Bank reminder","权益提醒","權益提醒"), ExperienceNotificationKind.Update=>copy.Text("Software update","软件更新","軟體更新"), _=>copy.Text("Quota update","额度更新","額度更新") };
        var amber=message.Kind==ExperienceNotificationKind.Bank || artwork==NotificationCharacterArtwork.Attention;
        var tagText=Ui.Text(category,10,ColorBrush(amber?(dark?"#FFD6A1":"#93602D"):(dark?"#DDD0FF":"#6751A5"))); tagText.FontWeight=FontWeights.SemiBold; tagText.VerticalAlignment=VerticalAlignment.Center;
        var tag=new Border { Height=22,CornerRadius=new CornerRadius(11),Background=ColorBrush(amber?(dark?"#58412D":"#FFF0DC"):(dark?"#493E68":"#EAE2FF")),Padding=new Thickness(12,0,12,0),Child=tagText };
        Canvas.SetLeft(tag,CardLeft+20); Canvas.SetTop(tag,12); canvas.Children.Add(tag);
        void Place(FrameworkElement element,double y) { element.Width=innerWidth; Canvas.SetLeft(element,CardLeft+20); Canvas.SetTop(element,y); canvas.Children.Add(element); }
        Place(title,42); Place(text,bodyY);
        var actions=new Grid { Height=32 }; actions.ColumnDefinitions.Add(new() { Width=new GridLength(1.2,GridUnitType.Star) }); actions.ColumnDefinitions.Add(new() { Width=new GridLength(14) }); actions.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) });
        var label=message.Kind==ExperienceNotificationKind.Bank?copy.Text("View Bank","查看 Bank","查看 Bank"):message.Kind==ExperienceNotificationKind.Update?copy.Text("Update now","立即更新","立即更新"):copy.Text("View details","查看详情","查看詳情");
        var primary=Ui.Button(label,()=>ActionRequested?.Invoke(message.Id,message.DeliveryToken)); primary.Tag="notification.primary";
        var acknowledge=Ui.Button(copy.Text("Got it","知道了","知道了"),()=>Acknowledged?.Invoke(message.Id,message.DeliveryToken)); acknowledge.Tag="notification.acknowledge";
        foreach(var button in new[]{primary,acknowledge}) {
            button.Height=32; button.MinHeight=32; button.FontSize=12; button.FontWeight=FontWeights.SemiBold; button.Margin=new Thickness(0); button.Padding=new Thickness(4,0,4,0);
            button.Template=(ControlTemplate)XamlReader.Parse("""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button"><Border x:Name="frame" CornerRadius="10" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="frame" Property="Opacity" Value="0.85"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="frame" Property="Opacity" Value="0.7"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="frame" Property="BorderBrush" Value="#4488DD"/><Setter TargetName="frame" Property="BorderThickness" Value="2"/><Setter TargetName="frame" Property="Padding" Value="2,0,2,0"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
""");
        }
        primary.Background=new LinearGradientBrush(Color.FromRgb(52,65,83),Color.FromRgb(39,50,65),90); primary.Foreground=Brushes.White; primary.BorderThickness=new Thickness(0);
        acknowledge.Background=ColorBrush(dark?"#353D4D":"#F4F6FA"); acknowledge.Foreground=muted; acknowledge.BorderBrush=ColorBrush(dark?"#505B71":"#E3E8F1"); acknowledge.BorderThickness=new Thickness(1);
        Grid.SetColumn(acknowledge,2); actions.Children.Add(primary); actions.Children.Add(acknowledge); Place(actions,actionY);
        System.Windows.Automation.AutomationProperties.SetName(this,message.Title+". "+message.Body); Content=canvas;
    }
    public bool ShowMessage(ExperienceNotification message,Rect anchor,bool dark,Copy copy,double scale=1) {
        // Platform.Bounds and WorkArea are physical pixels. Convert placement once to DIPs.
        var work=Platform.WorkArea(anchor.Location);
        var width=Math.Min(DefaultWidth*scale,work.Width-16*scale); if(width<MinimumWidth*scale) return false;
        Width=width/scale; Build(message,dark,copy);
        var rect=NotificationBubbleLayout.Place(new(anchor.X/scale,anchor.Y/scale,anchor.Width/scale,anchor.Height/scale),new(work.X/scale,work.Y/scale,work.Width/scale,work.Height/scale),Width,Height);
        if(rect is not { } frame) return false;
        Left=frame.X; Top=frame.Y; Opacity=0; Show(); Platform.Place(this,new(frame.X*scale,frame.Y*scale),false); if(SystemParameters.ClientAreaAnimation) BeginAnimation(OpacityProperty,new System.Windows.Media.Animation.DoubleAnimation(0,1,TimeSpan.FromMilliseconds(150))); else Opacity=1; return IsVisible;
    }
    public void Dismiss() { Hide(); InteractionChanged?.Invoke(false); }
    public void Dispose() { if(disposed) return; disposed=true; Close(); }
}
