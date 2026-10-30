using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using QuotaBar.Core;
using QuotaBar.Windows;
internal static class FloatingControlsTests {
 static void Check(bool v,string s) { if(!v) throw new Exception("floating controls: "+s); }
 static IEnumerable<DependencyObject> Tree(DependencyObject v) { yield return v;foreach(var c in LogicalTreeHelper.GetChildren(v).OfType<DependencyObject>()) foreach(var d in Tree(c)) yield return d; }
 static void Pump()=>Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle);
 public static void Run(Application app) {
  var state=new RefreshState();state.Received(DateTimeOffset.Now);var prefs=new Preferences { FloatingX=140,FloatingY=140 };var copy=new Copy("en");var floating=new FloatingWindow();
  try {
   foreach(var dark in new[]{false,true}) foreach(var value in new[]{0d,20d,100d}) {
    floating.Render(null,state,prefs with { FloatingBackgroundTransparency=value },copy,dark);Pump();
    var color=((SolidColorBrush)((Border)floating.Content).Background).Color;
    Check(color.R==(dark?0:255)&&color.G==color.R&&color.B==color.R&&Math.Abs(color.A-255*(1-value/100))<1,"pure theme background alpha");
   }
   floating.Render(null,state,prefs,copy,false);Pump();
   var events=new List<string>();var saved=new Point(140,140);var clicks=0;
   floating.Primary+=()=>clicks++;
   floating.PositionChanged+=p=> { events.Add("position");saved=p;prefs=prefs with { FloatingX=p.X,FloatingY=p.Y }; };
   floating.DragFinished+=()=> { events.Add("finished");floating.Render(null,state,prefs,copy,false); };
   floating.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,0,MouseButton.Left) { RoutedEvent=Mouse.MouseDownEvent });
   Check(floating.IsMouseCaptured,"drag input captures mouse");
   // Exercise real WPF ReleaseMouseCapture/LostMouseCapture reentrancy after a drag.
   typeof(FloatingWindow).GetField("dragging",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(floating,true);
   Platform.Place(floating,new Point(260,240));var expected=Platform.Bounds(floating).Location;
   floating.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,0,MouseButton.Left) { RoutedEvent=Mouse.MouseUpEvent });Pump();
   Check(events.SequenceEqual(new[]{"position","finished"}),"save final position before capture-loss finish, exactly once: "+string.Join(",",events));
   Check((saved-expected).Length<2&&(Platform.Bounds(floating).Location-expected).Length<2&&clicks==0,"release/refresh preserves new position without primary click");
   events.Clear();floating.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,0,MouseButton.Left) { RoutedEvent=Mouse.MouseDownEvent });
   typeof(FloatingWindow).GetField("dragging",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(floating,true);
   Platform.Place(floating,new Point(340,270));expected=Platform.Bounds(floating).Location;floating.ReleaseMouseCapture();Pump();
   Check(events.SequenceEqual(new[]{"position","finished"})&&(saved-expected).Length<2&&clicks==0,"unexpected capture loss persists position without click");
   events.Clear();floating.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,0,MouseButton.Left) { RoutedEvent=Mouse.MouseDownEvent });floating.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,0,MouseButton.Left) { RoutedEvent=Mouse.MouseUpEvent });
   Check(events.Count==0&&clicks==1,"ordinary click stays separate from dragging");
  } finally { floating.Close(); }
  var root=Path.Combine(Path.GetTempPath(),"floating-settings-"+Guid.NewGuid());
  using(var owner=new Coordinator(app,root)) {
   var settings=new SettingsWindow(owner);try {
    settings.Show();Pump();
    var slider=Tree(settings).OfType<Slider>().Single(s=>Equals(s.Tag,"settings.floatingTransparency"));
    Check(slider.Minimum==0&&slider.Maximum==100,"slider range");slider.Value=65;Pump();
    Check(owner.Preferences.FloatingBackgroundTransparency==65&&new PreferencesStore(Path.Combine(root,"preferences.json")).Load().FloatingBackgroundTransparency==65,"slider saves live");
    Check(Tree(settings).OfType<TextBlock>().Any(t=>Equals(t.Tag,"settings.floatingTransparency.value")&&t.Text=="65%"),"percentage label updates");
    Check(ReferenceEquals(slider,Tree(settings).OfType<Slider>().Single(s=>Equals(s.Tag,"settings.floatingTransparency"))),"dragging slider never rebuilds focused control");
   } finally { settings.Close(); }
  }
  Directory.Delete(root,true);Console.WriteLine("PASS floating background alpha, live slider persistence and drag capture release ordering");
 }
}
