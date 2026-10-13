using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using QuotaBar.Core;
using QuotaBar.Windows;

internal static class Program {
    [STAThread]
    static int Main() {
        if(!OperatingSystem.IsWindows()) return 1;
        System.Windows.Forms.Application.SetHighDpiMode(System.Windows.Forms.HighDpiMode.PerMonitorV2);
        var app=new Application { ShutdownMode=ShutdownMode.OnExplicitShutdown };
        var quota=QuotaDecoder.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/rate-limits/read-response.json")));
        quota=quota with { Primary=quota.Primary with { ResetsAt=DateTimeOffset.Now.AddHours(5) },Secondary=quota.Secondary is { } second ? second with { ResetsAt=DateTimeOffset.Now.AddDays(4) } : null };
        var today=DateOnly.FromDateTime(DateTime.Now);
        var tokens=new TokenUsage([new(today.AddDays(-1),8000),new(today,10000)],18000,10000,3600,2,4);
        var state=new RefreshState(); state.Received(DateTimeOffset.Now);
        var prefs=new Preferences(); var copy=new Copy("zh-CN");
        var button=new FloatingWindow(); var detail=new DetailWindow();
        try {
            var clicks=0; var closes=0;
            button.Primary+=()=>clicks++;
            button.CloseRequested+=()=> { closes++; prefs=prefs with { FloatingEnabled=false }; button.Render(quota,state,prefs,copy,false); };
            button.Render(quota,state,prefs,copy,false); Pump();
            Check(button.IsVisible && button.CloseControl.Visibility==Visibility.Hidden,"initial floating close hidden");
            var width=button.Width;
            button.RaiseEvent(new MouseEventArgs(Mouse.PrimaryDevice,0) { RoutedEvent=Mouse.MouseEnterEvent });
            Check(button.CloseControl.Visibility==Visibility.Visible && button.Width==width,"hover close no layout jump");
            button.CloseControl.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
            Check(closes==1 && clicks==0 && !button.IsVisible && !prefs.FloatingEnabled,"close distinct from primary and hides");
            prefs=prefs with { FloatingEnabled=true }; button.Render(quota,state,prefs,copy,false); Pump();
            Check(button.IsVisible && button.CloseControl.Visibility==Visibility.Hidden,"restore floating hidden close");
            var output=Environment.GetEnvironmentVariable("QUOTABAR_TEST_ARTIFACTS")??Path.Combine(Path.GetTempPath(),"quotabar-ui-tests"); Directory.CreateDirectory(output);
            foreach(var dark in new[]{false,true}) {
                using(var icon=Coordinator.MakeTrayIcon()) using(var preview=icon.ToBitmap()) preview.Save(Path.Combine(output,"tray-"+(dark?"dark":"light")+".png"),System.Drawing.Imaging.ImageFormat.Png);
                detail.Render(quota,dark?tokens:null,new AccountIdentity("Example",null,null),state,prefs,copy,dark,false,Platform.Bounds(button)); Pump();
                var labels=Tree(detail.Content as DependencyObject ?? detail).OfType<TextBlock>().Select(v=>v.Text).ToArray();
                Check(!labels.Any(v=>v is "累计 Token" or "最高单日 Token" or "最长运行时长" or "当前连续天数" or "最长连续天数"),"detail does not expose auxiliary token statistic rows");
                Check(Tree(detail.Content as DependencyObject ?? detail).OfType<Button>().Any(v=>v.ToolTip?.ToString()=="Tibo 的 X 动态"),"Tibo remains accessible as a footer button");
                Check(!Tree(detail.Content as DependencyObject ?? detail).OfType<Button>().Any(v=>v.ToolTip?.ToString()=="关闭详情"),"detail header close removed");
                Check(detail.IsVisible && !Platform.Bounds(detail).IsEmpty,"native detail window visible");
                Console.WriteLine("PASS refreshed detail reparenting "+(dark?"dark":"light"));
                var root=(FrameworkElement)detail.Content; root.UpdateLayout();
                var bitmap=new RenderTargetBitmap((int)Math.Ceiling(detail.Width),(int)Math.Ceiling(detail.Height),96,96,PixelFormats.Pbgra32); bitmap.Render(root);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var file=File.Create(Path.Combine(output,"detail-"+(dark?"dark":"light")+".png")); encoder.Save(file);
            }
            Check(File.ReadAllBytes(Path.Combine(output,"tray-light.png")).SequenceEqual(File.ReadAllBytes(Path.Combine(output,"tray-dark.png"))),"same circular tray pixels across themes");
            // A short saved viewport must keep all content reachable and survive repeated refresh.
            foreach(var language in new[]{"en","zh-TW"}) {
                detail.Render(quota,tokens,new AccountIdentity("Example with a long account name",null,null),state,prefs with { DetailHeight=220 },new Copy(language),true,true,Platform.Bounds(button)); Pump();
                detail.Render(quota,tokens,new AccountIdentity("Example with a long account name",null,null),state,prefs with { DetailHeight=220 },new Copy(language),true,true,Platform.Bounds(button)); Pump();
                Check(detail.Content is Border { Child:ScrollViewer },"short detail viewport can scroll fixed bands");
            }
            Console.WriteLine("PASS Windows native floating visibility/hover/close/restore and light/dark detail rendering"); return 0;
        } catch(Exception e) { Console.Error.WriteLine("FAIL Windows UI: "+e); return 1; }
        finally { button.Close(); detail.Close(); app.Shutdown(); }
    }
    static void Pump() { var frame=new DispatcherFrame(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background,()=>frame.Continue=false); Dispatcher.PushFrame(frame); }
    static System.Collections.Generic.IEnumerable<DependencyObject> Tree(DependencyObject root) {
        yield return root;
        foreach(var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) foreach(var node in Tree(child)) yield return node;
    }
    static void Check(bool b,string message) { if(!b) throw new Exception(message); }
}
