using System.Text.Json;
using System.Text.Json.Serialization;
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
 public DateTimeOffset? BubblePausedUntil { get; init; }
 public static JsonSerializerOptions JsonOptions { get; }=new() { PropertyNamingPolicy=JsonNamingPolicy.CamelCase,Converters={new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)} };
 public static NotificationPolicyPreferences Decode(string json) {
  try {
   using var doc=JsonDocument.Parse(json);
   if(!doc.RootElement.TryGetProperty("schema",out var schema)||schema.GetInt32()!=1||!doc.RootElement.TryGetProperty("enabledChannels",out _)||!doc.RootElement.TryGetProperty("rules",out _)) return Safe();
   var p=JsonSerializer.Deserialize<NotificationPolicyPreferences>(json,JsonOptions);
   if(p?.EnabledChannels is null||p.Rules is null||p.Rules.Any(r=>r.Value is null)) return Safe();
   return p with { LowRemainingThreshold=p.LowRemainingThreshold is 10 or 20 or 30?p.LowRemainingThreshold:20 };
  } catch(Exception e) when(e is JsonException or InvalidOperationException or FormatException or OverflowException) { return Safe(); }
 }
 static NotificationPolicyPreferences Safe()=>new() { EnabledChannels=[],Rules=[],RecoveredInvalidData=true };
}
public static class NotificationPolicy {
 public static NotificationDecision Decision(NotificationCategory category,NotificationChannel channel,NotificationPolicyPreferences preferences,DateTimeOffset now) {
  if(!preferences.Rules.TryGetValue(category,out var channels)||!channels.Contains(channel)) return NotificationDecision.RuleOff;
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
