using System;
using System.Collections.Generic;
using System.Linq;
using QuotaBar.Core;
using QuotaBar.Windows;
internal static class NotificationMatrixTests {
 public static void Run(System.Windows.Application app) {
  TestLowPolicyTransitions(app);
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
 public static void TestPolicyFailureRecovery(System.Windows.Application app) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"policy-recovery-"+Guid.NewGuid());
  System.IO.Directory.CreateDirectory(root);
  var path=System.IO.Path.Combine(root,"notification-policy.json");
  var persisted=NotificationPolicyPreferences.AllSelected().WithLowThresholds([30,15]).WithBankHours([48,12]) with { EnabledChannels=[NotificationChannel.Bubble,NotificationChannel.System] };
  new NotificationPolicyStore(path).Save(persisted);
  var before=System.IO.File.ReadAllText(path);
  try {
   using var locked=new System.IO.FileStream(path,System.IO.FileMode.Open,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
   using var owner=new Coordinator(app,root,barkSecrets:new BarkTests.Secrets());
   Check(!owner.Notifications.PolicyActive&&owner.Notifications.PolicyError,"locked policy load reports failure");
   var view=new NotificationSettingsView(owner);
   Check(Tree(view).OfType<NotificationMatrixSettingsView>().Count()==1,"failed policy load must keep matrix visible");
   var cells=Tree(view).OfType<System.Windows.Controls.CheckBox>().Where(c=>c.Tag is string t&&t.StartsWith("notification.rule.")).ToArray();
   Check(cells.Length==15&&cells.All(c=>!c.IsEnabled),"unloaded matrix cannot edit unknown persisted rules");
   Check(!Tree(view).OfType<System.Windows.Controls.ComboBox>().Any(c=>Equals(c.Tag,"notification.channel")),"load failure cannot silently restore old settings UI");
   Check(Tree(view).OfType<System.Windows.Controls.TextBlock>().Any(t=>Equals(t.Tag,"notification.policy.failure")&&t.Text.Contains("notification-policy.json")),"load error includes concrete file failure");
   RenderPolicyState(view,"policy-load-failed");
   Check(!owner.Notifications.ConfigurePolicy(NotificationPolicyPreferences.AllSelected())&&!owner.Notifications.PolicyActive,"failed load cannot become memory-only success or replace unread settings");
   var retry=Tree(view).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.policy.retry"));
   retry.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(!owner.Notifications.PolicyActive,"retry while locked stays safely inactive");
   locked.Dispose();
   retry=Tree(view).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.policy.retry"));
   retry.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(owner.Notifications.PolicyActive&&!owner.Notifications.PolicyError,"retry recovers policy after temporary lock without restart");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual([30,15])&&owner.Notifications.PolicyPreferences.ConfiguredBankHours.SequenceEqual([48,12]),"retry reads persisted custom thresholds");
   Check(System.IO.File.ReadAllText(path)==before,"recovery does not overwrite unread existing policy");
   RenderPolicyState(view,"policy-load-recovered");
   Check(Tree(view).OfType<System.Windows.Controls.CheckBox>().Where(c=>c.Tag is string t&&t.StartsWith("notification.rule.")&&t.EndsWith(".bubble")).All(c=>c.IsEnabled),"successful retry unlocks correct columns");
  } finally { System.IO.Directory.Delete(root,true); }
 }
 static void RenderPolicyState(System.Windows.FrameworkElement view,string name) {
  var output=Environment.GetEnvironmentVariable("QUOTABAR_TEST_ARTIFACTS"); if(output is null) return;
  System.IO.Directory.CreateDirectory(output);
  var host=new System.Windows.Controls.Border { Background=System.Windows.Media.Brushes.White,Padding=new System.Windows.Thickness(12),Child=view };
  host.Measure(new System.Windows.Size(720,double.PositiveInfinity)); var height=Math.Ceiling(host.DesiredSize.Height);
  host.Arrange(new System.Windows.Rect(0,0,720,height)); host.UpdateLayout();
  var bitmap=new System.Windows.Media.Imaging.RenderTargetBitmap(720,(int)height,96,96,System.Windows.Media.PixelFormats.Pbgra32); bitmap.Render(host);
  var encoder=new System.Windows.Media.Imaging.PngBitmapEncoder(); encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
  using(var file=System.IO.File.Create(System.IO.Path.Combine(output,name+".png"))) encoder.Save(file);
  host.Child=null;
 }
 public static void TestInitialMigrationFailureRecovery(System.Windows.Application app) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"policy-migration-"+Guid.NewGuid());
  var path=System.IO.Path.Combine(root,"notification-policy.json"); System.IO.Directory.CreateDirectory(path);
  try {
   using var owner=new Coordinator(app,root,barkSecrets:new BarkTests.Secrets());
   Check(!owner.Notifications.PolicyActive&&owner.Notifications.PolicyLoadFailed,"failed initial policy write is recoverable");
   Check(!owner.Notifications.ConfigurePolicy(NotificationPolicyPreferences.AllSelected()),"initial failed migration cannot report memory-only save");
   System.IO.Directory.Delete(path);
   Check(owner.Notifications.RetryPolicy()&&owner.Notifications.PolicyActive&&!owner.Notifications.PolicyLoadFailed,"initial migration retries original fresh-install intent");
   Check(owner.Notifications.PolicyPreferences.Rules.Values.All(c=>c.SetEquals(Enum.GetValues<NotificationChannel>()))&&owner.Notifications.PolicyPreferences.EnabledChannels.SetEquals([NotificationChannel.Bubble]),"retry keeps fresh all-selected defaults and independent masters");
   Check(System.IO.File.Exists(path),"successful retry persists policy");
  } finally { System.IO.Directory.Delete(root,true); }
 }
 public static void TestWarningProducer(System.Windows.Application app) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   using var owner=new Coordinator(app,root,barkSecrets:new BarkTests.Secrets());
   Check(owner.Notifications.PolicyPreferences.Rules.Count==6&&owner.Notifications.PolicyPreferences.Rules.Values.All(c=>c.SetEquals(Enum.GetValues<NotificationChannel>()))&&owner.Notifications.PolicyPreferences.EnabledChannels.SetEquals(new[]{NotificationChannel.Bubble}),"actual fresh Coordinator initializes legacy rules for15 visible cells with independent masters");
   owner.Save(owner.Preferences with { Experience=new(true,false,false,false) },false);
   owner.Notifications.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.System],Rules=new() { [NotificationCategory.QuotaLow]=[NotificationChannel.System],[NotificationCategory.QuotaExhausted]=[NotificationChannel.System] } });
   var matrix=new NotificationMatrixSettingsView(owner);
   var pause=Tree(matrix).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.pause"));
   Check(System.Windows.Automation.AutomationProperties.GetName(pause)==pause.Content.ToString(),"pause accessible name initially follows label");
   pause.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(System.Windows.Automation.AutomationProperties.GetName(pause)==pause.Content.ToString(),"pause accessible name follows resume label");
   TestChipFocus(app,owner);
   var lowChips=Tree(matrix).OfType<DynamicThresholdChipsView>().Single(v=>Equals(v.Tag,"notification.threshold.low"));
   void Click(string tag) => Tree(matrix).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,tag)).RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   void Edit(string tag,string text,bool cancel=false) {
    var field=Tree(matrix).OfType<System.Windows.Controls.TextBox>().Single(b=>Equals(b.Tag,tag)); field.Text=text;
    if(cancel) { using var source=new System.Windows.Interop.HwndSource(new System.Windows.Interop.HwndSourceParameters("threshold test") { Width=1,Height=1 }); field.RaiseEvent(new System.Windows.Input.KeyEventArgs(System.Windows.Input.Keyboard.PrimaryDevice,source,0,System.Windows.Input.Key.Escape) { RoutedEvent=System.Windows.Input.Keyboard.KeyDownEvent }); }
    else field.RaiseEvent(new System.Windows.Input.KeyboardFocusChangedEventArgs(System.Windows.Input.Keyboard.PrimaryDevice,0,field,null) { RoutedEvent=System.Windows.Input.Keyboard.LostKeyboardFocusEvent });
   }
   Click("notification.threshold.low.add");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(new[]{20}),"blank addition remains unsaved");
   Edit("notification.threshold.low.new","10");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(new[]{20,10}),"valid addition saves sorted thresholds");
   Edit("notification.threshold.low.20","15");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(new[]{15,10}),"editing saves new threshold");
   Edit("notification.threshold.low.15","10");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(new[]{15,10}),"duplicate edit preserves thresholds");
   Edit("notification.threshold.low.15","100");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(new[]{15,10}),"invalid edit preserves thresholds");
   Click("notification.threshold.low.add"); Edit("notification.threshold.low.new","9",true);
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(new[]{15,10}),"cancel blank preserves thresholds");
   Click("notification.threshold.low.remove.15"); Click("notification.threshold.low.remove.10");
   Check(owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.Length==0&&Tree(lowChips).OfType<System.Windows.Controls.Button>().Any(b=>Equals(b.Tag,"notification.threshold.low.add")),"remove last leaves add and no hidden default");
   Click("notification.threshold.low.add"); Edit("notification.threshold.low.new","20");
   Check(lowChips.Children[0] is System.Windows.Controls.TextBlock,"name is first wrapping inline item");
   Check(Tree(matrix).OfType<System.Windows.Controls.TextBox>().All(b=>!string.IsNullOrWhiteSpace(System.Windows.Automation.AutomationProperties.GetName(b))),"chip fields have accessible names");
   var controls=Tree(matrix).OfType<System.Windows.Controls.CheckBox>().ToArray();
   Check(controls.Where(c=>c.Tag is string tag&&tag.StartsWith("notification.master.")).All(c=>c.HorizontalAlignment==System.Windows.HorizontalAlignment.Left),"master label and switch compact");
   Check(controls.Count(c=>c.Tag is string tag&&tag.StartsWith("notification.rule."))==15,"15 independent UI cells");
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
   var shortcuts=Tree(matrix).OfType<System.Windows.Controls.Button>().Where(b=>b.Tag is string t&&t.StartsWith("notification.selectAll.")).ToArray();
   Check(shortcuts.Length==3,"three column shortcuts");
   Check(!shortcuts.Single(b=>Equals(b.Tag,"notification.selectAll.bubble")).IsEnabled&&!shortcuts.Single(b=>Equals(b.Tag,"notification.selectAll.mobile")).IsEnabled,"closed masters disable shortcuts");
   Click("notification.selectAll.system");
   Check(owner.Notifications.PolicyPreferences.Rules.Values.All(c=>c.Contains(NotificationChannel.System)),"system shortcut selects system");
   Check(owner.Notifications.PolicyPreferences.Rules.All(r=>r.Value.Contains(NotificationChannel.Mobile)==(beforeSelect.Rules.GetValueOrDefault(r.Key)?.Contains(NotificationChannel.Mobile)==true)),"system shortcut preserves mobile");
   Check(owner.Notifications.PolicyPreferences.EnabledChannels.SetEquals(beforeSelect.EnabledChannels)&&owner.Notifications.PolicyPreferences.ConfiguredLowThresholds.SequenceEqual(beforeSelect.ConfiguredLowThresholds)&&owner.Notifications.PolicyPreferences.BubblePausedUntil==beforeSelect.BubblePausedUntil,"column selection retains masters thresholds pause");
   Click("notification.selectAll.system");
   Check(owner.Notifications.PolicyPreferences.Rules.Values.All(c=>!c.Contains(NotificationChannel.System))&&owner.Notifications.PolicyPreferences.ConfiguredBankHours.All(h=>!owner.Notifications.PolicyPreferences.BankChannels(h).Contains(NotificationChannel.System)),"second shortcut click clears only system including Bank mapping");
   Check(owner.Notifications.PolicyPreferences.Rules.All(r=>r.Value.Contains(NotificationChannel.Mobile)==(beforeSelect.Rules.GetValueOrDefault(r.Key)?.Contains(NotificationChannel.Mobile)==true)),"clear preserves mobile");
   Click("notification.selectAll.system");
   Check(owner.Notifications.PolicyPreferences.Rules.Values.All(c=>c.Contains(NotificationChannel.System)),"third shortcut click selects again");
   var mixed=beforeSelect with { BankExpiryHours=new[]{72,24},BankThresholdChannels=new() { [72]=[NotificationChannel.System],[24]=[] } };
   owner.Notifications.ConfigurePolicy(mixed);
   var mixedMatrix=new NotificationMatrixSettingsView(owner);
   var bank=Tree(mixedMatrix).OfType<System.Windows.Controls.CheckBox>().Single(c=>Equals(c.Tag,"notification.rule.bankExpiring72h.system"));
   Check(bank.IsThreeState&&bank.IsChecked==null,"merged Bank shows mixed channel");
   bank.IsChecked=true; bank.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(owner.Notifications.PolicyPreferences.ConfiguredBankHours.All(h=>owner.Notifications.PolicyPreferences.BankChannels(h).Contains(NotificationChannel.System)),"mixed Bank click unifies channel");
   bank.IsChecked=null; bank.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
   Check(owner.Notifications.PolicyPreferences.ConfiguredBankHours.All(h=>!owner.Notifications.PolicyPreferences.BankChannels(h).Contains(NotificationChannel.System)),"selected Bank checkbox unchecks all despite native three-state cycle");
   // Use the first view again to verify an edit keeps the old per-hour selection.
   owner.Notifications.ConfigurePolicy(mixed);
   Edit("notification.threshold.bank.72","48");
   Check(owner.Notifications.PolicyPreferences.BankChannels(48).SetEquals(new[]{NotificationChannel.System})&&!owner.Notifications.PolicyPreferences.BankChannels(24).Contains(NotificationChannel.System),"Bank edit preserves individual channel mapping");
   Click("notification.threshold.bank.add"); Edit("notification.threshold.bank.new","12");
   Check(owner.Notifications.PolicyPreferences.BankChannels(12).Count==0,"Bank addition inherits intersection");
   owner.Notifications.ConfigurePolicy(beforeSelect.WithLowThresholds(new[]{20,10}));
   var categories=new List<NotificationCategory>(); var levels=new List<int>();
   owner.Notifications.SystemDelivery=(m,done)=> { if(m.Category is {} c) categories.Add(c); if(m.Category==NotificationCategory.QuotaLow&&m.ReminderThreshold is {} level) levels.Add(level); done(true); };
   var now=DateTimeOffset.UtcNow; var values=new[]{30,20,10,0,100,100,0};
   for(var i=0;i<values.Length;i++) {
    var at=now.AddSeconds((i-(values.Length-1))*18); var q=new QuotaSnapshot(new(100-values[i],values[i],now.AddHours(1),300),null,"plus",null,null,at);
    owner.Experience.Receive(new("a",i,at,q));
   }
   Check(System.Linq.Enumerable.SequenceEqual(categories,new[]{NotificationCategory.QuotaLow,NotificationCategory.QuotaLow,NotificationCategory.QuotaExhausted,NotificationCategory.QuotaExhausted}),"producer uses every configured low level and internally rearms");
   Check(levels.SequenceEqual(new[]{20,10}),"actual producer attaches exact low threshold metadata");
  } finally { if(System.IO.Directory.Exists(root)) System.IO.Directory.Delete(root,true); }
 }
 static void TestLowPolicyTransitions(System.Windows.Application app) {
  foreach(var editRules in new[]{false,true}) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   using var owner=new Coordinator(app,root,barkSecrets:new BarkTests.Secrets(),barkTransport:new BarkTests.Transport());
   var policy=new NotificationPolicyPreferences { EnabledChannels=[NotificationChannel.System],Rules=new() { [NotificationCategory.QuotaLow]=[NotificationChannel.System],[NotificationCategory.QuotaExhausted]=[NotificationChannel.System] },LowRemainingThresholds=[20] };
   owner.Notifications.ConfigurePolicy(policy);
   var delivered=new List<NotificationCategory>(); owner.Notifications.SystemDelivery=(m,done)=> { if(m.Category is {} c) delivered.Add(c); done(true); };
   var now=DateTimeOffset.UtcNow; var sequence=0;
   void Receive(int remaining,int seconds) {
    var at=now.AddSeconds(seconds); var q=new QuotaSnapshot(new(100-remaining,remaining,now.AddHours(1),300),null,"plus",null,null,at);
    owner.Experience.Receive(new("a",++sequence,at,q));
   }
   void Readd() {
    owner.Notifications.ConfigurePolicy(editRules?policy with { Rules=new() { [NotificationCategory.QuotaLow]=[],[NotificationCategory.QuotaExhausted]=[NotificationChannel.System] } }:policy.WithLowThresholds([]));
    owner.Notifications.ConfigurePolicy(policy);
   }
   Receive(30,-80); Readd(); Receive(10,-60);
   Check(delivered.Count==0,"remove and readd between reads establishes low baseline");
   Receive(30,-40); Readd(); Receive(0,0);
   Check(delivered.SequenceEqual(new[]{NotificationCategory.QuotaExhausted}),"pending low baseline preserves actual depletion delivery");
  } finally { if(System.IO.Directory.Exists(root)) System.IO.Directory.Delete(root,true); }
 }
 }
 static void TestChipFocus(System.Windows.Application app,Coordinator owner) {
  TestFailedDeleteRecovery(app,owner);
  // A shown native window is essential: a synthetic LostKeyboardFocus event cannot
  // detect detaching the destination during the focus transition.
  foreach(var edit in new[]{"20","18","bad"}) foreach(var destination in new[]{"input","add","tab"}) {
   var values=new[]{20,10};
   var chips=new DynamicThresholdChipsView(new System.Windows.Controls.TextBlock { Text="Low" },"low",99,"%",owner.Copy,false,()=>values,(next,_)=>values=next);
   var window=new System.Windows.Window { Content=chips,Width=400,Height=140,ShowInTaskbar=false,WindowStartupLocation=System.Windows.WindowStartupLocation.CenterScreen };
   try {
    window.Show(); window.Activate(); window.UpdateLayout();
    void Settle()=>app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
    Settle();
    var first=Tree(chips).OfType<System.Windows.Controls.TextBox>().Single(b=>Equals(b.Tag,"notification.threshold.low.20"));
    var second=Tree(chips).OfType<System.Windows.Controls.TextBox>().Single(b=>Equals(b.Tag,"notification.threshold.low.10"));
    var add=Tree(chips).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.threshold.low.add"));
    Check(first.Focus(),"real chip focus established"); first.Text=edit;
    var remove=Tree(chips).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.threshold.low.remove.20"));
    var target=destination=="add"?(System.Windows.IInputElement)add:destination=="tab"?remove:second;
    if(destination=="tab") Check(first.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.Next)),"Tab traversal moves to next chip");
    else System.Windows.Input.Keyboard.Focus(target);
    Settle();
    Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,target),$"{edit} edit retains {destination} destination focus");
    if(destination=="tab") {
     Check(remove.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.Previous)),"Shift Tab returns from delete to its editor"); Settle();
     Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,first)&&first.Text==edit,"reverse Tab preserves pending editor and text");
     System.Windows.Input.Keyboard.Focus(remove); System.Windows.Input.Keyboard.Focus(first); Settle();
     Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,first)&&first.Text==edit,"direct focus return from delete preserves editor");
     // Continue typing after both return paths, then leave the editing region.
     first.Text=edit; System.Windows.Input.Keyboard.Focus(remove);
     Check(remove.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.Next)),"Tab leaves delete action for next editor"); Settle();
     Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,second),"field to delete to next field retains focus"); target=second;
    }
    Check(values.SequenceEqual(edit=="18"?new[]{18,10}:new[]{20,10}),"focus commit validates saved values");
    if(target==second) {
     second.Text="9"; System.Windows.Input.Keyboard.Focus(add); Settle();
     Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,add)&&values.Contains(9),"destination remains editable and can Tab onward to add");
     var edited=Tree(chips).OfType<System.Windows.Controls.TextBox>().First(); var saved=int.Parse(edited.Text);
     System.Windows.Input.Keyboard.Focus(edited); edited.Text="7";
     Check(edited.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.Next)),"delete action is keyboard reachable"); Settle();
     var delete=Tree(chips).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.threshold.low.remove."+saved));
     Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,delete),"changed field retains its keyboard delete target");
     delete.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Settle();
     Check(!values.Contains(saved)&&!values.Contains(7),"keyboard delete removes original without saving pending edit");
    } else {
     add.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Settle();
     var blank=Tree(chips).OfType<System.Windows.Controls.TextBox>().Single(b=>Equals(b.Tag,"notification.threshold.low.new"));
     Check(ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,blank),"focused add opens a usable focused blank");
    }
   } finally { window.Close(); }
  }
 }
 static void TestFailedDeleteRecovery(System.Windows.Application app,Coordinator owner) {
  foreach(var commit in new[]{"enter","blur"}) {
   var values=new[]{20,10}; var accept=false;
   var chips=new DynamicThresholdChipsView(new System.Windows.Controls.TextBlock { Text="Low" },"low",99,"%",owner.Copy,false,()=>values,(next,_)=> { if(accept) values=next; });
   var window=new System.Windows.Window { Content=chips,Width=400,Height=140,ShowInTaskbar=false };
   try {
    window.Show(); window.Activate(); window.UpdateLayout();
    void Settle()=>app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
    var field=Tree(chips).OfType<System.Windows.Controls.TextBox>().Single(b=>Equals(b.Tag,"notification.threshold.low.20"));
    var remove=Tree(chips).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.threshold.low.remove.20"));
    var add=Tree(chips).OfType<System.Windows.Controls.Button>().Single(b=>Equals(b.Tag,"notification.threshold.low.add"));
    void Key(System.Windows.Input.Key key) {
     using var source=new System.Windows.Interop.HwndSource(new System.Windows.Interop.HwndSourceParameters("failed delete") { Width=1,Height=1 });
     field.RaiseEvent(new System.Windows.Input.KeyEventArgs(System.Windows.Input.Keyboard.PrimaryDevice,source,0,key) { RoutedEvent=System.Windows.Input.Keyboard.KeyDownEvent });
    }
    Check(field.Focus(),"failed-delete field focused"); field.Text="17"; System.Windows.Input.Keyboard.Focus(remove);
    remove.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Settle();
    Check(values.SequenceEqual(new[]{20,10})&&field.Text=="20","refused deletion restores original value");
    Check(ReferenceEquals(Tree(chips).OfType<System.Windows.Controls.TextBox>().Single(b=>Equals(b.Tag,field.Tag)),field)&&ReferenceEquals(System.Windows.Input.Keyboard.FocusedElement,remove),"refused deletion retains editor and delete focus");
    System.Windows.Input.Keyboard.Focus(field); field.Text="16"; Key(System.Windows.Input.Key.Escape);
    Check(field.Text=="20"&&values.SequenceEqual(new[]{20,10}),"Escape remains usable after refused deletion");
    accept=true; field.Text="18";
    if(commit=="enter") Key(System.Windows.Input.Key.Enter); else System.Windows.Input.Keyboard.Focus(add);
    Settle(); Check(values.SequenceEqual(new[]{18,10}),"save recovers after refused deletion through "+commit);
   } finally { window.Close(); }
  }
 }
 public static void TestDynamicBankProducer(System.Windows.Application app) {
  var root=System.IO.Path.Combine(System.IO.Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   var transport=new BarkTests.Transport(); using var owner=new Coordinator(app,root,barkSecrets:new BarkTests.Secrets(),barkTransport:transport);
   Check(owner.Mobile.SaveKey("fake-key")&&owner.Mobile.SetEnabled(true),"fake mobile configured for exact Bank route");
   owner.Notifications.ConfigurePolicy(new() { EnabledChannels=[NotificationChannel.System,NotificationChannel.Mobile],BankExpiryHours=[72,24,12],BankThresholdChannels=new() { [72]=[NotificationChannel.System],[24]=[NotificationChannel.Mobile],[12]=[NotificationChannel.System] } });
   var systemLevels=new List<int>(); owner.Notifications.SystemDelivery=(m,done)=> { if(m.ReminderThreshold is {} h) systemLevels.Add(h); done(true); };
   var now=DateTimeOffset.UtcNow; var first=new BankCredit("available",null,now.AddHours(11),null,null,"twelve"); var second=new BankCredit("available",null,now.AddHours(23),null,null,"twentyfour");
   void Receive(params BankCredit[] credits) {
    var at=DateTimeOffset.UtcNow; var quota=new QuotaSnapshot(new(50,50,now.AddHours(1),300),null,"plus",null,new BankSummary(credits.Length,credits),at);
    owner.Experience.Receive(new("a",0,at,quota,BankFieldState.Value));
    var deadline=DateTime.UtcNow.AddSeconds(5); while(!owner.Mobile.WhenIdle.IsCompleted&&DateTime.UtcNow<deadline) { app.Dispatcher.Invoke(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle); System.Threading.Thread.Sleep(5); }
    Check(owner.Mobile.WhenIdle.IsCompleted,"fake mobile drain bounded"); owner.Mobile.WhenIdle.GetAwaiter().GetResult();
   }
   Receive(); Check(systemLevels.Count==0&&transport.Sends==0,"complete empty inventory establishes added hour12 baseline");
   Receive(first); Check(systemLevels.SequenceEqual(new[]{12})&&transport.Sends==0,"hour12 uses exact system mapping rather than legacy24");
   Receive(first,second); Check(systemLevels.Count==1&&transport.Sends==1,"hour24 retains mobile-only mapping");
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
