using System.Text.Json;
using QuotaBar.Core;
static class NotificationPolicyTests {
 public static void Run() {
  var now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
  foreach(var dynamicMap in new[]{false,true}) {
   var p=NotificationPolicyPreferences.AllSelected();
   p.Rules[NotificationCategory.BankExpiring72h]=dynamicMap?[NotificationChannel.Mobile]:[NotificationChannel.Bubble];
   p.Rules[NotificationCategory.BankExpiring24h]=[NotificationChannel.Mobile];
   p=dynamicMap?p with { BankExpiryHours=[12],BankThresholdChannels=new() { [12]=[NotificationChannel.Bubble] } }:p.WithBankHours([72]);
   var original=p;
   p=p.WithBankHours([]);
   Check(p.BankChannelSelected(NotificationChannel.Bubble)==true&&p.BankChannelSelected(NotificationChannel.Mobile)==false,"empty Bank preserves current selection");
   p=NotificationPolicyPreferences.Decode(JsonSerializer.Serialize(p,NotificationPolicyPreferences.JsonOptions));
   Check(p.ConfiguredBankHours.Length==0&&p.BankThresholdChannels?.Count==0,"empty Bank mapping roundtrip");
   p=p.WithBankHours([12]);
   Check(p.BankChannels(12).SetEquals([NotificationChannel.Bubble]),"readded Bank inherits current selection without mobile expansion");
   Check(p.EnabledChannels.SetEquals(original.EnabledChannels),"clear/readd preserves masters");
   foreach(var category in Enum.GetValues<NotificationCategory>().Where(c=>c is not NotificationCategory.BankExpiring72h and not NotificationCategory.BankExpiring24h))
    Check(p.Rules[category].SetEquals(original.Rules[category]),"clear/readd preserves other rules");
   Check(original.Rules[NotificationCategory.BankExpiring24h].SetEquals([NotificationChannel.Mobile]),"clear does not mutate original rules");
  }

  var dynamicPolicy=new NotificationPolicyPreferences { LowRemainingThreshold=15,Rules=new() { [NotificationCategory.BankExpiring72h]=[NotificationChannel.Bubble],[NotificationCategory.BankExpiring24h]=[NotificationChannel.Mobile] } };
  Check(dynamicPolicy.ConfiguredLowThresholds.SequenceEqual(new[]{15})&&dynamicPolicy.ConfiguredBankHours.SequenceEqual(new[]{72,24}),"legacy scalar/hours fallback");
  Check(dynamicPolicy.BankChannelSelected(NotificationChannel.Bubble) is null&&dynamicPolicy.BankChannelSelected(NotificationChannel.Mobile) is null,"legacy split Bank mixed");
  dynamicPolicy=dynamicPolicy.WithBankHours(new[]{72,24,12}); Check(dynamicPolicy.BankChannels(12).Count==0,"added Bank uses intersection");
  dynamicPolicy=dynamicPolicy.WithBankHours(new[]{48,24,12},new Dictionary<int,int> { [48]=72 }); Check(dynamicPolicy.BankChannels(48).SetEquals(new[]{NotificationChannel.Bubble}),"edited Bank retains old channel");
  var oldMobile=dynamicPolicy.Rules.GetValueOrDefault(NotificationCategory.QuotaLow)?.Contains(NotificationChannel.Mobile)??false;
  dynamicPolicy=dynamicPolicy.SelectColumn(NotificationChannel.System);
  Check(dynamicPolicy.EnabledChannels.SetEquals(new[]{NotificationChannel.Bubble})&&dynamicPolicy.ConfiguredLowThresholds.SequenceEqual(new[]{15}),"column selection preserves master and thresholds");
  Check(dynamicPolicy.BankChannels(24).SetEquals(new[]{NotificationChannel.Mobile,NotificationChannel.System}),"column only changes its Bank channel");
  Check(NotificationPolicyPreferences.Decode(JsonSerializer.Serialize(dynamicPolicy,NotificationPolicyPreferences.JsonOptions)).BankChannels(48).SetEquals(dynamicPolicy.BankChannels(48)),"dynamic Bank map roundtrip");
  var defaultsRoundtrip=NotificationPolicyPreferences.Decode(JsonSerializer.Serialize(new NotificationPolicyPreferences(),NotificationPolicyPreferences.JsonOptions));
  Check(defaultsRoundtrip.ConfiguredLowThresholds.SequenceEqual(new[]{20})&&defaultsRoundtrip.ConfiguredBankHours.SequenceEqual(new[]{72,24}),"missing optional lists survive old-style roundtrip");
  var exact=NotificationPolicyPreferences.AllSelected() with { EnabledChannels=Enum.GetValues<NotificationChannel>().ToHashSet() };
  exact=exact.WithLowThresholds(new[]{30,20,10}).WithBankHours(new[]{72,24,12});
  var exactSnapshot=new NotificationDeliverySnapshot(NotificationCategory.BankExpiring72h,exact,now,12);
  exact=exact.WithBankHours(new[]{72,24}); exactSnapshot.Restrict(exact,now); exact=exact.WithBankHours(new[]{72,24,12});
  Check(!exactSnapshot.Allows(NotificationChannel.Bubble,exact,now),"removed threshold cannot gain eligibility again");
  exact=exact.WithLowThresholds(Array.Empty<int>()); Check(NotificationPolicy.Decision(NotificationCategory.QuotaLow,NotificationChannel.Bubble,exact,now,20)==NotificationDecision.RuleOff,"removed low threshold blocked");
  var malformed=NotificationPolicyPreferences.Decode("{\"schema\":1,\"enabledChannels\":[\"mobile\"],\"rules\":{\"bankExpiring72h\":[\"mobile\"]},\"bankExpiryHours\":\"bad\",\"lowRemainingThresholds\":null}");
  Check(malformed.ConfiguredBankHours.Length==0&&malformed.ConfiguredLowThresholds.Length==0,"malformed explicit lists fail closed");
  foreach(var value in new[]{1,15,99,0,100,-1}) {
   var decoded=NotificationPolicyPreferences.Decode(JsonSerializer.Serialize(new NotificationPolicyPreferences { LowRemainingThreshold=value },NotificationPolicyPreferences.JsonOptions));
   Check(decoded.LowRemainingThreshold==(value is >=1 and <=99?value:20),"custom threshold range and roundtrip");
  }
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
  var freshRoot=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString());
  try {
   var freshStore=new NotificationPolicyStore(Path.Combine(freshRoot,"policy.json")); var fresh=freshStore.LoadOrMigrate(null);
   Check(fresh.Rules.Count==6&&fresh.Rules.Values.All(c=>c.SetEquals(Enum.GetValues<NotificationChannel>())),"fresh install selects all18 rules");
   Check(fresh.EnabledChannels.SetEquals(new[]{NotificationChannel.Bubble}),"fresh masters remain independent");
   var edited=fresh with { Rules=new() { [NotificationCategory.QuotaLow]=[] },LowRemainingThreshold=15 }; freshStore.Save(edited);
   var restored=freshStore.LoadOrMigrate(null); Check(restored.Rules[NotificationCategory.QuotaLow].Count==0&&restored.LowRemainingThreshold==15,"fresh defaults do not override existing policy");
  } finally { if(Directory.Exists(freshRoot)) Directory.Delete(freshRoot,true); }
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
