using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
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
            var updateRoot=Path.Combine(Path.GetTempPath(),"quotabar-update-ui-"+Guid.NewGuid());
            using(var owner=new Coordinator(app,updateRoot,new HttpClient(new InterruptedFeedHandler()))) {
                owner.Updates.Check(true);
                var deadline=DateTime.UtcNow.AddSeconds(5);
                while(owner.Updates.Checking && DateTime.UtcNow<deadline) Pump();
                Check(!owner.Updates.Checking && owner.Updates.Status==owner.Copy.Text("Could not check. Try again later.","检查失败，请稍后重试。","檢查失敗，請稍後重試。"),"interrupted update stream is a recoverable check failure");
                foreach(var dark in new[]{false,true}) {
                    owner.Save(new Preferences { Theme=dark?"dark":"light",Language="zh-CN",AutomaticUpdates=false },false);
                    var settings=new SettingsWindow(owner); settings.Show(); Pump();
                    var controls=Tree(settings.Content as DependencyObject??settings).OfType<CheckBox>().ToArray();
                    Check(controls.Any(c=>c.Content?.ToString()=="自动检查更新" && c.IsChecked==false),"update opt-out visible");
                    Check(controls.Any(c=>c.Content?.ToString()=="更新提醒" && c.IsChecked==false),"system reminders opt in");
                    Check(Tree(settings.Content as DependencyObject??settings).OfType<Button>().Any(c=>c.Content?.ToString()=="检查更新"),"manual update action visible");
                    Check(settings.Content is ScrollViewer,"settings remain reachable on short screens");
                    var bitmap=new RenderTargetBitmap((int)settings.ActualWidth,(int)settings.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(settings);
                    var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using(var file=File.Create(Path.Combine(output,"settings-updates-"+(dark?"dark":"light")+".png"))) encoder.Save(file);
                    settings.Close();
                }
            }
            File.WriteAllText(Path.Combine(updateRoot,"updates.json"),"{\"Policy\":null}");
            using(var owner=new Coordinator(app,updateRoot,new HttpClient(new AvailableFeedHandler()))) {
                owner.Updates.Check(true); var deadline=DateTime.UtcNow.AddSeconds(5);
                while(owner.Updates.Checking && DateTime.UtcNow<deadline) Pump();
                Check(owner.Updates.Available?.Version=="999.0.0","valid Windows release discovered");
                foreach(var dark in new[]{false,true}) {
                    owner.Save(new Preferences { Theme=dark?"dark":"light",Language="zh-CN",AutomaticUpdates=false },false);
                    var settings=new SettingsWindow(owner); settings.Show(); Pump();
                    Check(Tree(settings.Content as DependencyObject??settings).OfType<Button>().Any(c=>c.Content?.ToString()=="查看更新" && c.IsVisible),"discovered update actions visible");
                    var bitmap=new RenderTargetBitmap((int)settings.ActualWidth,(int)settings.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(settings);
                    var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using(var file=File.Create(Path.Combine(output,"settings-update-available-"+(dark?"dark":"light")+".png"))) encoder.Save(file);
                    settings.Close();
                }
                owner.Updates.Skip(); Check(File.ReadAllText(Path.Combine(updateRoot,"updates.json")).Contains("999.0.0"),"skip persisted");
                owner.Updates.Dispose(); owner.Updates.Dispose(); owner.Updates.ReminderShown();
            }
            Directory.Delete(updateRoot,true);
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

internal sealed class InterruptedFeedHandler : HttpMessageHandler {
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content=new StreamContent(new InterruptedFeedStream()) });
}
internal sealed class InterruptedFeedStream : MemoryStream {
    public override ValueTask<int> ReadAsync(Memory<byte> buffer,CancellationToken token=default)=>ValueTask.FromException<int>(new IOException("Interrupted response body"));
}

internal sealed class AvailableFeedHandler : HttpMessageHandler {
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content=new StringContent("""{"schemaVersion":1,"stable":{"windows-x64":{"version":"999.0.0","minOS":"10.0","releaseNotesURL":"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v999.0.0"}}}""") });
}
