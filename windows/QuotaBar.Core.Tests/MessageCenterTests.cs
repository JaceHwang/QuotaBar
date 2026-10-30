using System.Text.Json;
using QuotaBar.Core;
static class MessageCenterTests {
 static void Check(bool condition,string name) { if(!condition) throw new Exception(name); }
 static MessageCenterRecord Row(string id,long at=1900000000000,string generation="initial",string? epoch="one")=>new(new(id,generation,epoch),NotificationCategory.QuotaLow,"Quota low","15% snapshot",at,null,[NotificationChannel.Bubble]);
 public static void Run() {
  var root=Path.Combine(Path.GetTempPath(),"message-tests-"+Guid.NewGuid()); Directory.CreateDirectory(root); var path=Path.Combine(root,"message-center.json");
  try {
   File.Copy(Path.Combine(AppContext.BaseDirectory,"contracts/notifications/message-center-cases.json"),path);
   var store=new MessageCenterStore(path); Check(store.Error is null&&store.Records.Count==3&&store.UnreadCount==2,"shared fixture");
   var original=store.Records.Single(r=>r.Key.Id=="low");
   Check(store.Append(original with { Body="not original snapshot",Channels=[NotificationChannel.Mobile] }),"duplicate merge save");
   var kept=store.Records.Single(r=>r.Key.Id=="low");
   Check(kept.Body==original.Body&&kept.Channels.SetEquals([NotificationChannel.Bubble,NotificationChannel.System,NotificationChannel.Mobile])&&kept.ReadAtMilliseconds==original.ReadAtMilliseconds,"immutable snapshot and read with merged channels");
   Check(store.MarkAllRead(1900000010000)&&new MessageCenterStore(path).UnreadCount==0,"read restart");
   using(var doc=JsonDocument.Parse(File.ReadAllText(path))) Check(!doc.RootElement.GetProperty("messages")[0].TryGetProperty("createdAt",out _),"wire times are UTC milliseconds only");
   File.Delete(path); store=new(path); var a=Row("same",1600000000000);var b=Row("same",generation:"later");var c=Row("same",epoch:"two");
   Check(store.Append([a,b,c])&&store.UnreadCount==3,"generation and epoch distinct");
   Check(store.MarkRead(a.Key,1900000001000)&&store.Append(a)&&store.UnreadCount==2,"repeated capture cannot unread");
   Check(new MessageCenterStore(path).Records.Count==3&&new MessageCenterStore(path).Records.Last().Key==a.Key,"old history not pruned");
   File.WriteAllText(path,"{broken history"); store=new(path); Check(store.Error!=null&&!store.Append(Row("pending"))&&store.HasUnpersistedMessages,"corrupt load volatile overlay");
   Check(!store.MarkRead(Row("pending").Key,1900000010000)&&store.UnreadCount==1&&File.ReadAllText(path)=="{broken history","unread file not overwritten");
   File.WriteAllText(path,"{\"schema\":1,\"messages\":[]}"); Check(store.Reload()&&!store.HasUnpersistedMessages&&new MessageCenterStore(path).UnreadCount==1,"reload merge pending");
   var saved=File.ReadAllText(path); File.Delete(path); Directory.CreateDirectory(path);
   Check(!store.MarkAllRead(1900000010000)&&store.UnreadCount==1,"write failure keeps read status");
   Check(!store.Append(Row("new"))&&store.Records.Count==2,"pending while write unavailable");
   Directory.Delete(path); File.WriteAllText(path,saved); Check(store.Reload()&&new MessageCenterStore(path).Records.Count==2,"retry preserves disk and pending");
   File.Delete(path);store=new(path);Check(store.Append(Enumerable.Range(0,10000).Select(i=>Row(i.ToString(),1600000000000+i)).ToArray()),"bulk10k save");
   Check(new MessageCenterStore(path).Records.Count==10000&&store.MarkAllRead(1900000000000)&&new MessageCenterStore(path).UnreadCount==0,"10k history/read restart");
   File.WriteAllText(path,"{\"schema\":999,\"messages\":[]}");store=new(path);Check(store.Error!=null&&!store.Append(Row("new"))&&File.ReadAllText(path).Contains("999"),"future schema preserved");
  } finally { Directory.Delete(root,true); }
  Console.WriteLine("PASS persistent message archive contract, read/restart, corrupt/write recovery and10000 records");
 }
}
