namespace QuotaBar.Windows;
internal sealed class CharacterNotificationBubble : Window,IDisposable {
    bool disposed;
    public Action<string,string?>? ActionRequested,Acknowledged;
    public Action<bool>? InteractionChanged;
    public CharacterNotificationBubble() {
        Width=368; Height=180; WindowStyle=WindowStyle.None; AllowsTransparency=true; Background=Brushes.Transparent;
        ShowInTaskbar=false; ShowActivated=false; ResizeMode=ResizeMode.NoResize; Topmost=true; Platform.Passive(this);
        MouseEnter+=(_,_)=>InteractionChanged?.Invoke(true); MouseLeave+=(_,_)=>InteractionChanged?.Invoke(false);
    }
    public void Build(ExperienceNotification message,bool dark,Copy copy) {
        var fg=dark?Brushes.White:Ui.Foreground(false); var muted=dark?new SolidColorBrush(Color.FromRgb(205,207,216)):Brushes.DimGray;
        var canvas=new Canvas { Width=Width,Height=180 };
        var body=new StackPanel { Margin=new Thickness(14,10,14,12) };
        var card=new Border { Width=Width-48,Height=180,CornerRadius=new CornerRadius(16),Background=dark?new SolidColorBrush(Color.FromRgb(35,36,40)):Brushes.White,BorderBrush=dark?new SolidColorBrush(Color.FromRgb(65,66,70)):new SolidColorBrush(Color.FromRgb(227,228,232)),BorderThickness=new Thickness(1),Child=body };
        Canvas.SetLeft(card,48); canvas.Children.Add(card);
        var tail=new System.Windows.Shapes.Polygon { Points=new PointCollection([new(49,38),new(40,45),new(49,52)]),Fill=card.Background,IsHitTestVisible=false }; canvas.Children.Add(tail);
        var mascot=new QuotaMoodView { Width=40,Height=48,Mood=message.Kind is ExperienceNotificationKind.Recovery or ExperienceNotificationKind.Test?QuotaMood.Recovered:QuotaMood.Good,Dark=dark };
        Canvas.SetTop(mascot,26); canvas.Children.Add(mascot);
        if(message.Kind is ExperienceNotificationKind.Bank or ExperienceNotificationKind.Update) {
            var badge=new Border { Background=dark?Brushes.DimGray:Brushes.White,CornerRadius=new CornerRadius(10),Width=20,Height=20,Child=Ui.Text(message.Kind==ExperienceNotificationKind.Bank?"◷":"↑",14,fg),IsHitTestVisible=false };
            Canvas.SetLeft(badge,24); Canvas.SetTop(badge,56); canvas.Children.Add(badge);
        }
        var category=message.Kind switch {
            ExperienceNotificationKind.Recovery=>copy.Text("Quota recovery","额度恢复","額度恢復"), ExperienceNotificationKind.Bank=>copy.Text("Bank reminder","权益提醒","權益提醒"), ExperienceNotificationKind.Update=>copy.Text("Software update","软件更新","軟體更新"), _=>copy.Text("Example","示例","範例") };
        var tag=Ui.Text(category,10,dark?Brushes.Plum:Brushes.SaddleBrown); tag.Margin=new Thickness(0,0,0,6); body.Children.Add(tag);
        var title=Ui.Text(message.Title,14,fg); title.FontWeight=FontWeights.SemiBold; title.Height=34; title.TextWrapping=TextWrapping.Wrap; title.TextTrimming=TextTrimming.CharacterEllipsis; body.Children.Add(title);
        var text=Ui.Text(message.Body,12,muted); text.Height=60; text.Margin=new Thickness(0,6,0,10); text.TextWrapping=TextWrapping.Wrap; text.TextTrimming=TextTrimming.CharacterEllipsis; text.ToolTip=message.Body; body.Children.Add(text);
        var actions=new Grid(); actions.ColumnDefinitions.Add(new()); actions.ColumnDefinitions.Add(new());
        var label=message.Kind==ExperienceNotificationKind.Bank?copy.Text("View Bank","查看 Bank","查看 Bank"):message.Kind==ExperienceNotificationKind.Update?copy.Text("View update","查看更新","查看更新"):copy.Text("View details","查看详情","查看詳情");
        var primary=Ui.Button(label,()=>ActionRequested?.Invoke(message.Id,message.DeliveryToken)); primary.Height=28; primary.MinHeight=28; primary.FontSize=12; primary.Margin=new Thickness(0,0,8,0); primary.Padding=new Thickness(8,2,8,2); primary.Tag="notification.primary";
        var acknowledge=Ui.Button(copy.Text("Got it","知道了","知道了"),()=>Acknowledged?.Invoke(message.Id,message.DeliveryToken)); acknowledge.Height=28; acknowledge.MinHeight=28; acknowledge.FontSize=12; acknowledge.Margin=new Thickness(0); acknowledge.Padding=new Thickness(8,2,8,2); acknowledge.Tag="notification.acknowledge";
        Grid.SetColumn(acknowledge,1); actions.Children.Add(primary); actions.Children.Add(acknowledge); body.Children.Add(actions);
        SettingsVisual.ApplyButtons(canvas,dark); primary.Background=new SolidColorBrush(Color.FromRgb(46,59,76)); primary.Foreground=Brushes.White;
        System.Windows.Automation.AutomationProperties.SetName(this,message.Title+". "+message.Body); Content=canvas;
    }
    public bool ShowMessage(ExperienceNotification message,Rect anchor,bool dark,Copy copy,double scale=1) {
        // Platform.Bounds and WorkArea are physical pixels. Convert the completed placement once to DIPs.
        var work=Platform.WorkArea(anchor.Location);
        var width=Math.Min(368*scale,work.Width-16*scale); if(width<308*scale) return false;
        var rect=NotificationBubbleLayout.Place(new(anchor.X/scale,anchor.Y/scale,anchor.Width/scale,anchor.Height/scale),new(work.X/scale,work.Y/scale,work.Width/scale,work.Height/scale),width/scale,180);
        if(rect is not { } frame) return false;
        Width=frame.Width; Height=frame.Height; Build(message,dark,copy); Left=frame.X; Top=frame.Y; Opacity=0; Show(); Platform.Place(this,new(frame.X*scale,frame.Y*scale),false); if(SystemParameters.ClientAreaAnimation) BeginAnimation(OpacityProperty,new System.Windows.Media.Animation.DoubleAnimation(0,1,TimeSpan.FromMilliseconds(150))); else Opacity=1; return IsVisible;
    }
    public void Dismiss() { Hide(); InteractionChanged?.Invoke(false); }
    public void Dispose() { if(disposed) return; disposed=true; Close(); }
}
