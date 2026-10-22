using System.Text.Json;
using System.Text.Json.Serialization;
namespace QuotaBar.Core;
[JsonConverter(typeof(NotificationDeliveryModeConverter))]
public enum NotificationDeliveryMode { Bubble,System,Both,Off }
public sealed class NotificationDeliveryModeConverter : JsonConverter<NotificationDeliveryMode> {
    public override NotificationDeliveryMode Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options) {
        if(reader.TokenType==JsonTokenType.Number && reader.TryGetInt32(out var n) && Enum.IsDefined(typeof(NotificationDeliveryMode),n)) return (NotificationDeliveryMode)n;
        if(reader.TokenType==JsonTokenType.String && Enum.TryParse<NotificationDeliveryMode>(reader.GetString(),true,out var mode) && Enum.IsDefined(mode)) return mode;
        reader.Skip(); return NotificationDeliveryMode.Bubble;
    }
    public override void Write(Utf8JsonWriter writer,NotificationDeliveryMode value,JsonSerializerOptions options)=>writer.WriteNumberValue((int)value);
}
public sealed record NotificationPresentationPreferences {
    public int Schema { get; init; }=1;
    public NotificationDeliveryMode Mode { get; init; }=NotificationDeliveryMode.Bubble;
    public DateTimeOffset? PausedUntil { get; init; }
    public bool UsesBubble=>Mode is NotificationDeliveryMode.Bubble or NotificationDeliveryMode.Both;
    public bool UsesSystem=>Mode is NotificationDeliveryMode.System or NotificationDeliveryMode.Both;
    public bool Paused(DateTimeOffset now)=>PausedUntil>now;
    public NotificationPresentationPreferences Validated()=>Schema==1&&Enum.IsDefined(Mode)?this:new();
}
public sealed record NotificationUnreadItem(ExperienceNotification Message,bool Stale);
public sealed class NotificationPresentationState {
    sealed class Entry(ExperienceNotification message,bool deferred) {
        public ExperienceNotification Message=message; public bool Deferred=deferred,Presented,Read;
    }
    readonly List<Entry> entries=[];
    public string? ActiveId { get; private set; }
    QuotaObservation? quotaBaseline;
    bool stopped;
    public void Enqueue(ExperienceNotification m,bool canPresent,DateTimeOffset now) {
        if(stopped||entries.Any(e=>e.Message.Id==m.Id)) return;
        Prune(now); entries.Add(new(m,!canPresent));
        if(entries.Count>32) { var worst=entries.Where(e=>e.Message.Id!=ActiveId).Max(e=>e.Message.Kind); entries.Remove(entries.First(e=>e.Message.Id!=ActiveId&&e.Message.Kind==worst)); }
    }
    public ExperienceNotification? Next(bool canPresent,DateTimeOffset now) {
        Prune(now); if(stopped||!canPresent||ActiveId!=null) return null;
        var e=entries.Where(e=>!e.Deferred&&!e.Presented&&!e.Read&&e.Message.Valid(now)).OrderBy(e=>e.Message.Kind).FirstOrDefault();
        if(e==null) return null;
        ActiveId=e.Message.Id; return e.Message;
    }
    public void Shown(string id,DateTimeOffset now) { if(ActiveId!=id) return; var e=entries.FirstOrDefault(e=>e.Message.Id==id); if(e!=null) { e.Presented=true; } }
    public void Dismiss(string id,bool read) { var e=entries.FirstOrDefault(e=>e.Message.Id==id); if(e!=null) { e.Read|=read; e.Deferred=true; } if(ActiveId==id) { ActiveId=null; } }
    public void SetInteracting(bool value,DateTimeOffset now) { }
    public bool Tick(DateTimeOffset now) { Prune(now); return false; }
    public bool ObserveQuota(QuotaObservation observation,DateTimeOffset now) {
        if(stopped||observation.Source!=ObservationSource.FullRead||(now-observation.ReceivedAt).TotalSeconds is < -5 or >120||!double.IsFinite(observation.Quota.Primary.UsedPercent)||observation.Quota.Primary.UsedPercent<0||observation.Quota.Secondary is { } secondary&&(!double.IsFinite(secondary.UsedPercent)||secondary.UsedPercent<0)) return false;
        var previous=quotaBaseline;
        if(previous?.Epoch==observation.Epoch&&(observation.Sequence<=previous.Sequence||observation.ReceivedAt<previous.ReceivedAt)) return false;
        var changed=previous?.Epoch==observation.Epoch&&(previous.Quota.Primary.UsedPercent!=observation.Quota.Primary.UsedPercent||(previous.Quota.Secondary is { } old&&observation.Quota.Secondary is { } current&&old.UsedPercent!=current.UsedPercent));
        quotaBaseline=observation with { Quota=observation.Quota with { Secondary=observation.Quota.Secondary??(previous?.Epoch==observation.Epoch?previous.Quota.Secondary:null) } };
        if(!changed||ActiveId is not { } id) return false;
        Dismiss(id,false); return true;
    }
    public void Suspend() { if(ActiveId is { } id) Dismiss(id,false); }
    public void Forget(string id) { if(ActiveId==id) Suspend(); entries.RemoveAll(e=>e.Message.Id==id); }
    public void Cancel(string epoch) { if(entries.Any(e=>e.Message.Id==ActiveId&&e.Message.Epoch==epoch)) Suspend(); entries.RemoveAll(e=>e.Message.Epoch==epoch); }
    public IReadOnlyList<NotificationUnreadItem> Unread(DateTimeOffset now) { Prune(now); return entries.Where(e=>!e.Read).Reverse().Select(e=>new NotificationUnreadItem(e.Message,!e.Message.Valid(now))).ToArray(); }
    public void Stop() { Suspend(); entries.Clear(); stopped=true; }
    void Prune(DateTimeOffset now) { entries.RemoveAll(e=>e.Message.Id!=ActiveId&&now-e.Message.CreatedAt>TimeSpan.FromHours(24)); }
}
