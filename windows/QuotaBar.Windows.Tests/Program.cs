using System;
using System.IO;
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
                detail.Render(quota,null,new AccountIdentity("Example",null,null),state,prefs,copy,dark,false,Platform.Bounds(button)); Pump();
                Check(detail.IsVisible && !Platform.Bounds(detail).IsEmpty,"native detail window visible");
                var root=(FrameworkElement)detail.Content; root.UpdateLayout();
                var bitmap=new RenderTargetBitmap((int)Math.Ceiling(detail.Width),(int)Math.Ceiling(detail.Height),96,96,PixelFormats.Pbgra32); bitmap.Render(root);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var file=File.Create(Path.Combine(output,"detail-"+(dark?"dark":"light")+".png")); encoder.Save(file);
            }
            Console.WriteLine("PASS Windows native floating visibility/hover/close/restore and light/dark detail rendering"); return 0;
        } catch(Exception e) { Console.Error.WriteLine("FAIL Windows UI: "+e.Message); return 1; }
        finally { button.Close(); detail.Close(); app.Shutdown(); }
    }
    static void Pump() { var frame=new DispatcherFrame(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background,()=>frame.Continue=false); Dispatcher.PushFrame(frame); }
    static void Check(bool b,string message) { if(!b) throw new Exception(message); }
}
