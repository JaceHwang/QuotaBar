using System.Text.Json;
using QuotaBar.Core;
static class NotificationPolicyTests {
 public static void Run() {
  var now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
  using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/notifications/matrix-cases.json")));
  foreach(var row in doc.RootElement.EnumerateArray()) {
   var category=Enum.Parse<NotificationCategory>(row.GetProperty("category").GetString()!,true);
   var selected=Enum.Parse<NotificationChannel>(row.GetProperty("selected").GetString()!,true);
   var channel=Enum.Parse<NotificationChannel>(row.GetProperty("channel").GetString()!,true);
   var p=new NotificationPolicyPreferences { EnabledChannels=Enum.GetValues<NotificationChannel>().ToHashSet(), Rules=new() { [category]=[selected] } };
   Check(NotificationPolicy.Decision(category,channel,p,now).ToString().Equals(row.GetProperty("expected").GetString(),StringComparison.OrdinalIgnoreCase),"matrix");
   p=p with { BubblePausedUntil=now.AddSeconds(1) };
   if(selected==channel) Check(NotificationPolicy.Decision(category,channel,p,now)==(channel==NotificationChannel.Bubble?NotificationDecision.Paused:NotificationDecision.Allowed),"pause only bubble");
   Check(NotificationPolicy.Decision(category,channel,p,now.AddSeconds(1)).ToString().Equals(row.GetProperty("expected").GetString(),StringComparison.OrdinalIgnoreCase),"pause boundary");
  }
  var message=new ExperienceNotification("low",ExperienceNotificationKind.Recovery,"a","x","x",now,Category:NotificationCategory.QuotaLow);
  Check(message.Category==NotificationCategory.QuotaLow&&message.Priority==1,"event classification separate from kind");
  using var migration=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/notifications/migration-cases.json")));
  foreach(var row in migration.RootElement.EnumerateArray()) {
   var legacy=new LegacyNotificationPreferences(Enum.Parse<NotificationDeliveryMode>(row.GetProperty("mode").GetString()!,true),row.GetProperty("recovery").GetBoolean(),row.GetProperty("celebration").GetBoolean(),row.GetProperty("bank").GetBoolean(),row.GetProperty("updates").GetBoolean(),row.GetProperty("mobile").GetBoolean());
   var p=NotificationPolicyMigration.Migrate(legacy);
   var channels=row.GetProperty("channels").EnumerateArray().Select(x=>Enum.Parse<NotificationChannel>(x.GetString()!,true)).ToHashSet();
   Check(p.EnabledChannels.SetEquals(channels),"migrated channels");
   Check(p.Rules[NotificationCategory.QuotaRecovered].SetEquals(legacy.Recovery||legacy.Celebration?channels:[]),"migrated implicit celebration");
   Check(p.Rules[NotificationCategory.BankExpiring24h].SetEquals(legacy.Bank?channels:[]),"migrated bank");
   Check(p.Rules[NotificationCategory.UpdateAvailable].SetEquals(legacy.UpdatesReminders?channels:[]),"migrated updates");
   Check(p.Rules[NotificationCategory.QuotaLow].Count==0&&p.Rules[NotificationCategory.QuotaExhausted].Count==0,"new alerts off");
  }
  var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root);
  try {
   var path=Path.Combine(root,"policy.json"); var store=new NotificationPolicyStore(path);
   var old=new LegacyNotificationPreferences(NotificationDeliveryMode.Both,true,false,true,true,true);
   var first=store.LoadOrMigrate(old);
   Check(first.EnabledChannels.Contains(NotificationChannel.Mobile),"persist migrated mobile");
   Check(store.LoadOrMigrate(old with { BarkEnabled=false }).EnabledChannels.Contains(NotificationChannel.Mobile),"migration runs once");
   File.WriteAllText(path,"broken"); Check(store.LoadOrMigrate(old).EnabledChannels.Count==0&&File.ReadAllText(path)=="broken","corrupt evidence preserved");
   File.WriteAllText(path,"{\"schema\":1,\"enabledChannels\":null,\"rules\":{}}");
   Check(store.LoadOrMigrate(old).EnabledChannels.Count==0&&store.Corrupted,"malformed current schema is reported");
   var blocker=Path.Combine(root,"file"); File.WriteAllText(blocker,""); var threw=false;
   try { new NotificationPolicyStore(Path.Combine(blocker,"policy.json")).LoadOrMigrate(old); } catch(IOException) { threw=true; }
   Check(threw,"migration write failure propagates for legacy fallback");
  } finally { Directory.Delete(root,true); }
  var policy=new NotificationPolicyPreferences { EnabledChannels=[NotificationChannel.Bubble,NotificationChannel.Mobile] };
  policy.Rules[NotificationCategory.QuotaRecovered]=[NotificationChannel.Bubble,NotificationChannel.Mobile];
  var snapshot=new NotificationDeliverySnapshot(NotificationCategory.QuotaRecovered,policy,now);
  snapshot.RecordAccepted(NotificationChannel.Bubble);
  Check(snapshot.Allows(NotificationChannel.Mobile,policy,now)&&!snapshot.Allows(NotificationChannel.Bubble,policy,now),"independent receipts");
  policy=policy with { EnabledChannels=[NotificationChannel.Bubble] }; snapshot.Restrict(policy,now);
  policy=policy with { EnabledChannels=[NotificationChannel.Bubble,NotificationChannel.Mobile] };
  Check(!snapshot.Allows(NotificationChannel.Mobile,policy,now),"reopen cannot replay");
  var priorityQueue=new ExperienceNotificationQueue(); var presentation=new NotificationPresentationState();
  foreach(var category in new[]{NotificationCategory.UpdateAvailable,NotificationCategory.QuotaLow,NotificationCategory.QuotaExhausted}) {
   var m=new ExperienceNotification(category.ToString(),ExperienceNotificationKind.Recovery,"a","x","",now,Category:category);
   priorityQueue.Enqueue(m); presentation.Enqueue(m,true,now);
  }
  Check(priorityQueue.Next(now)?.Category==NotificationCategory.QuotaExhausted&&presentation.Next(true,now)?.Category==NotificationCategory.QuotaExhausted,"actual queues use category priority");
  var defaults=new NotificationPolicyPreferences();
  Check(defaults.Rules[NotificationCategory.QuotaRecovered].SetEquals([NotificationChannel.Bubble]),"default recovery");
  Check(defaults.Rules[NotificationCategory.UpdateAvailable].Count==0,"default update off");
  Check(NotificationPolicyPreferences.Decode("{\"schema\":99,\"enabledChannels\":[\"mobile\"]}").EnabledChannels.Count==0,"unknown schema safe");
 }
 static void Check(bool ok,string message) { if(!ok) throw new Exception(message); }
}
