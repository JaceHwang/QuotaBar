using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using QuotaBar.Windows;

internal static class TactileButtonNativeTests {
    static void Check(bool condition,string message) { if(!condition) throw new InvalidOperationException(message); }
    static bool ContainsAccessText(DependencyObject element) {
        if(element is AccessText) return true;
        for(var i=0;i<VisualTreeHelper.GetChildrenCount(element);i++) if(ContainsAccessText(VisualTreeHelper.GetChild(element,i))) return true;
        return false;
    }
    static bool ContainsRenderedText(DependencyObject element,string text) {
        if(element is TextBlock label && label.Text==text) return true;
        for(var i=0;i<VisualTreeHelper.GetChildrenCount(element);i++) if(ContainsRenderedText(VisualTreeHelper.GetChild(element,i),text)) return true;
        return false;
    }
    static void WaitForAnimations() {
        var frame=new DispatcherFrame();
        var timer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(300) };
        timer.Tick+=(_,_)=> { timer.Stop(); frame.Continue=false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
    public static void Run() {
        if(SystemParameters.HighContrast) return;
        foreach(var variant in new[]{SettingsVisual.ButtonVariant.Primary,SettingsVisual.ButtonVariant.Secondary,SettingsVisual.ButtonVariant.Tertiary,SettingsVisual.ButtonVariant.Ghost,SettingsVisual.ButtonVariant.Text}) {
            var button=new Button { Content="Action",Width=160,Height=40 };
            SettingsVisual.ApplyVariant(button,variant,false);
            var window=new Window { Width=240,Height=120,Content=button,ShowInTaskbar=false,WindowStyle=WindowStyle.None,WindowStartupLocation=WindowStartupLocation.Manual,Left=-30000,Top=-30000 };
            try {
                window.Show(); button.ApplyTemplate(); window.UpdateLayout();
                Check(VisualStateManager.GoToState(button,"Normal",true),$"{variant}: normal state exists"); WaitForAnimations();
                var frame=(Border)button.Template.FindName("frame",button);
                if(variant is SettingsVisual.ButtonVariant.Primary or SettingsVisual.ButtonVariant.Secondary or SettingsVisual.ButtonVariant.Tertiary) {
                    var lift=(Border)button.Template.FindName("lift",button);
                    Check(Math.Abs(lift.Margin.Left-3)<0.01,$"{variant}: resting lift shadow has negative spread");
                }
                Check(VisualStateManager.GoToState(button,"Pressed",true),$"{variant}: pressed state exists"); WaitForAnimations();
                var translate=(TranslateTransform)frame.RenderTransform;
                Check(Math.Abs(translate.Y-1)<0.01,$"{variant}: pressed button moves down");
                if(variant is SettingsVisual.ButtonVariant.Primary or SettingsVisual.ButtonVariant.Secondary or SettingsVisual.ButtonVariant.Tertiary) {
                    var face=(LinearGradientBrush)frame.Background;
                    Check(face.GradientStops[0].Color.R<face.GradientStops[1].Color.R,$"{variant}: pressed gradient reverses");
                    var inset=(Border)button.Template.FindName("pressedInset",button);
                    Check(inset.Opacity>0.95,$"{variant}: pressed inner shade appears");
                    var contact=(Border)button.Template.FindName("contact",button);
                    var shadow=(System.Windows.Media.Effects.DropShadowEffect)contact.Effect;
                    Check(shadow.BlurRadius<=1.01,$"{variant}: contact shadow collapses");
                } else if(variant==SettingsVisual.ButtonVariant.Ghost) {
                    var inset=(Border)button.Template.FindName("pressedInset",button);
                    Check(inset.Opacity>0.95,"ghost button is recessed when pressed");
                }
                Check(VisualStateManager.GoToState(button,"MouseOver",true),$"{variant}: hover state exists"); WaitForAnimations();
                Check(Math.Abs(((TranslateTransform)frame.RenderTransform).Y)<0.01,$"{variant}: hover releases press offset");
                if(variant is SettingsVisual.ButtonVariant.Primary or SettingsVisual.ButtonVariant.Secondary or SettingsVisual.ButtonVariant.Tertiary) {
                    var lift=(Border)button.Template.FindName("lift",button);
                    Check(Math.Abs(lift.Margin.Left-5)<0.01,$"{variant}: hover lift shadow grows with negative spread");
                }
                if(variant==SettingsVisual.ButtonVariant.Text) {
                    var arrow=(TextBlock)button.Template.FindName("arrow",button);
                    Check(((TranslateTransform)arrow.RenderTransform).X>1.9,"text arrow nudges on hover");
                }
                Check(VisualStateManager.GoToState(button,"Normal",true),$"{variant}: normal state restores"); WaitForAnimations();
                if(variant==SettingsVisual.ButtonVariant.Ghost) Check(((SolidColorBrush)frame.Background).Color.A==0,"ghost face is transparent at rest");
                SettingsVisual.ApplySize(button,SettingsVisual.ButtonSize.Lg); window.UpdateLayout();
                var scale=(ScaleTransform)button.LayoutTransform;
                Check(Math.Abs(scale.ScaleX-16.0/14.0)<0.001 && Math.Abs(scale.ScaleY-16.0/14.0)<0.001,$"{variant}: large size scales the material");
                if(variant==SettingsVisual.ButtonVariant.Text) {
                    button.Content="_Action"; window.UpdateLayout();
                    var presenter=(ContentPresenter)button.Template.FindName("label",button);
                    Check(presenter.RecognizesAccessKey && ContainsAccessText(presenter),"text variant realizes access-key content");
                    var clicks=0; button.Click+=(_,_)=>clicks++;
                    var source=PresentationSource.FromVisual(button)!;
                    Check(AccessKeyManager.IsKeyRegistered(source,"A"),"text access key is registered");
                    AccessKeyManager.ProcessKey(source,"A",false);
                    Check(clicks==1,"text access key invokes the button");
                    var custom=new TextBlock { Text="Custom content" }; button.Content=custom; window.UpdateLayout();
                    Check(ReferenceEquals(presenter.Content,custom),"text variant retains custom content");
                    var contentTemplate=(DataTemplate)System.Windows.Markup.XamlReader.Parse("<DataTemplate xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><TextBlock Text=\"Templated view\"/></DataTemplate>");
                    button.Content="Templated"; button.ContentTemplate=contentTemplate; window.UpdateLayout();
                    Check(ReferenceEquals(presenter.ContentTemplate,contentTemplate) && ContainsRenderedText(presenter,"Templated view"),"text variant renders a caller-supplied content template");
                }
                button.IsEnabled=false; window.UpdateLayout();
                Check(button.Opacity<1,$"{variant}: disabled state remains visible");
            } finally { window.Close(); }
        }
    }
}
