using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using QuotaBar.Core;
using QuotaBar.Windows;

internal static class BarkTests {
    internal sealed class Secrets : IBarkSecretStore {
        public string? Key; public bool Fail;
        public BarkSecretResult Read()=>Fail?new(BarkSecretState.Unavailable):Key is null?new(BarkSecretState.Missing):new(BarkSecretState.Available,Key);
        public bool Write(string key) { if(Fail) return false; Key=key; return true; }
        public bool Clear() { if(Fail) return false; Key=null; return true; }
    }
    internal sealed class AcceptedTransport : IBarkPushClient { public Task<BarkPushResult> Send(string key,string title,string body,CancellationToken token)=>Task.FromResult(BarkPushResult.Accepted); }
    internal sealed class Transport : IBarkPushClient {
        public int Sends; public TaskCompletionSource<BarkPushResult>? Pending;
        public Task<BarkPushResult> Send(string key,string title,string body,CancellationToken token) { Sends++; return Pending?.Task??Task.FromResult(BarkPushResult.Accepted); }
    }
    sealed class Handler(HttpStatusCode code,string body) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellationToken) {
            Check(request.RequestUri?.AbsoluteUri=="https://api.day.app/push"&&request.Method==HttpMethod.Post,"fixed POST endpoint");
            return Task.FromResult(new HttpResponseMessage(code) { Content=new StringContent(body) });
        }
    }
    static void Check(bool value,string name) { if(!value) throw new Exception("Bark: "+name); }
    public static async Task Run() {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-bark-"+Guid.NewGuid()); Directory.CreateDirectory(root);
        try {
            var corruptPath=Path.Combine(root,"corrupt-start.json"); File.WriteAllText(corruptPath,"broken"); var corruptPreferences=new BarkPreferences { Enabled=true };
            using(var corrupt=new BarkNotificationController(new Secrets { Key="fake-key" },new Transport(),new BarkDeliveryStore(corruptPath),corruptPreferences,p=>corruptPreferences=p)) { Check(!corrupt.Preferences.Enabled&&!corruptPreferences.Enabled,"corrupt receipts pause auto until explicit enable"); }
            var secrets=new Secrets(); var transport=new Transport(); var prefs=new BarkPreferences();
            using var controller=new BarkNotificationController(secrets,transport,new BarkDeliveryStore(Path.Combine(root,"receipts.json")),prefs,p=>prefs=p);
            Check(!controller.SetEnabled(true)&&!prefs.Enabled,"missing key cannot enable");
            Check(controller.SaveKey("fake-device-key")&&!prefs.Enabled&&transport.Sends==0,"save is explicit and does not enable or send");
            Check(controller.SetEnabled(true),"saved key enables");
            var receipt=0; var message=new ExperienceNotification("event",ExperienceNotificationKind.Update,null,"Example","Sample only",DateTimeOffset.UtcNow);
            controller.Enqueue(message,_=>true,_=>receipt++); await controller.WhenIdle;
            controller.Enqueue(message,_=>true,_=>receipt++); await controller.WhenIdle;
            Check(transport.Sends==1&&receipt==1,"automatic dedup independent of desktop");
            controller.Enqueue(message with { Id="preview",Kind=ExperienceNotificationKind.Test },_=>true,_=>receipt++); await controller.WhenIdle;
            Check(transport.Sends==1,"desktop examples excluded");
            Check(await controller.Test("Example","Sample only")==BarkPushResult.Accepted&&transport.Sends==2&&receipt==1,"explicit test separate from real receipts");
            secrets.Fail=true; var old=prefs; Check(!controller.SaveKey("replacement")&&prefs==old,"failed secure save preserves settings"); secrets.Fail=false;
            secrets.Fail=true; Check(!controller.ClearKey()&&!prefs.Enabled,"failed clear still disables and cancels"); secrets.Fail=false; Check(controller.SetEnabled(true),"reenable after failed clear");
            transport.Pending=new(TaskCreationOptions.RunContinuationsAsynchronously);
            controller.Enqueue(message with { Id="late",Epoch="old" },_=>true,_=>receipt++);
            Check(controller.ClearKey()&&!prefs.Enabled,"clear disables"); transport.Pending.SetResult(BarkPushResult.Accepted); await controller.WhenIdle;
            Check(receipt==1,"old config completion ignored"); transport.Pending=null;
            Check(controller.SaveKey("fake-device-key")&&controller.SetEnabled(true),"reconfigure");
            controller.Enqueue(message,_=>true,_=>receipt++); await controller.WhenIdle;
            Check(transport.Sends==3,"reconfigure does not replay receipt");
            using var restart=new BarkNotificationController(secrets,transport,new BarkDeliveryStore(Path.Combine(root,"receipts.json")),prefs,_=>{});
            restart.Enqueue(message,_=>true,_=>receipt++); await restart.WhenIdle;
            Check(transport.Sends==3,"restart preserves attempted receipt");
            restart.Enqueue(message with { Id="invalid" },_=>false,_=>receipt++); await restart.WhenIdle;
            Check(transport.Sends==3,"invalid event suppressed");
            var serialTransport=new Transport { Pending=new(TaskCreationOptions.RunContinuationsAsynchronously) }; var serialPrefs=new BarkPreferences { Enabled=true }; var serialReceipts=0;
            using(var serial=new BarkNotificationController(secrets,serialTransport,new BarkDeliveryStore(Path.Combine(root,"serial.json")),serialPrefs,_=>{})) {
                serial.Enqueue(message with { Id="serial-real" },_=>true,_=>serialReceipts++);
                var sample=serial.Test("Example","Sample only");
                Check(serialTransport.Sends==1,"sample waits for automatic transport");
                Check(await serial.Test("Example","Sample only")==BarkPushResult.Cancelled,"duplicate sample test rejected while queued");
                serialTransport.Pending.SetResult(BarkPushResult.Accepted); await serial.WhenIdle; await sample;
                Check(serialTransport.Sends==2&&serialReceipts==1,"sample and real sends serialize and receipt independently");
                serialTransport.Pending=new(TaskCreationOptions.RunContinuationsAsynchronously);
                serial.Enqueue(message with { Id="same-id",Epoch="old",ReminderGeneration="first" },_=>true,_=>serialReceipts++);
                serial.CancelAuthenticationEpoch("old");
                serial.Enqueue(message with { Id="same-id",Epoch="new",ReminderGeneration="second" },_=>true,_=>serialReceipts++);
                serialTransport.Pending.SetResult(BarkPushResult.Accepted); await serial.WhenIdle;
                Check(serialReceipts==2&&serialTransport.Sends==4,"late old epoch cannot receipt replacement generation");
                var allowed=true; serialTransport.Pending=new(TaskCreationOptions.RunContinuationsAsynchronously);
                serial.Enqueue(message with { Id="category-disabled" },_=>allowed,_=>serialReceipts++); allowed=false; serial.Revalidate(); serialTransport.Pending.SetResult(BarkPushResult.Accepted); await serial.WhenIdle;
                Check(serialReceipts==2,"category disabled cancels in-flight receipt");
                serialTransport.Pending=null;
                serial.Enqueue(message with { Id="same-id",Epoch="new",ReminderGeneration="third" },_=>true,_=>serialReceipts++); await serial.WhenIdle;
                Check(serialReceipts==3,"explicit rearm generation may send");
            }
            var blocked=Path.Combine(root,"blocked"); File.WriteAllText(blocked,"block directory creation");
            var blockedPrefs=new BarkPreferences(); var baselineTransport=new Transport();
            using(var baseline=new BarkNotificationController(secrets,baselineTransport,new BarkDeliveryStore(Path.Combine(blocked,"receipts.json")),blockedPrefs,p=>blockedPrefs=p)) {
                baseline.CurrentMessages=()=>new[]{message with { Id="current-update" }};
                Check(!baseline.SetEnabled(true)&&!blockedPrefs.Enabled,"baseline write failure disables automatic delivery");
                File.Delete(blocked); Directory.CreateDirectory(blocked);
                Check(baseline.SetEnabled(true),"baseline retry after storage recovery");
                baseline.Enqueue(message with { Id="current-update" },_=>true,_=>receipt++); await baseline.WhenIdle;
                Check(baselineTransport.Sends==0,"current update suppressed after baseline retry");
            }
            using(var baselineRestart=new BarkNotificationController(secrets,baselineTransport,new BarkDeliveryStore(Path.Combine(blocked,"receipts.json")),blockedPrefs,_=>{})) {
                baselineRestart.Enqueue(message with { Id="current-update" },_=>true,_=>receipt++); await baselineRestart.WhenIdle;
                Check(baselineTransport.Sends==0,"enable-current-update baseline survives restart");
            }
            using(var failPrefs=new BarkNotificationController(secrets,new Transport(),new BarkDeliveryStore(Path.Combine(root,"prefs-failure.json")),new BarkPreferences(),_=>throw new IOException("synthetic"))) {
                Check(!failPrefs.SetEnabled(true)&&!failPrefs.Preferences.Enabled&&failPrefs.Status==BarkStatus.PersistenceUnavailable,"preferences failure fails closed without crash");
            }
            foreach(var (code,body,expected) in new[]{(HttpStatusCode.OK,"{\"code\":200}",BarkPushResult.Accepted),(HttpStatusCode.OK,"{\"code\":400}",BarkPushResult.Rejected),(HttpStatusCode.Redirect,"{}",BarkPushResult.Rejected),(HttpStatusCode.OK,new string('x',65537),BarkPushResult.Unknown)}) {
                using var client=new BarkPushClient(new HttpClient(new Handler(code,body)));
                Check(await client.Send("fake-device-key","Example","Sample only",CancellationToken.None)==expected,"bounded response classification");
            }
            Console.WriteLine("Bark portable fake tests passed");
        } finally { Directory.Delete(root,true); }
    }
}
