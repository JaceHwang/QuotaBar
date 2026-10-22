namespace QuotaBar.Core;
public enum NotificationDeliveryMode { Bubble,System,Both,Off }
public sealed record NotificationPresentationPreferences {
    public NotificationDeliveryMode Mode { get; init; }=NotificationDeliveryMode.Bubble;
    public DateTimeOffset? PausedUntil { get; init; }
    public bool UsesBubble=>Mode is NotificationDeliveryMode.Bubble or NotificationDeliveryMode.Both;
    public bool UsesSystem=>Mode is NotificationDeliveryMode.System or NotificationDeliveryMode.Both;
    public bool Paused(DateTimeOffset now)=>PausedUntil>now;
    public NotificationPresentationPreferences Validated()=>Enum.IsDefined(Mode)?this:this with { Mode=NotificationDeliveryMode.Bubble };
}
public sealed record NotificationUnreadItem(ExperienceNotification Message,bool Stale);
public sealed class NotificationPresentationState {
    sealed class Entry(ExperienceNotification message,bool deferred) {
        public ExperienceNotification Message=message; public bool Deferred=deferred,Presented,Read;
    }
    readonly List<Entry> entries=[];
    public string? ActiveId { get; private set; }
    DateTimeOffset? deadline;
    TimeSpan remaining;
    bool interacting,stopped;
    public void Enqueue(ExperienceNotification m,bool canPresent,DateTimeOffset now) {
        if(stopped||entries.Any(e=>e.Message.Id==m.Id)) return;
        Prune(now); entries.Add(new(m,!canPresent));
        if(entries.Count>32) { var worst=entries.Where(e=>e.Message.Id!=ActiveId).Max(e=>e.Message.Kind); entries.Remove(entries.First(e=>e.Message.Id!=ActiveId&&e.Message.Kind==worst)); }
    }
    public ExperienceNotification? Next(bool canPresent,DateTimeOffset now) {
        Prune(now); if(stopped||!canPresent||ActiveId!=null) return null;
        var e=entries.Where(e=>!e.Deferred&&!e.Presented&&!e.Read&&e.Message.Valid(now)).OrderBy(e=>e.Message.Kind).FirstOrDefault();
        if(e==null) return null;
        ActiveId=e.Message.Id; remaining=TimeSpan.FromSeconds(e.Message.Kind is ExperienceNotificationKind.Bank or ExperienceNotificationKind.Update?10:6); deadline=null; interacting=false; return e.Message;
    }
    public void Shown(string id,DateTimeOffset now) { if(ActiveId!=id) return; var e=entries.FirstOrDefault(e=>e.Message.Id==id); if(e!=null) { e.Presented=true; deadline=now+remaining; } }
    public void Dismiss(string id,bool read) { var e=entries.FirstOrDefault(e=>e.Message.Id==id); if(e!=null) { e.Read|=read; e.Deferred=true; } if(ActiveId==id) { ActiveId=null; deadline=null; interacting=false; } }
    public void SetInteracting(bool value,DateTimeOffset now) { if(ActiveId==null||interacting==value) return; if(value) { if(deadline is { } d) remaining=d>now?d-now:TimeSpan.Zero; deadline=null; } else deadline=now+remaining; interacting=value; }
    public bool Tick(DateTimeOffset now) { Prune(now); if(ActiveId is not string id||deadline is not { } d||now<d) return false; Dismiss(id,false); return true; }
    public void Suspend() { if(ActiveId is { } id) Dismiss(id,false); }
    public void Cancel(string epoch) { if(entries.Any(e=>e.Message.Id==ActiveId&&e.Message.Epoch==epoch)) Suspend(); entries.RemoveAll(e=>e.Message.Epoch==epoch); }
    public IReadOnlyList<NotificationUnreadItem> Unread(DateTimeOffset now) { Prune(now); return entries.Where(e=>!e.Read).Reverse().Select(e=>new NotificationUnreadItem(e.Message,!e.Message.Valid(now))).ToArray(); }
    public void Stop() { Suspend(); entries.Clear(); stopped=true; }
    void Prune(DateTimeOffset now) { if(entries.Any(e=>e.Message.Id==ActiveId&&now-e.Message.CreatedAt>TimeSpan.FromHours(24))) Suspend(); entries.RemoveAll(e=>now-e.Message.CreatedAt>TimeSpan.FromHours(24)); }
}
