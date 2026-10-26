using System;
using System.Collections.Generic;
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
internal static class MessageCenterNativeTests {
 static void Check(bool value,string message) { if(!value) throw new Exception("message center: "+message); }
 static IEnumerable<DependencyObject> Tree(DependencyObject root) { yield return root;foreach(var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) foreach(var item in Tree(child)) yield return item; }
 static T Find<T>(DependencyObject root,string tag) where T:FrameworkElement=>Tree(root).OfType<T>().Single(v=>Equals(v.Tag,tag));
 static void Pump() { Dispatcher.CurrentDispatcher.Invoke(()=>{},DispatcherPriority.ApplicationIdle); }
 static void Click(DependencyObject root,string tag) { Find<Button>(root,tag).RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));Pump(); }
 static MessageCenterRecord Row(int i,Copy copy,long time)=>new(new("message-"+i,"initial","one"),i%3==0?NotificationCategory.QuotaLow:i%3==1?NotificationCategory.BankExpiring72h:NotificationCategory.UpdateAvailable,i%3==0?copy.Text("Quota low","额度偏低","額度偏低"):i%3==1?copy.Text("Bank expiring","Bank 即将到期","Bank 即將到期"):copy.Text("Update available","发现新版本","發現新版本"),copy.Text("The5-hour quota period has15% remaining. Recorded snapshot.","5小时额度周期剩余15%。这是提醒产生时的记录。","5小時額度週期剩餘15%。這是提醒產生時的記錄。"),time-i*1000,null,[NotificationChannel.Bubble,NotificationChannel.System]);
 static (string Root,System.Windows.Forms.NotifyIcon Tray,AppNotificationRouter Router,MessageCenterWindow Window) Create(string language="zh-CN",bool dark=false,int count=3) {
  var root=Path.Combine(Path.GetTempPath(),"message-ui-"+Guid.NewGuid());var store=new MessageCenterStore(Path.Combine(root,"message-center.json"));var copy=new Copy(language);
  Check(store.Append(Enumerable.Range(0,count).Select(i=>Row(i,copy,DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()))),"fixture saved");
  var tray=new System.Windows.Forms.NotifyIcon();var router=new AppNotificationRouter(tray,_=>true,_=>{},_=>{});router.BindMessageCenter(store);router.CurrentMessageEpoch="one";router.MessageDetailsRequested=()=>{};router.SystemUpdateRequested=()=>{};
  var window=new MessageCenterWindow(router,copy,dark);window.Show();Pump();return(root,tray,router,window);
 }
 static void Close((string Root,System.Windows.Forms.NotifyIcon Tray,AppNotificationRouter Router,MessageCenterWindow Window) s) { s.Window.Close();s.Router.Dispose();s.Tray.Dispose();if(Directory.Exists(s.Root)) Directory.Delete(s.Root,true); }
 public static void Run(Application app) {
  var s=Create();try {
   var list=Find<ListBox>(s.Window,"messages.list");var tabs=Find<TabControl>(s.Window,"messages.tabs");
   Check(list.Items.Count==3&&list.SelectedIndex==-1&&s.Router.MessageUnreadCount==3,"opening window never auto reads first row");
   tabs.SelectedIndex=1;Pump();Check(s.Router.MessageUnreadCount==3,"tab selection does not read");tabs.SelectedIndex=0;Pump();
   var clicked=s.Router.MessageHistory[1].Key;list.SelectedIndex=1;Pump();
   Check(s.Router.MessageUnreadCount==2&&list.Items.Count==2&&list.SelectedIndex==-1&&s.Window.SelectedKey==clicked,"opening detail reads exactly clicked row, not successor");
   Pump();Check(s.Router.MessageHistory.Count(r=>r.ReadAtMilliseconds!=null)==1,"read/filter event cannot cascade");
   tabs.SelectedIndex=1;Pump();Check(list.Items.Count==3&&s.Router.MessageUnreadCount==2,"history includes read rows");
   s.Window.Width=720;Pump();list.SelectedIndex=0;Pump();
   Check(Find<FrameworkElement>(s.Window,"messages.listPane").Visibility==Visibility.Collapsed&&Find<ScrollViewer>(s.Window,"messages.detailScroll").Visibility==Visibility.Visible,"narrow user selection opens detail");
   Click(s.Window,"messages.back");Check(Find<FrameworkElement>(s.Window,"messages.listPane").Visibility==Visibility.Visible,"back restores list");
   list.Focus();list.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(s.Window)!,0,Key.Enter) { RoutedEvent=Keyboard.KeyDownEvent });Pump();
   Check(Find<ScrollViewer>(s.Window,"messages.detailScroll").Visibility==Visibility.Visible,"keyboard can reopen selected detail without selection change");
   s.Window.Width=920;Pump();var selected=s.Window.SelectedKey;s.Router.CurrentMessageEpoch="another";Pump();
   Check(Tree(s.Window).OfType<TextBlock>().Any(t=>t.Text.Contains("历史会话")),"earlier epoch is a historical snapshot");
   var p=NotificationPolicyPreferences.AllSelected() with { EnabledChannels=[NotificationChannel.Bubble] };s.Router.ConfigurePolicy(p);s.Router.Enqueue(new("arrived",ExperienceNotificationKind.Recovery,"another","新消息","snapshot",DateTimeOffset.UtcNow,Category:NotificationCategory.QuotaRecovered));Pump();
   Check(tabs.SelectedIndex==1&&s.Window.SelectedKey==selected,"new arrival retains tab and detail");
   Click(s.Window,"messages.allRead");Check(s.Router.MessageUnreadCount==0&&list.Items.Count==4&&!Find<Button>(s.Window,"messages.allRead").IsEnabled,"all read preserves history");
   Check(new MessageCenterStore(Path.Combine(s.Root,"message-center.json")).UnreadCount==0,"read status survives restart");
  } finally { Close(s); }
  var empty=Create(count:0);try { Check(Find<ListBox>(empty.Window,"messages.list").Items.Count==0&&!Find<Button>(empty.Window,"messages.allRead").IsEnabled,"empty state");Find<TabControl>(empty.Window,"messages.tabs").SelectedIndex=1;Pump();Check(Find<TextBlock>(empty.Window,"messages.empty").Visibility==Visibility.Visible,"history empty state"); } finally { Close(empty); }
  TestCategories();TestStorageFailure();TestWriteFailure();TestLongAndLarge();RenderVariants();Console.WriteLine("PASS Windows message center auto-read/no-cascade, persistence, storage recovery, responsive and multilingual density renders");
 }
 static void TestCategories() {
  var s=Create(count:0);try {
   var cases=new[]{(NotificationCategory.QuotaExhausted,"额度耗尽"),(NotificationCategory.QuotaRecovered,"额度恢复"),(NotificationCategory.QuotaLow,"额度偏低"),(NotificationCategory.BankExpiring72h,"Bank 到期提醒"),(NotificationCategory.UpdateAvailable,"软件有新版本")};
   foreach(var (category,title) in cases) {
    var row=Row((int)category,new Copy("zh-CN"),DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()) with { Category=category,Title="通用标题" };Check(s.Router.MessageStore!.Append(row),"category fixture saved");
    s.Window.Refresh();Find<TabControl>(s.Window,"messages.tabs").SelectedIndex=1;Pump();
    Find<ListBox>(s.Window,"messages.list").SelectedIndex=s.Router.MessageHistory.ToList().FindIndex(r=>r.Key==row.Key);Pump();
    Check(Tree(s.Window).OfType<TextBlock>().Any(t=>Equals(t.Tag,"messages.detail.category")&&t.Text=="类别："+title),"explicit detail category "+category);
   }
  } finally { Close(s); }
 }
 static void TestStorageFailure() {
  var root=Path.Combine(Path.GetTempPath(),"message-corrupt-ui-"+Guid.NewGuid());Directory.CreateDirectory(root);var path=Path.Combine(root,"message-center.json");File.WriteAllText(path,"broken");
  using var tray=new System.Windows.Forms.NotifyIcon();using var router=new AppNotificationRouter(tray,_=>true,_=>{},_=>{});MessageCenterWindow? window=null;
  try {
   router.BindMessageCenter(new(path));router.ConfigurePolicy(NotificationPolicyPreferences.AllSelected());router.Enqueue(new("pending",ExperienceNotificationKind.Recovery,"one","pending","snapshot",DateTimeOffset.UtcNow,Category:NotificationCategory.QuotaRecovered));
   window=new(router,new Copy("zh-CN"),false);window.Show();Pump();Find<ListBox>(window,"messages.list").SelectedIndex=0;Pump();
   Check(router.MessageUnreadCount==1&&router.MessageStorageError!=null&&File.ReadAllText(path)=="broken","corrupt original preserved and no false read");
   Check(Find<TextBlock>(window,"messages.storageError").Visibility==Visibility.Visible,"storage error stays visible");
   File.WriteAllText(path,"{\"schema\":1,\"messages\":[]}");Click(window,"messages.retry");Check(router.MessageStorageError==null&&router.MessageUnreadCount==1,"retry merges pending without inventing read");
   Click(window,"messages.markRead");Check(new MessageCenterStore(path).UnreadCount==0,"explicit retry read persists");
  } finally { window?.Close();Directory.Delete(root,true); }
 }
 static void TestWriteFailure() {
  var s=Create();try {
   var path=Path.Combine(s.Root,"message-center.json");using(var locked=new FileStream(path,FileMode.Open,FileAccess.ReadWrite,FileShare.None)) { Find<ListBox>(s.Window,"messages.list").SelectedIndex=0;Pump();Check(s.Router.MessageUnreadCount==3&&s.Router.MessageStorageError!=null,"failed read-state write does not alter unread count"); }
   Click(s.Window,"messages.retry");Check(s.Router.MessageUnreadCount==3,"storage reload alone does not fake failed read intent");Click(s.Window,"messages.markRead");Check(s.Router.MessageUnreadCount==2,"retry reads only selected message");
  } finally { Close(s); }
 }
 static void TestLongAndLarge() {
  var s=Create();try {
   var record=Row(100,new Copy("zh-CN"),DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()+200000) with { Body=string.Concat(Enumerable.Repeat("完整历史消息正文。",600)) };
   s.Router.MessageStore!.Append(record);s.Window.Refresh();Find<TabControl>(s.Window,"messages.tabs").SelectedIndex=1;Pump();Find<ListBox>(s.Window,"messages.list").SelectedIndex=0;Pump();
   Check(Find<ScrollViewer>(s.Window,"messages.detailScroll").ScrollableHeight>0&&Find<TextBlock>(s.Window,"messages.detail.body").ActualHeight>200,"long detail is scrollable and wraps");
  } finally { Close(s); }
  var big=Create(count:10000);try { var list=Find<ListBox>(big.Window,"messages.list");Check(list.Items.Count==10000&&list.ItemContainerGenerator.ContainerFromIndex(9999)==null,"native virtualization does not materialize10k controls"); } finally { Close(big); }
 }
 static void RenderVariants() {
  var output=Environment.GetEnvironmentVariable("QUOTABAR_TEST_ARTIFACTS");if(output==null) return;Directory.CreateDirectory(output);
  foreach(var language in new[]{"zh-CN","zh-TW","en"}) foreach(var dark in new[]{false,true}) {
   var s=Create(language,dark);try {
    Find<TabControl>(s.Window,"messages.tabs").SelectedIndex=1;Pump();Find<ListBox>(s.Window,"messages.list").SelectedIndex=0;Pump();
    var content=(FrameworkElement)s.Window.Content;
    foreach(var tag in new[]{"messages.allRead","messages.tabs"}) { var control=Find<FrameworkElement>(s.Window,tag);var at=control.TransformToAncestor(content).Transform(new Point());Check(at.X>=-1&&at.X+control.ActualWidth<=content.ActualWidth+1,"translated toolbar fits "+language); }
    foreach(var scale in new[]{1.25,1.5,2d}) {
     var bitmap=new RenderTargetBitmap((int)Math.Ceiling(s.Window.ActualWidth*scale),(int)Math.Ceiling(s.Window.ActualHeight*scale),96*scale,96*scale,PixelFormats.Pbgra32);bitmap.Render(s.Window);
     var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var file=File.Create(Path.Combine(output,$"message-center-{language}-{dark}-{scale}.png"));encoder.Save(file);
    }
   } finally { Close(s); }
  }
 }
}
