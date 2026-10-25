using System;
using System.Collections.Generic;
using System.Linq;
using QuotaBar.Core;
using QuotaBar.Windows;
internal static class NotificationMatrixTests {
 public static void Run(System.Windows.Application app) {
  using var tray=new System.Windows.Forms.NotifyIcon(); var receipts=0; var system=0; var bubbles=0;
  using var router=new AppNotificationRouter(tray,_=>true,_=>{},_=>receipts++);
  router.Configure(new() { Mode=NotificationDeliveryMode.Off });
  var p=new NotificationPolicyPreferences { EnabledChannels=[NotificationChannel.System],Rules=new() { [NotificationCategory.QuotaRecovered]=[NotificationChannel.System] } };
  router.ConfigurePolicy(p);
  var callbacks=new List<Action<bool>>();
  router.SystemDelivery=(_,done)=> { system++; callbacks.Add(done); };
  router.PresentBubble=_=> { bubbles++; return true; }; router.UpdateEnvironment(true);
  var m=new ExperienceNotification("matrix",ExperienceNotificationKind.Recovery,"a","r","",DateTimeOffset.UtcNow,Category:NotificationCategory.QuotaRecovered);
  router.Enqueue(m); Check(system==1&&bubbles==0,"matrix overrides legacy off");
  p=p with { EnabledChannels=[NotificationChannel.Bubble],Rules=new() { [NotificationCategory.QuotaRecovered]=[NotificationChannel.Bubble] } };
  router.ConfigurePolicy(p); callbacks[0](true); Check(receipts==0,"late disabled system cannot receipt");
  router.Enqueue(m); Check(bubbles==0,"old event cannot gain bubble");
  router.Enqueue(m with { Id="new" }); Check(bubbles==1,"new event uses new policy");
  router.ConfigurePolicy(p with { EnabledChannels=[] }); router.ConfigurePolicy(p); Check(bubbles==1,"reopen cannot replay");
  using var secondTray=new System.Windows.Forms.NotifyIcon(); using var dedup=new AppNotificationRouter(secondTray,_=>true,_=>{},_=>{});
  dedup.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.System],Rules=new() { [NotificationCategory.UpdateAvailable]=[NotificationChannel.System] } });
  var attempts=0; dedup.SystemDelivery=(_,done)=> { attempts++; done(true); };
  var update=new ExperienceNotification("version",ExperienceNotificationKind.Update,null,"x","",DateTimeOffset.UtcNow,Category:NotificationCategory.UpdateAvailable);
  dedup.Enqueue(update); dedup.CancelMessage(update.Id); dedup.Enqueue(update); Check(attempts==1,"accepted same generation cannot resend");
  dedup.CancelMessage(update.Id); dedup.Enqueue(update with { ReminderGeneration="later" }); Check(attempts==2,"new generation may deliver");
  using var testTray=new System.Windows.Forms.NotifyIcon(); using var testRouter=new AppNotificationRouter(testTray,_=>true,_=>{},_=>{});
  var testSystems=0; var testBubbles=0;
  testRouter.Configure(new() { Mode=NotificationDeliveryMode.Off });
  testRouter.SystemDelivery=(_,done)=> { testSystems++; done(true); }; testRouter.PresentBubble=_=> { testBubbles++; return true; }; testRouter.UpdateEnvironment(true);
  testRouter.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.System],Rules=[] });
  testRouter.SendTestNotification("Example","Sample only"); Check(testSystems==1&&testBubbles==0,"test uses system master even with legacy off and no categories");
  testRouter.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.Bubble],Rules=[] });
  testRouter.SendTestNotification("Example","Sample only"); Check(testSystems==1&&testBubbles==1,"test uses bubble master");
  testRouter.ConfigurePolicy(new() { EnabledChannels=[],Rules=[] }); testRouter.Configure(new() { Mode=NotificationDeliveryMode.Both });
  testRouter.SendTestNotification("Example","Sample only"); Check(testSystems==1&&testBubbles==1,"all masters off blocks example even with legacy both");
  var testRoot=System.IO.Path.Combine(System.IO.Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   var transport=new BarkTests.Transport();
   using var mobile=new BarkNotificationController(new BarkTests.Secrets { Key="fake-key" },transport,new BarkDeliveryStore(System.IO.Path.Combine(testRoot,"receipts.json")),new(),_=>{});
   testRouter.Mobile=mobile; Check(testRouter.SetChannelEnabled(NotificationChannel.Mobile,true),"test mobile can enable");
   testRouter.SendTestNotification("Example","No account data"); Check(transport.Sends==1,"mobile master uses dedicated example API");
   Check(testRouter.SetChannelEnabled(NotificationChannel.Mobile,false),"test mobile can disable");
   testRouter.SendTestNotification("Example","No account data"); Check(transport.Sends==1,"closed mobile master sends nothing");
  } finally { if(System.IO.Directory.Exists(testRoot)) System.IO.Directory.Delete(testRoot,true); }

 }
 public static void TestWarningProducer(System.Windows.Application app) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   using var owner=new Coordinator(app,root,barkSecrets:new BarkTests.Secrets());
   Check(owner.Notifications.PolicyPreferences.Rules.Count==6&&owner.Notifications.PolicyPreferences.Rules.Values.All(c=>c.SetEquals(Enum.GetValues<NotificationChannel>()))&&owner.Notifications.PolicyPreferences.EnabledChannels.SetEquals(new[]{NotificationChannel.Bubble}),"actual fresh Coordinator initializes18 rules with independent masters");
   owner.Save(owner.Preferences with { Experience=new(true,false,false,false) },false);
   owner.Notifications.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.System],Rules=new() { [NotificationCategory.QuotaLow]=[NotificationChannel.System],[NotificationCategory.QuotaExhausted]=[NotificationChannel.System] } });
   int? customValue=15;
   var matrix=new NotificationMatrixSettingsView(owner,_=>customValue);
   var pause=Tree(matrix).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.pause"));
   Check(System.Windows.Automation.AutomationProperties.GetName(pause)==pause.Content.ToString(),"pause accessible name initially follows label");
   pause.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(System.Windows.Automation.AutomationProperties.GetName(pause)==pause.Content.ToString(),"pause accessible name follows resume label");
   var threshold=Tree(matrix).OfType<System.Windows.Controls.ComboBox>().Single(b=>Equals(b.Tag,"notification.threshold"));
   Check(threshold.Items.Count==4,"custom option available"); threshold.SelectedIndex=3; app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
   Check(owner.Notifications.PolicyPreferences.LowRemainingThreshold==15,"custom saves percent");
   Check(threshold.Text.Contains("15%"),"custom displays percent after native selection settles");
   customValue=17; threshold.SelectedIndex=3; app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
   Check(owner.Notifications.PolicyPreferences.LowRemainingThreshold==17&&threshold.Text.Contains("17%"),"saved custom can reopen without choosing preset");
   customValue=null; threshold.SelectedIndex=3; app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
   Check(owner.Notifications.PolicyPreferences.LowRemainingThreshold==17,"reediting custom cancel preserves value");
   threshold.SelectedIndex=1; customValue=null; threshold.SelectedIndex=3; app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
   Check(owner.Notifications.PolicyPreferences.LowRemainingThreshold==20&&threshold.SelectedIndex==1,"custom cancel preserves preset");
   customValue=19; threshold.SelectedIndex=3; threshold.SelectedIndex=1;
   app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
   Check(owner.Notifications.PolicyPreferences.LowRemainingThreshold==20&&threshold.SelectedIndex==1&&!threshold.Text.Contains("19%"),"deferred custom label cannot overwrite newer preset");
   customValue=100; threshold.SelectedIndex=3; Check(owner.Notifications.PolicyPreferences.LowRemainingThreshold==20,"invalid custom rejected");
   Check(threshold.Parent is System.Windows.Controls.StackPanel { Orientation:System.Windows.Controls.Orientation.Horizontal },"threshold inline with low title");
   var controls=Tree(matrix).OfType<System.Windows.Controls.CheckBox>().ToArray();
   Check(controls.Where(c=>c.Tag is string tag&&tag.StartsWith("notification.master.")).All(c=>c.HorizontalAlignment==System.Windows.HorizontalAlignment.Left),"master label and switch compact");
   Check(controls.Count(c=>c.Tag is string tag&&tag.StartsWith("notification.rule."))==18,"18 independent UI cells");
   var low=controls.Single(c=>Equals(c.Tag,"notification.rule.quotaLow.bubble"));
   Check(!low.IsEnabled,"closed bubble column disabled");
   low.IsChecked=true; low.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(!owner.Notifications.PolicyPreferences.Rules[NotificationCategory.QuotaLow].Contains(NotificationChannel.Bubble),"disabled cell cannot save");
   var master=controls.Single(c=>Equals(c.Tag,"notification.master.bubble")); master.IsChecked=true;
   Check(low.IsEnabled,"opening master enables column");
   low.IsChecked=true; low.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(owner.Notifications.PolicyPreferences.Rules[NotificationCategory.QuotaLow].Contains(NotificationChannel.Bubble),"UI saves low bubble only");
   master.IsChecked=false; Check(!low.IsEnabled&&low.IsChecked==true,"closing preserves selection");
   var testButton=Tree(matrix).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.test"));
   Check(matrix.Children.IndexOf(testButton)==2,"test immediately follows matrix card");
   var testSystems=0; owner.Notifications.SystemDelivery=(_,done)=> { testSystems++; done(true); };
   owner.Experience.PreviewCelebration(); Check(testSystems==0,"celebration preview stays local");
   testButton.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(testSystems==1,"matrix test button wired to enabled system master");
   var beforeSelect=owner.Notifications.PolicyPreferences;
   var selectAll=Tree(matrix).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.selectAll"));
   selectAll.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(owner.Notifications.PolicyPreferences.Rules.Values.All(c=>c.SetEquals(Enum.GetValues<NotificationChannel>()))&&owner.Notifications.PolicyPreferences.Rules.Count==6,"select all fills18 cells including disabled");
   Check(owner.Notifications.PolicyPreferences.EnabledChannels.SetEquals(beforeSelect.EnabledChannels)&&owner.Notifications.PolicyPreferences.LowRemainingThreshold==beforeSelect.LowRemainingThreshold&&owner.Notifications.PolicyPreferences.BubblePausedUntil==beforeSelect.BubblePausedUntil,"select all retains masters threshold pause");
   Check(owner.Notifications.PolicyPreferences.Rules[NotificationCategory.QuotaLow].Contains(NotificationChannel.Mobile)&&!controls.Single(c=>Equals(c.Tag,"notification.rule.quotaLow.mobile")).IsEnabled,"disabled selected mobile remains disabled");
   owner.Notifications.ConfigurePolicy(beforeSelect);
   var categories=new List<NotificationCategory>();
   owner.Notifications.SystemDelivery=(m,done)=> { if(m.Category is {} c) categories.Add(c); done(true); };
   var now=DateTimeOffset.UtcNow; var values=new[]{30,20,0,100,100,0};
   for(var i=0;i<values.Length;i++) {
    var at=now.AddSeconds((i-5)*20); var q=new QuotaSnapshot(new(100-values[i],values[i],now.AddHours(1),300),null,"plus",null,null,at);
    owner.Experience.Receive(new("a",i,at,q));
   }
   Check(System.Linq.Enumerable.SequenceEqual(categories,new[]{NotificationCategory.QuotaLow,NotificationCategory.QuotaExhausted,NotificationCategory.QuotaExhausted}),"producer ignores old switches and internally rearms");
  } finally { if(System.IO.Directory.Exists(root)) System.IO.Directory.Delete(root,true); }
 }
 public static void TestUpdateProducer(System.Windows.Application app) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   using var owner=new Coordinator(app,root,new System.Net.Http.HttpClient(new Feed()),new BarkTests.Secrets(),new BarkTests.AcceptedTransport());
   owner.Save(owner.Preferences with { AutomaticUpdates=false,UpdateReminders=false },false);
   owner.Notifications.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.System],Rules=new() { [NotificationCategory.UpdateAvailable]=[NotificationChannel.System] } });
   var categories=new List<NotificationCategory>(); owner.Notifications.SystemDelivery=(m,done)=> { if(m.Category is {} c) categories.Add(c); done(true); };
   owner.Updates.Check(true); var end=DateTime.UtcNow.AddSeconds(5);
   while(owner.Updates.Checking&&DateTime.UtcNow<end) { System.Windows.Threading.Dispatcher.CurrentDispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle); System.Threading.Thread.Sleep(10); }
   Check(!owner.Updates.Checking&&categories.SequenceEqual(new[]{NotificationCategory.UpdateAvailable}),"manual check uses matrix while legacy reminder and automatic checks are off");
  } finally { if(System.IO.Directory.Exists(root)) System.IO.Directory.Delete(root,true); }
 }
 sealed class Feed : System.Net.Http.HttpMessageHandler {
  protected override System.Threading.Tasks.Task<System.Net.Http.HttpResponseMessage> SendAsync(System.Net.Http.HttpRequestMessage request,System.Threading.CancellationToken cancellationToken)=>System.Threading.Tasks.Task.FromResult(new System.Net.Http.HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content=new System.Net.Http.StringContent("{\"schemaVersion\":1,\"stable\":{\"windows-x64\":{\"version\":\"9.0.0\",\"minOS\":\"10.0\",\"releaseNotesURL\":\"https://github.com/JaceHwang/QuotaBar/releases/tag/v9.0.0\"}}}") });
 }
 static System.Collections.Generic.IEnumerable<System.Windows.DependencyObject> Tree(System.Windows.DependencyObject root) {
  yield return root;
  foreach(var child in System.Windows.LogicalTreeHelper.GetChildren(root).OfType<System.Windows.DependencyObject>()) foreach(var item in Tree(child)) yield return item;
 }
 static void Check(bool value,string message) { if(!value) throw new Exception(message); }
}
