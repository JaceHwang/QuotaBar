using System;
using System.IO;
using System.Net;
using System.Text.Json;
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
            Check(prefs.Experience.Moods && prefs.Experience.Recovery && prefs.Experience.Celebration && prefs.Experience.Bank,"all four default on");
            foreach(var mood in Enum.GetValues<QuotaMood>()) foreach(var dark in new[]{false,true}) {
                var view=new QuotaMoodView { Width=80,Height=80,Mood=mood,Dark=dark,Stars=mood==QuotaMood.Recovered };
                Check(!view.IsHitTestVisible,"character is decorative and never intercepts clicks");
                view.Measure(new Size(80,80)); view.Arrange(new Rect(0,0,80,80));
                var bitmap=new RenderTargetBitmap(80,80,96,96,PixelFormats.Pbgra32); bitmap.Render(view);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var file=File.Create(Path.Combine(output,$"mood-{dark}-{mood}.png")); encoder.Save(file);
            }
            prefs=prefs with { Experience=new(Moods:true,Recovery:false,Celebration:false,Bank:false) }; button.Render(quota,state,prefs,copy,false); Pump();
            Check(button.Height==30,"mood keeps original floating height");
            var floatingMood=Tree(button).OfType<QuotaMoodView>().Single();
            Check(floatingMood.ActualWidth>=28 && floatingMood.ActualHeight>=28,"mood fills floating height without enlarging bar");
            Check(!prefs.Experience.Celebration,"preview test explicitly disables automatic celebration");
            button.Celebrate(); Check(button.IsCelebrating,"preview works independently of celebration toggle");
            button.HideFloat(); Check(!button.IsCelebrating,"hide cancels celebration");
            button.Celebrate(); Check(!button.IsCelebrating,"hidden float never celebrates");
            prefs=prefs with { Experience=new() }; button.Render(quota,state,prefs,copy,false); Pump();
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
                    var experienceToggles=Tree(settings.Content as DependencyObject??settings).OfType<CheckBox>().Where(b=>new[]{"额度表情模式","额度恢复时提醒","额度恢复时播放小庆祝","Bank 到期提醒"}.Contains(b.Content?.ToString())).ToArray();
                    Check(experienceToggles.Length==4 && experienceToggles.All(b=>b.IsChecked==true),"four independent default-on controls present");
                    Check(Tree(settings).OfType<ScrollViewer>().Any(),"settings remain reachable on short screens");
                    Check(Tree(settings).OfType<QuotaMoodView>().Count()==6,"inline five mood states plus recovery illustration");
                    var moodBitmap=new RenderTargetBitmap((int)settings.ActualWidth,(int)settings.ActualHeight,96,96,PixelFormats.Pbgra32); moodBitmap.Render(settings);
                    var moodEncoder=new PngBitmapEncoder(); moodEncoder.Frames.Add(BitmapFrame.Create(moodBitmap)); using(var moodFile=File.Create(Path.Combine(output,"settings-b-"+(dark?"dark":"light")+".png"))) moodEncoder.Save(moodFile);
                    var navigation=Tree(settings).OfType<Button>().Where(b=>b.Tag is string tag && tag.StartsWith("settings-nav-")).ToArray();
                    Check(navigation.Length==4,"four sidebar pages");
                    var moodToggle=experienceToggles.First(b=>b.Content?.ToString()=="额度表情模式");
                    moodToggle.IsChecked=false; moodToggle.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
                    navigation.First(b=>b.Tag?.ToString()=="settings-nav-display").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                    navigation.First(b=>b.Tag?.ToString()=="settings-nav-moods").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                    Check(!owner.Preferences.Experience.Moods && Tree(settings).OfType<CheckBox>().Any(b=>b.Content?.ToString()=="额度表情模式" && b.IsChecked==false),"navigation preserves explicit mood opt-out");
                    owner.Save(owner.Preferences with { Experience=new() },false);
                    settings.Build();
                    navigation=Tree(settings).OfType<Button>().Where(b=>b.Tag is string tag && tag.StartsWith("settings-nav-")).ToArray();
                    navigation.First(b=>b.Tag?.ToString()=="settings-nav-updates").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
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
                    Tree(settings).OfType<Button>().First(b=>b.Tag?.ToString()=="settings-nav-updates").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                    Check(Tree(settings.Content as DependencyObject??settings).OfType<TextBlock>().Any(c=>c.Text.Contains("改善更新提醒")),"embedded release notes visible");
                    Check(Tree(settings.Content as DependencyObject??settings).OfType<Button>().Any(c=>c.Content?.ToString()=="查看更新" && c.IsVisible),"discovered update actions visible");
                    var bitmap=new RenderTargetBitmap((int)settings.ActualWidth,(int)settings.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(settings);
                    var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using(var file=File.Create(Path.Combine(output,"settings-update-available-"+(dark?"dark":"light")+".png"))) encoder.Save(file);
                    settings.Close();
                }
                owner.Updates.Skip(); Check(File.ReadAllText(Path.Combine(updateRoot,"updates.json")).Contains("999.0.0"),"skip persisted");
                owner.Updates.Dispose(); owner.Updates.Dispose(); owner.Updates.ReminderShown();
            }
            var clock=DateTimeOffset.FromUnixTimeSeconds(100000);
            File.WriteAllText(Path.Combine(updateRoot,"updates.json"),JsonSerializer.Serialize(new { LastSuccess=clock }));
            using(var owner=new Coordinator(app,updateRoot,new HttpClient(new AvailableFeedHandler()))) {
                owner.Save(new Preferences { AutomaticUpdates=false },false);
                using var updates=new UpdateController(owner,updateRoot,new HttpClient(new AvailableFeedHandler()),()=>clock);
                owner.Save(new Preferences { AutomaticUpdates=true },false);
                clock=clock.AddSeconds(31); updates.Check();
                var deadline=DateTime.UtcNow.AddSeconds(5); while(updates.Checking && DateTime.UtcNow<deadline) Pump();
                using(var updateState=JsonDocument.Parse(File.ReadAllText(Path.Combine(updateRoot,"updates.json"))))
                    Check(updateState.RootElement.GetProperty("LastSuccess").GetDateTimeOffset()==clock,"startup ignores recent successful check");
                var completed=clock; clock=completed.AddSeconds(86399); updates.Check(); Pump();
                using(var updateState=JsonDocument.Parse(File.ReadAllText(Path.Combine(updateRoot,"updates.json"))))
                    Check(updateState.RootElement.GetProperty("LastSuccess").GetDateTimeOffset()==completed,"automatic check waits full 24 hours");
                clock=completed.AddDays(1); updates.Check(); deadline=DateTime.UtcNow.AddSeconds(5); while(updates.Checking && DateTime.UtcNow<deadline) Pump();
                using(var updateState=JsonDocument.Parse(File.ReadAllText(Path.Combine(updateRoot,"updates.json"))))
                    Check(updateState.RootElement.GetProperty("LastSuccess").GetDateTimeOffset()==clock,"automatic check resumes after 24 hours");
            }
            using(var owner=new Coordinator(app,updateRoot,new HttpClient(new AvailableFeedHandler()))) {
                owner.Save(new Preferences { AutomaticUpdates=false },false);
                var failed=new InterruptedFeedHandler();
                using var updates=new UpdateController(owner,updateRoot,new HttpClient(failed),()=>clock);
                clock=clock.AddSeconds(31); updates.Check(); Pump();
                Check(failed.Requests==0,"disabled automatic startup sends no request");
                updates.Check(true); var deadline=DateTime.UtcNow.AddSeconds(5); while(updates.Checking && DateTime.UtcNow<deadline) Pump();
                Check(failed.Requests==1,"manual check works while automatic checks disabled");
                owner.Save(new Preferences { AutomaticUpdates=true },false);
                clock=clock.AddSeconds(299); updates.Check(); Pump(); Check(failed.Requests==1,"failure retry respects five-minute delay");
                clock=clock.AddSeconds(1); updates.Check(); deadline=DateTime.UtcNow.AddSeconds(5); while(updates.Checking && DateTime.UtcNow<deadline) Pump();
                Check(failed.Requests==2,"failure retries after five minutes rather than one day");
                clock=clock.AddSeconds(599); updates.Check(); Pump(); Check(failed.Requests==2,"second failure waits ten minutes");
                clock=clock.AddSeconds(1); updates.Check(); deadline=DateTime.UtcNow.AddSeconds(5); while(updates.Checking && DateTime.UtcNow<deadline) Pump();
                Check(failed.Requests==3,"second retry resumes after ten minutes");
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
    public int Requests { get; private set; }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token) {
        Requests++;
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content=new StreamContent(new InterruptedFeedStream()) });
    }
}
internal sealed class InterruptedFeedStream : MemoryStream {
    public override ValueTask<int> ReadAsync(Memory<byte> buffer,CancellationToken token=default)=>ValueTask.FromException<int>(new IOException("Interrupted response body"));
}

internal sealed class AvailableFeedHandler : HttpMessageHandler {
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content=new StringContent("""{"schemaVersion":1,"stable":{"windows-x64":{"version":"999.0.0","minOS":"10.0","summary":"改善更新提醒","releaseNotes":"更新内容\n• 改善更新提醒\n• 修复额度刷新","releaseNotesURL":"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v999.0.0"}}}""") });
}
