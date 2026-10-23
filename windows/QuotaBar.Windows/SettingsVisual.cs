using System.Windows.Markup;
namespace QuotaBar.Windows;
internal static class SettingsVisual {
    static readonly ControlTemplate RoundedButtonTemplate=(ControlTemplate)XamlReader.Parse("""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
 <Border x:Name="frame" CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" RecognizesAccessKey="True"/></Border>
 <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="frame" Property="Opacity" Value="0.85"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="frame" Property="Opacity" Value="0.7"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="frame" Property="BorderBrush" Value="#4488DD"/><Setter TargetName="frame" Property="BorderThickness" Value="2"/></Trigger></ControlTemplate.Triggers>
</ControlTemplate>
""");
    public static void ApplyScrollbars(FrameworkElement root,bool dark) {
        var style=(Style)XamlReader.Parse("""
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ScrollBar">
 <Setter Property="Width" Value="8"/><Setter Property="Margin" Value="4,0,0,0"/>
 <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True">
 <Track.DecreaseRepeatButton><RepeatButton Command="{x:Static ScrollBar.PageUpCommand}" Focusable="False" Opacity="0"/></Track.DecreaseRepeatButton>
 <Track.Thumb><Thumb Background="{TemplateBinding Foreground}" MinHeight="24"><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="{TemplateBinding Background}" Width="6" HorizontalAlignment="Center" CornerRadius="3"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
 <Track.IncreaseRepeatButton><RepeatButton Command="{x:Static ScrollBar.PageDownCommand}" Focusable="False" Opacity="0"/></Track.IncreaseRepeatButton>
 </Track></ControlTemplate></Setter.Value></Setter>
</Style>
""");
        style.Setters.Add(new Setter(Control.ForegroundProperty,Muted(dark))); root.Resources[typeof(System.Windows.Controls.Primitives.ScrollBar)]=style;
    }
    public static void ApplyButtons(DependencyObject root,bool dark) {
        if(root is Button button) {
            button.Template=RoundedButtonTemplate; if(button.ReadLocalValue(Control.ForegroundProperty)==DependencyProperty.UnsetValue) button.Foreground=Ui.Foreground(dark);
            button.BorderBrush=new SolidColorBrush(Color.FromArgb(55,128,128,128));
            if(button.ReadLocalValue(Control.BorderThicknessProperty)==DependencyProperty.UnsetValue) button.BorderThickness=new Thickness(1);
            if(button.ReadLocalValue(Control.BackgroundProperty)==DependencyProperty.UnsetValue) button.Background=dark?new SolidColorBrush(Color.FromRgb(38,40,46)):Brushes.White;
        }
        foreach(var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) ApplyButtons(child,dark);
    }
    public static void Primary(Button button) { button.Background=new SolidColorBrush(Color.FromRgb(8,127,91)); button.Foreground=Brushes.White; }
    public static Brush Muted(bool dark)=>new SolidColorBrush(dark?Color.FromRgb(170,175,187):Color.FromRgb(110,116,130));
    public static Border Card(UIElement child,bool dark,Thickness? padding=null)=>new() { Child=child,Background=Ui.Surface(dark),BorderBrush=new SolidColorBrush(Color.FromArgb(40,128,128,128)),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(9),Padding=padding??new Thickness(16),Margin=new Thickness(0,0,0,10) };
    public static UIElement NavigationLabel(int index,string title,Brush foreground) {
        var geometries=new[]{"M 8,1 A 3,3 0 1 0 8,7 A 3,3 0 1 0 8,1 M 2,15 C 2,8 14,8 14,15 Z", "M 1,2 L 15,2 L 15,12 L 1,12 Z M 8,12 L 8,15 M 5,15 L 11,15", "M 8,1 A 7,7 0 1 0 8,15 A 7,7 0 1 0 8,1 M 5,6 L 5,7 M 11,6 L 11,7 M 4,10 Q 8,15 12,10", "M 4,1 L 12,1 L 12,15 L 4,15 Z M 7,12 L 9,12", "M 8,1 A 7,7 0 1 0 8,15 A 7,7 0 1 0 8,1 M 8,7 L 8,12 M 8,4 L 8,5"};
        var row=new StackPanel { Orientation=Orientation.Horizontal };
        row.Children.Add(new System.Windows.Shapes.Path { Data=Geometry.Parse(geometries[index]),Stroke=foreground,StrokeThickness=1.4,Width=18,Height=18,Stretch=Stretch.Uniform,Margin=new Thickness(0,0,10,0),VerticalAlignment=VerticalAlignment.Center });
        var label=Ui.Text(title,13,foreground); label.VerticalAlignment=VerticalAlignment.Center; row.Children.Add(label); return row;
    }
    public static UIElement Row(string title,UIElement control,bool dark,string? hint=null) {
        var grid=new Grid { Margin=new Thickness(0,10,0,10),MinHeight=28 };
        grid.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) }); grid.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
        var label=Ui.Text(title,13,Ui.Foreground(dark)); label.VerticalAlignment=VerticalAlignment.Center; label.Margin=new Thickness(0,0,16,0); label.TextWrapping=TextWrapping.Wrap; grid.Children.Add(label);
        Grid.SetColumn(control,1); grid.Children.Add(control); return grid;
    }
    public static UIElement Section(string title,UIElement content,bool dark) {
        var stack=new StackPanel { Margin=new Thickness(0,0,0,12) }; var label=Ui.Text(title,12,Muted(dark)); label.Margin=new Thickness(0,0,0,8); stack.Children.Add(label); stack.Children.Add(Card(content,dark)); return stack;
    }
    public static CheckBox Toggle(string title,bool value,Brush foreground,Action<bool> changed) {
        var box=new CheckBox { Content=title,IsChecked=value,Foreground=foreground,FontSize=13,FontWeight=FontWeights.Normal,VerticalContentAlignment=VerticalAlignment.Center,Margin=new Thickness(0,3,0,3) };
        box.Template=(ControlTemplate)XamlReader.Parse("""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="CheckBox">
 <Border x:Name="focus" BorderBrush="Transparent" BorderThickness="1" Padding="0,8" CornerRadius="4"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="{TemplateBinding Content}" TextWrapping="Wrap" VerticalAlignment="Center"/><Border Grid.Column="1" x:Name="track" Width="38" Height="22" CornerRadius="11" Background="#949BA5" Margin="16,0,0,0"><Ellipse x:Name="thumb" Width="18" Height="18" Margin="2" Fill="White" HorizontalAlignment="Left"/></Border></Grid></Border>
 <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="focus" Property="BorderBrush" Value="{DynamicResource {x:Static SystemColors.HighlightBrushKey}}"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="track" Property="Background" Value="#30BC58"/><Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers>
</ControlTemplate>
""");
        System.Windows.Automation.AutomationProperties.SetName(box,title); box.Checked+=(_,_)=>changed(true); box.Unchecked+=(_,_)=>changed(false); return box;
    }
}
internal sealed class SettingsIllustration : FrameworkElement {
    public bool Bank { get; init; }
    public bool Dark { get; init; }
    public SettingsIllustration() { Width=52; Height=52; IsHitTestVisible=false; }
    protected override void OnRender(DrawingContext dc) {
        var ink=Ui.Foreground(Dark); var pen=new Pen(ink,1.8); dc.PushTransform(new ScaleTransform(ActualWidth/52,ActualHeight/52));
        if(Bank) {
            var roof=Geometry.Parse("M 4,17 L 24,6 L 44,17 Z"); dc.DrawGeometry(null,pen,roof); dc.DrawLine(pen,new(5,21),new(43,21));
            foreach(var x in new[]{10,20,30,40}) dc.DrawLine(pen,new(x,23),new(x,39)); dc.DrawLine(pen,new(5,41),new(43,41)); dc.DrawLine(pen,new(3,45),new(35,45));
            dc.DrawEllipse(Ui.Surface(Dark),pen,new(39,38),11,11); dc.DrawLine(pen,new(39,38),new(39,31)); dc.DrawLine(pen,new(39,38),new(45,38));
        } else {
            dc.DrawGeometry(null,pen,Geometry.Parse("M 11,36 C 17,31 16,26 16,21 C 16,6 36,6 36,21 C 36,26 35,31 41,36 Z")); dc.DrawEllipse(null,pen,new(26,40),4,3);
            dc.DrawLine(pen,new(26,6),new(26,3)); foreach(var y in new[]{15,25}) { dc.DrawLine(pen,new(3,y),new(8,y+2)); dc.DrawLine(pen,new(44,y+2),new(49,y)); }
        } dc.Pop();
    }
}
