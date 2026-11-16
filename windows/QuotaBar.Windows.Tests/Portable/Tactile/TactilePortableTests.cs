global using System.Windows.Controls;
using System.Xml.Linq;
using QuotaBar.Windows;

namespace System.Windows.Controls { internal sealed class ControlTemplate { public required XDocument Xml { get; init; } } }
namespace System.Windows.Markup { internal static class XamlReader { public static object Parse(string text) => new ControlTemplate { Xml=XDocument.Parse(text) }; } }
namespace QuotaBar.Windows { internal static class SettingsVisual { internal enum ButtonVariant { Primary, Secondary, Tertiary, Ghost, Text } } }

internal static class Program {
    static readonly XNamespace Presentation="http://schemas.microsoft.com/winfx/2006/xaml/presentation";
    static readonly XNamespace Xaml="http://schemas.microsoft.com/winfx/2006/xaml";
    static void Check(bool value,string message) { if(!value) throw new Exception(message); }
    static XElement State(ControlTemplate template,string name) => template.Xml.Descendants(Presentation+"VisualState").Single(x=>(string?)x.Attribute(Xaml+"Name")==name);
    static XElement Animation(XElement state,string target,string property) => state.Descendants().Single(x=>(string?)x.Attribute("Storyboard.TargetName")==target && ((string?)x.Attribute("Storyboard.TargetProperty"))?.Contains(property)==true);
    static string Attribute(XElement element,string name) => (string?)element.Attribute(name) ?? throw new Exception("Missing "+name);
    static void Expect(XElement state,string target,string property,string value,string duration) {
        var animation=Animation(state,target,property);
        Check(Attribute(animation,"To")==value,$"{target}.{property} target value");
        Check(Attribute(animation,"Duration")==duration,$"{target}.{property} duration");
    }
    static void Main() {
        foreach(var (variant,top,bottom,hoverTop,hoverBottom,inset) in new[]{
            (SettingsVisual.ButtonVariant.Primary,"#404859","#273042","#505868","#353D4D","#66000000"),
            (SettingsVisual.ButtonVariant.Secondary,"#FFFFFF","#F4F5F7","#FFFFFF","#FAFBFC","#24000000"),
            (SettingsVisual.ButtonVariant.Tertiary,"#F3F4F6","#E7E9EC","#FAFAFB","#EFF0F2","#24000000") }) {
            var template=TactileButtonVisuals.Filled(variant,true);
            var normal=State(template,"Normal"); var hover=State(template,"MouseOver"); var pressed=State(template,"Pressed"); State(template,"Disabled");
            Expect(normal,"frame","GradientStops)[0]",top,"0:0:0.16");
            Expect(normal,"frame","GradientStops)[1]",bottom,"0:0:0.16");
            Expect(hover,"frame","GradientStops)[0]",hoverTop,"0:0:0.16");
            Expect(hover,"frame","GradientStops)[1]",hoverBottom,"0:0:0.16");
            Expect(pressed,"frame","GradientStops)[0]",bottom,"0:0:0.16");
            Expect(pressed,"frame","GradientStops)[1]",top,"0:0:0.16");
            Expect(pressed,"frame","TranslateTransform.Y","1","0:0:0.12");
            Expect(normal,"lift","Margin","3","0:0:0.14");
            Expect(hover,"lift","Margin","5","0:0:0.14");
            Expect(hover,"lift","BlurRadius","16","0:0:0.14");
            Expect(hover,"lift","ShadowDepth","8","0:0:0.14");
            Expect(pressed,"contact","BlurRadius","1","0:0:0.14");
            Expect(pressed,"pressedInset","Opacity","1","0:0:0.14");
            Expect(pressed,"restInset","Opacity","0","0:0:0.14");
            var inner=template.Xml.Descendants(Presentation+"Border").Single(x=>(string?)x.Attribute(Xaml+"Name")=="pressedInset");
            Check(inner.Descendants(Presentation+"GradientStop").Any(x=>(string?)x.Attribute("Color")==inset),$"{variant}: pressed inset shade");
            var innerBrush=inner.Descendants(Presentation+"LinearGradientBrush").Single();
            Check((string?)innerBrush.Attribute("MappingMode")=="Absolute" && (string?)innerBrush.Attribute("EndPoint")=="0,2",$"{variant}: inset fades over two scaled units");
            var bottomLine=template.Xml.Descendants(Presentation+"Border").Single(x=>(string?)x.Attribute(Xaml+"Name")=="pressedBottom");
            Check((string?)bottomLine.Attribute("BorderBrush")== (variant==SettingsVisual.ButtonVariant.Primary?"#00FFFFFF":"#E6FFFFFF"),$"{variant}: pressed paper highlight");
            var still=TactileButtonVisuals.Filled(variant,false);
            Check(still.Xml.Descendants().Where(x=>x.Name.LocalName.EndsWith("Animation")).All(x=>Attribute(x,"Duration")=="0:0:0"),$"{variant}: reduced motion");
        }
        var darkFactory=typeof(TactileButtonVisuals).GetMethod("Filled",System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.NonPublic,null,[typeof(SettingsVisual.ButtonVariant),typeof(bool),typeof(bool)],null);
        Check(darkFactory!=null,"Filled variants must support a coordinated dark appearance");
        var darkSecondary=(ControlTemplate)darkFactory!.Invoke(null,[SettingsVisual.ButtonVariant.Secondary,true,true])!;
        Expect(State(darkSecondary,"Normal"),"frame","GradientStops)[0]","#4A4A4A","0:0:0.16");
        Expect(State(darkSecondary,"Normal"),"frame","GradientStops)[1]","#353535","0:0:0.16");
        var ghost=TactileButtonVisuals.Ghost(true);
        Expect(State(ghost,"Normal"),"frame","SolidColorBrush.Color","#00808080","0:0:0.16");
        Expect(State(ghost,"MouseOver"),"frame","SolidColorBrush.Color","#10808080","0:0:0.16");
        Expect(State(ghost,"Pressed"),"pressedInset","Opacity","1","0:0:0.14");
        var text=TactileButtonVisuals.Text(true);
        Expect(State(text,"MouseOver"),"arrow","TranslateTransform.X","2","0:0:0.12");
        foreach(var template in new[]{TactileButtonVisuals.Ghost(false),TactileButtonVisuals.Text(false)})
            Check(template.Xml.Descendants().Where(x=>x.Name.LocalName.EndsWith("Animation")).All(x=>Attribute(x,"Duration")=="0:0:0"),"reduced motion for ghost/text");
        Console.WriteLine("PASS: tactile button variants, states, timings and reduced motion");
    }
}
