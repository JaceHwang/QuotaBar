using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Nodes;
namespace QuotaBar.Core;
public enum NotificationCategory { QuotaRecovered,BankExpiring72h,BankExpiring24h,UpdateAvailable,QuotaLow,QuotaExhausted }
public enum NotificationChannel { Bubble,System,Mobile }
public enum NotificationDecision { Allowed,RuleOff,ChannelOff,Paused }
public sealed record NotificationPolicyPreferences {
 [JsonIgnore] public bool RecoveredInvalidData { get; init; }
 public int Schema { get; init; }=1;
 public HashSet<NotificationChannel> EnabledChannels { get; init; }=[NotificationChannel.Bubble];
 public Dictionary<NotificationCategory,HashSet<NotificationChannel>> Rules { get; init; }=Enum.GetValues<NotificationCategory>().ToDictionary(c=>c,c=>c is NotificationCategory.QuotaRecovered or NotificationCategory.BankExpiring72h or NotificationCategory.BankExpiring24h?new HashSet<NotificationChannel>{NotificationChannel.Bubble}:[]);
 public int LowRemainingThreshold { get; init; }=20;
 [JsonIgnore(Condition=JsonIgnoreCondition.WhenWritingNull)] public int[]? LowRemainingThresholds { get; init; }
 [JsonIgnore(Condition=JsonIgnoreCondition.WhenWritingNull)] public int[]? BankExpiryHours { get; init; }
 [JsonIgnore(Condition=JsonIgnoreCondition.WhenWritingNull)] public Dictionary<int,HashSet<NotificationChannel>>? BankThresholdChannels { get; init; }
 public static int[] Normalize(IEnumerable<int> values,int min,int max)=>values.Where(v=>v>=min&&v<=max).Distinct().OrderDescending().Take(32).ToArray();
 [JsonIgnore] public int[] ConfiguredLowThresholds=>Normalize(LowRemainingThresholds??[LowRemainingThreshold],1,99);
 [JsonIgnore] public int[] ConfiguredBankHours=>Normalize(BankExpiryHours??[72,24],1,8760);
 public HashSet<NotificationChannel> BankChannels(int hours)=>BankThresholdChannels is {} mapping?(mapping.TryGetValue(hours,out var mapped)?new(mapped):[]):Rules.TryGetValue(hours==24?NotificationCategory.BankExpiring24h:NotificationCategory.BankExpiring72h,out var channels)?new(channels):[];
 IEnumerable<HashSet<NotificationChannel>> BankSets()=>ConfiguredBankHours.Length>0?ConfiguredBankHours.Select(BankChannels):new[]{Rules.GetValueOrDefault(NotificationCategory.BankExpiring72h)??[],Rules.GetValueOrDefault(NotificationCategory.BankExpiring24h)??[]};
 [JsonIgnore] public HashSet<NotificationChannel> CommonBankChannels { get { var common=Enum.GetValues<NotificationChannel>().ToHashSet(); foreach(var set in BankSets()) common.IntersectWith(set); return common; } }
 public bool? BankChannelSelected(NotificationChannel channel) { var sets=BankSets().ToArray(); var count=sets.Count(s=>s.Contains(channel)); return count==0?false:count==sets.Length?true:null; }
 public NotificationPolicyPreferences WithLowThresholds(IEnumerable<int> values) { var normalized=Normalize(values,1,99); return this with { LowRemainingThresholds=normalized,LowRemainingThreshold=normalized.FirstOrDefault(LowRemainingThreshold) }; }
 public NotificationPolicyPreferences WithBankHours(IEnumerable<int> values,IReadOnlyDictionary<int,int>? retainingChannelsFrom=null) {
  var hours=Normalize(values,1,8760); var old=ConfiguredBankHours.ToHashSet(); var inherited=CommonBankChannels;
  var rules=Rules;
  if(hours.Length==0) {
   rules=Rules.ToDictionary(r=>r.Key,r=>new HashSet<NotificationChannel>(r.Value));
   rules[NotificationCategory.BankExpiring72h]=new(inherited); rules[NotificationCategory.BankExpiring24h]=new(inherited);
  }
  return this with { Rules=rules,BankExpiryHours=hours,BankThresholdChannels=hours.ToDictionary(h=>h,h=>retainingChannelsFrom is {} aliases&&aliases.TryGetValue(h,out var source)?BankChannels(source):old.Contains(h)?BankChannels(h):new HashSet<NotificationChannel>(inherited)) };
 }
 public NotificationPolicyPreferences WithBankChannel(NotificationChannel channel,bool enabled) {
  var mapping=ConfiguredBankHours.ToDictionary(h=>h,BankChannels); foreach(var set in mapping.Values) { if(enabled) set.Add(channel); else set.Remove(channel); }
  var rules=Rules.ToDictionary(r=>r.Key,r=>new HashSet<NotificationChannel>(r.Value)); foreach(var category in new[]{NotificationCategory.BankExpiring72h,NotificationCategory.BankExpiring24h}) { if(!rules.TryGetValue(category,out var set)) rules[category]=set=[]; if(enabled) set.Add(channel); else set.Remove(channel); }
  return this with { Rules=rules,BankThresholdChannels=mapping };
 }
 public NotificationPolicyPreferences ToggleColumn(NotificationChannel channel) {
  var enabled=!(Enum.GetValues<NotificationCategory>().Where(c=>c is not NotificationCategory.BankExpiring72h and not NotificationCategory.BankExpiring24h).All(c=>Rules.GetValueOrDefault(c)?.Contains(channel)==true)&&BankChannelSelected(channel)==true);
  var rules=Rules.ToDictionary(r=>r.Key,r=>new HashSet<NotificationChannel>(r.Value));
  foreach(var category in Enum.GetValues<NotificationCategory>()) { if(!rules.TryGetValue(category,out var set)) rules[category]=set=[]; if(enabled) set.Add(channel); else set.Remove(channel); }
  return (this with { Rules=rules }).WithBankChannel(channel,enabled);
 }
 public NotificationPolicyPreferences SelectColumn(NotificationChannel channel) { var rules=Rules.ToDictionary(r=>r.Key,r=>new HashSet<NotificationChannel>(r.Value)); foreach(var category in Enum.GetValues<NotificationCategory>()) { if(!rules.TryGetValue(category,out var set)) rules[category]=set=[]; set.Add(channel); } return (this with { Rules=rules }).WithBankChannel(channel,true); }
 public DateTimeOffset? BubblePausedUntil { get; init; }
 public static NotificationPolicyPreferences AllSelected()=>new() { Rules=Enum.GetValues<NotificationCategory>().ToDictionary(c=>c,c=>Enum.GetValues<NotificationChannel>().ToHashSet()) };
 public static JsonSerializerOptions JsonOptions { get; }=new() { PropertyNamingPolicy=JsonNamingPolicy.CamelCase,Converters={new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)} };
 public static NotificationPolicyPreferences Decode(string json) {
  try {
   using var doc=JsonDocument.Parse(json);
   if(!doc.RootElement.TryGetProperty("schema",out var schema)||schema.GetInt32()!=1||!doc.RootElement.TryGetProperty("enabledChannels",out _)||!doc.RootElement.TryGetProperty("rules",out _)) return Safe();
   var legacy=JsonNode.Parse(json)!.AsObject(); legacy.Remove("lowRemainingThresholds"); legacy.Remove("bankExpiryHours"); legacy.Remove("bankThresholdChannels");
   var p=JsonSerializer.Deserialize<NotificationPolicyPreferences>(legacy.ToJsonString(),JsonOptions);
   if(p?.EnabledChannels is null||p.Rules is null||p.Rules.Any(r=>r.Value is null)) return Safe();
   return p with { LowRemainingThreshold=p.LowRemainingThreshold is >=1 and <=99?p.LowRemainingThreshold:20,LowRemainingThresholds=ReadThresholds(doc.RootElement,"lowRemainingThresholds",1,99),BankExpiryHours=ReadThresholds(doc.RootElement,"bankExpiryHours",1,8760),BankThresholdChannels=ReadBankChannels(doc.RootElement) };
  } catch(Exception e) when(e is JsonException or InvalidOperationException or FormatException or OverflowException) { return Safe(); }
 }
 static int[]? ReadThresholds(JsonElement root,string name,int min,int max) {
  if(!root.TryGetProperty(name,out var field)) return null;
  if(field.ValueKind!=JsonValueKind.Array) return [];
  var values=field.EnumerateArray().ToArray(); if(values.Any(e=>e.ValueKind!=JsonValueKind.Number||!e.TryGetInt32(out _))) return [];
  return Normalize(values.Select(e=>e.GetInt32()),min,max);
 }
 static Dictionary<int,HashSet<NotificationChannel>>? ReadBankChannels(JsonElement root) {
  if(!root.TryGetProperty("bankThresholdChannels",out var field)) return null;
  var result=new Dictionary<int,HashSet<NotificationChannel>>(); if(field.ValueKind!=JsonValueKind.Object) return result;
  foreach(var property in field.EnumerateObject()) {
   if(!int.TryParse(property.Name,out var hours)) return [];
   if(hours<1||hours>8760) continue;
   if(property.Value.ValueKind!=JsonValueKind.Array) return [];
   var set=new HashSet<NotificationChannel>();
   foreach(var value in property.Value.EnumerateArray()) {
    if(value.ValueKind!=JsonValueKind.String) return [];
    var channel=value.GetString() switch { "bubble"=>NotificationChannel.Bubble,"system"=>NotificationChannel.System,"mobile"=>NotificationChannel.Mobile,_=>(NotificationChannel?)null };
    if(channel is not {} known) return []; set.Add(known);
   }
   result[hours]=set;
  }
  return result;
 }
 static NotificationPolicyPreferences Safe()=>new() { EnabledChannels=[],Rules=[],RecoveredInvalidData=true };
}
public static class NotificationPolicy {
 public static NotificationDecision Decision(NotificationCategory category,NotificationChannel channel,NotificationPolicyPreferences preferences,DateTimeOffset now,int? threshold=null) {
  if(category==NotificationCategory.QuotaLow&&threshold is {} low&&!preferences.ConfiguredLowThresholds.Contains(low)) return NotificationDecision.RuleOff;
  HashSet<NotificationChannel>? channels;
  if((category is NotificationCategory.BankExpiring72h or NotificationCategory.BankExpiring24h)&&threshold is {} hours) {
   if(!preferences.ConfiguredBankHours.Contains(hours)) return NotificationDecision.RuleOff; channels=preferences.BankChannels(hours);
  } else channels=preferences.Rules.GetValueOrDefault(category);
  if(channels is null||!channels.Contains(channel)) return NotificationDecision.RuleOff;
  if(!preferences.EnabledChannels.Contains(channel)) return NotificationDecision.ChannelOff;
  return channel==NotificationChannel.Bubble&&preferences.BubblePausedUntil is {} until&&now<until?NotificationDecision.Paused:NotificationDecision.Allowed;
 }
 public static int Priority(NotificationCategory category)=>category switch { NotificationCategory.QuotaExhausted=>0,NotificationCategory.QuotaLow=>1,NotificationCategory.QuotaRecovered=>2,NotificationCategory.UpdateAvailable=>4,_=>3 };
}

public sealed record LegacyNotificationPreferences(NotificationDeliveryMode Mode,bool Recovery,bool Celebration,bool Bank,bool UpdatesReminders,bool BarkEnabled,DateTimeOffset? PausedUntil=null);
public static class NotificationPolicyMigration {
 public static NotificationPolicyPreferences Migrate(LegacyNotificationPreferences legacy) {
  HashSet<NotificationChannel> channels=[];
  if(legacy.Mode is NotificationDeliveryMode.Bubble or NotificationDeliveryMode.Both) channels.Add(NotificationChannel.Bubble);
  if(legacy.Mode is NotificationDeliveryMode.System or NotificationDeliveryMode.Both) channels.Add(NotificationChannel.System);
  if(legacy.BarkEnabled) channels.Add(NotificationChannel.Mobile);
  var rules=Enum.GetValues<NotificationCategory>().ToDictionary(c=>c,_=>new HashSet<NotificationChannel>());
  foreach(var category in new[]{NotificationCategory.QuotaRecovered,NotificationCategory.BankExpiring72h,NotificationCategory.BankExpiring24h,NotificationCategory.UpdateAvailable}) {
   var enabled=category switch { NotificationCategory.QuotaRecovered=>legacy.Recovery||legacy.Celebration,NotificationCategory.UpdateAvailable=>legacy.UpdatesReminders,_=>legacy.Bank };
   if(enabled) rules[category]=new(channels);
  }
  return new() { EnabledChannels=channels,Rules=rules,BubblePausedUntil=legacy.PausedUntil };
 }
}
