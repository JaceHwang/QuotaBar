using System.Windows.Markup;

namespace QuotaBar.Windows;

/// <summary>WPF material layers and native visual states for the existing settings Button.</summary>
internal static class TactileButtonVisuals {
    readonly record struct Palette(string Top,string Bottom,string HoverTop,string HoverBottom,string Edge,string Highlight,string Shade,string Inset,string Contact,string Lift,string Paper);
    static Palette Colors(SettingsVisual.ButtonVariant variant,bool dark) => (variant,dark) switch {
        (SettingsVisual.ButtonVariant.Secondary,true) => new("#4A4A4A","#353535","#565656","#404040","#202020","#2EFFFFFF","#38000000","#66000000","0.18","0.28","#00FFFFFF"),
        (SettingsVisual.ButtonVariant.Tertiary,true) => new("#3B3B3B","#2C2C2C","#474747","#373737","#1C1C1C","#2EFFFFFF","#38000000","#66000000","0.18","0.28","#00FFFFFF"),
        (SettingsVisual.ButtonVariant.Primary,_) => new("#404859","#273042","#505868","#353D4D","#12161F","#2EFFFFFF","#38000000","#66000000","0.18","0.28","#00FFFFFF"),
        (SettingsVisual.ButtonVariant.Tertiary,_) => new("#F3F4F6","#E7E9EC","#FAFAFB","#EFF0F2","#1A0F172A","#E6FFFFFF","#0F000000","#24000000","0.06","0.09","#E6FFFFFF"),
        _ => new("#FFFFFF","#F4F5F7","#FFFFFF","#FAFBFC","#240F172A","#E6FFFFFF","#0F000000","#24000000","0.06","0.09","#E6FFFFFF")
    };
    static string Duration(bool animate,int milliseconds) => !animate ? "0:0:0" : milliseconds switch { 120 => "0:0:0.12", 140 => "0:0:0.14", _ => "0:0:0.16" };
    static string Animate(string type,string name,string property,string value,string duration) => $"<{type} Storyboard.TargetName=\"{name}\" Storyboard.TargetProperty=\"{property}\" To=\"{value}\" Duration=\"{duration}\"/>";
    static string State(string name,params string[] animations) => $"<VisualState x:Name=\"{name}\"><Storyboard>{string.Concat(animations)}</Storyboard></VisualState>";
    static string Group(params string[] states) => $"<VisualStateManager.VisualStateGroups><VisualStateGroup x:Name=\"CommonStates\">{string.Concat(states)}</VisualStateGroup></VisualStateManager.VisualStateGroups>";
    const string TranslateY="(UIElement.RenderTransform).(TranslateTransform.Y)";
    const string TranslateX="(UIElement.RenderTransform).(TranslateTransform.X)";
    const string GradientTop="(Border.Background).(GradientBrush.GradientStops)[0].(GradientStop.Color)";
    const string GradientBottom="(Border.Background).(GradientBrush.GradientStops)[1].(GradientStop.Color)";
    const string BrushColor="(Border.Background).(SolidColorBrush.Color)";
    const string Blur="(UIElement.Effect).(DropShadowEffect.BlurRadius)";
    const string Depth="(UIElement.Effect).(DropShadowEffect.ShadowDepth)";
    const string ShadowOpacity="(UIElement.Effect).(DropShadowEffect.Opacity)";

    static string FilledState(string name,Palette p,bool hover,bool pressed,bool animate) {
        var top=pressed?p.Bottom:hover?p.HoverTop:p.Top;
        var bottom=pressed?p.Top:hover?p.HoverBottom:p.Bottom;
        var move=Duration(animate,120); var shadow=Duration(animate,140); var color=Duration(animate,160);
        return State(name,
            Animate("ColorAnimation","frame",GradientTop,top,color),
            Animate("ColorAnimation","frame",GradientBottom,bottom,color),
            Animate("DoubleAnimation","frame",TranslateY,pressed?"1":"0",move),
            Animate("ThicknessAnimation","lift","Margin",hover?"5":"3",shadow),
            Animate("DoubleAnimation","lift",Blur,hover?"16":"10",shadow),
            Animate("DoubleAnimation","lift",Depth,hover?"8":"4",shadow),
            Animate("DoubleAnimation","lift",ShadowOpacity,pressed?"0":p.Lift,shadow),
            Animate("DoubleAnimation","contact",Blur,pressed?"1":"2",shadow),
            Animate("DoubleAnimation","pressedInset","Opacity",pressed?"1":"0",shadow),
            Animate("DoubleAnimation","pressedBottom","Opacity",pressed?"1":"0",shadow),
            Animate("DoubleAnimation","restInset","Opacity",pressed?"0":"1",shadow));
    }
    static string FilledStates(Palette p,bool animate) => Group(FilledState("Normal",p,false,false,animate),FilledState("MouseOver",p,true,false,animate),FilledState("Pressed",p,false,true,animate),FilledState("Disabled",p,false,false,animate));

    internal static ControlTemplate Filled(SettingsVisual.ButtonVariant variant,bool animate) => Filled(variant,animate,false);
    internal static ControlTemplate Filled(SettingsVisual.ButtonVariant variant,bool animate,bool dark) {
        var p=Colors(variant,dark);
        var markup="""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
 <Grid>
  @STATES@
  <Border x:Name="lift" Margin="3" CornerRadius="7" Background="#FF000000" IsHitTestVisible="False"><Border.Effect><DropShadowEffect Color="#000000" BlurRadius="10" ShadowDepth="4" Direction="270" Opacity="@LIFT@"/></Border.Effect></Border>
  <Border x:Name="contact"><Border.Effect><DropShadowEffect Color="#000000" BlurRadius="2" ShadowDepth="1" Direction="270" Opacity="@CONTACT@"/></Border.Effect>
   <Border x:Name="frame" CornerRadius="10" BorderThickness="1" BorderBrush="@EDGE@">
    <Border.RenderTransform><TranslateTransform/></Border.RenderTransform>
    <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="@TOP@" Offset="0"/><GradientStop Color="@BOTTOM@" Offset="1"/></LinearGradientBrush></Border.Background>
    <Grid>
     <Border x:Name="restInset" CornerRadius="9" BorderThickness="0,1,0,1" IsHitTestVisible="False"><Border.BorderBrush><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="@HIGHLIGHT@" Offset="0"/><GradientStop Color="@SHADE@" Offset="1"/></LinearGradientBrush></Border.BorderBrush></Border>
     <Border x:Name="pressedInset" CornerRadius="9" BorderThickness="0,2,0,0" Opacity="0" IsHitTestVisible="False"><Border.BorderBrush><LinearGradientBrush MappingMode="Absolute" StartPoint="0,0" EndPoint="0,2"><GradientStop Color="@INSET@" Offset="0"/><GradientStop Color="#00000000" Offset="1"/></LinearGradientBrush></Border.BorderBrush></Border>
     <Border x:Name="pressedBottom" CornerRadius="9" BorderThickness="0,0,0,1" BorderBrush="@PAPER@" Margin="0,0,0,-1" Opacity="0" IsHitTestVisible="False"/>
     <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" RecognizesAccessKey="True">@LABEL_EFFECT@</ContentPresenter>
    </Grid>
   </Border>
  </Border>
  <Border x:Name="focus" CornerRadius="10" BorderThickness="2" BorderBrush="Transparent" IsHitTestVisible="False"/>
 </Grid>
 <ControlTemplate.Triggers>
  <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.55"/></Trigger>
  <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="focus" Property="BorderBrush" Value="{DynamicResource {x:Static SystemColors.HighlightBrushKey}}"/></Trigger>
 </ControlTemplate.Triggers>
</ControlTemplate>
""";
        markup=markup.Replace("@STATES@",FilledStates(p,animate)).Replace("@CONTACT@",p.Contact).Replace("@EDGE@",p.Edge).Replace("@TOP@",p.Top).Replace("@BOTTOM@",p.Bottom).Replace("@LIFT@",p.Lift).Replace("@HIGHLIGHT@",p.Highlight).Replace("@SHADE@",p.Shade).Replace("@INSET@",p.Inset).Replace("@PAPER@",p.Paper).Replace("@LABEL_EFFECT@",variant==SettingsVisual.ButtonVariant.Primary?"<ContentPresenter.Effect><DropShadowEffect Color=\"#000000\" BlurRadius=\"0\" ShadowDepth=\"1\" Direction=\"90\" Opacity=\"0.28\"/></ContentPresenter.Effect>":"");
        return (ControlTemplate)XamlReader.Parse(markup);
    }
    static string GhostState(string name,bool hover,bool pressed,bool animate) => State(name,
        Animate("ColorAnimation","frame",BrushColor,pressed?"#26808080":hover?"#10808080":"#00808080",Duration(animate,160)),
        Animate("DoubleAnimation","frame",TranslateY,pressed?"1":"0",Duration(animate,120)),
        Animate("DoubleAnimation","pressedInset","Opacity",pressed?"1":"0",Duration(animate,140)));
    internal static ControlTemplate Ghost(bool animate) {
        var markup="""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button"><Grid>
 @STATES@
 <Border x:Name="frame" CornerRadius="10" BorderThickness="1" BorderBrush="Transparent"><Border.RenderTransform><TranslateTransform/></Border.RenderTransform><Border.Background><SolidColorBrush Color="#00808080"/></Border.Background><Grid>
  <Border x:Name="pressedInset" CornerRadius="9" BorderThickness="0,2,0,0" Opacity="0" IsHitTestVisible="False"><Border.BorderBrush><LinearGradientBrush MappingMode="Absolute" StartPoint="0,0" EndPoint="0,2"><GradientStop Color="#24000000" Offset="0"/><GradientStop Color="#00000000" Offset="1"/></LinearGradientBrush></Border.BorderBrush></Border>
  <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" RecognizesAccessKey="True"/>
 </Grid></Border><Border x:Name="focus" CornerRadius="10" BorderThickness="2" BorderBrush="Transparent" IsHitTestVisible="False"/>
 </Grid><ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.55"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="focus" Property="BorderBrush" Value="{DynamicResource {x:Static SystemColors.HighlightBrushKey}}"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
""";
        return (ControlTemplate)XamlReader.Parse(markup.Replace("@STATES@",Group(GhostState("Normal",false,false,animate),GhostState("MouseOver",true,false,animate),GhostState("Pressed",false,true,animate),GhostState("Disabled",false,false,animate))));
    }
    static string TextState(string name,bool hover,bool pressed,bool animate) => State(name,
        Animate("DoubleAnimation","frame",TranslateY,pressed?"1":"0",Duration(animate,120)),
        Animate("DoubleAnimation","arrow",TranslateX,hover?"2":"0",Duration(animate,120)));
    internal static ControlTemplate Text(bool animate) {
        var markup="""
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button"><Grid>
 @STATES@
 <Border x:Name="frame" Background="Transparent" CornerRadius="10" BorderThickness="1" BorderBrush="Transparent" Padding="{TemplateBinding Padding}"><Border.RenderTransform><TranslateTransform/></Border.RenderTransform><StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center"><Border BorderBrush="{TemplateBinding Foreground}" BorderThickness="0,0,0,1"><ContentPresenter x:Name="label" ContentSource="Content" RecognizesAccessKey="True"/></Border><TextBlock x:Name="arrow" Text=" →" Foreground="{TemplateBinding Foreground}"><TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform></TextBlock></StackPanel></Border>
 <Border x:Name="focus" CornerRadius="10" BorderThickness="2" BorderBrush="Transparent" IsHitTestVisible="False"/>
 </Grid><ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.55"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="focus" Property="BorderBrush" Value="{DynamicResource {x:Static SystemColors.HighlightBrushKey}}"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
""";
        return (ControlTemplate)XamlReader.Parse(markup.Replace("@STATES@",Group(TextState("Normal",false,false,animate),TextState("MouseOver",true,false,animate),TextState("Pressed",false,true,animate),TextState("Disabled",false,false,animate))));
    }
}
