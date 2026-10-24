namespace QuotaBar.Core;
public sealed record QuotaWarningPeriodState {
 public DateTimeOffset ResetAnchor { get; init; }
 public int WindowMinutes { get; init; }
 public bool LowNotified { get; set; }
 public bool ExhaustionNotified { get; set; }
 public int Incident { get; set; }
}
public sealed record QuotaWarningState {
 public int Schema { get; init; }=1;
 public string Epoch { get; set; }="";
 public string Plan { get; set; }="";
 public int Threshold { get; set; }=20;
 public Dictionary<string,QuotaWarningPeriodState> Periods { get; set; }=[];
}
public sealed record QuotaWarningEvent(NotificationCategory Category,IReadOnlyList<string> PeriodIDs,int Threshold,string IncidentID);
public sealed class QuotaWarningEngine {
 public QuotaWarningState State { get; private set; }
 readonly Dictionary<string,double> previous=[];
 long sequence=-1;
 DateTimeOffset? receivedAt;
 public QuotaWarningEngine(QuotaWarningState? state=null) { State=state is { Schema:1,Periods.Count:<=2 }?state:new(); }
 public void ResetBaseline() { previous.Clear(); sequence=-1; receivedAt=null; }
 public void ConfirmRecovery(IEnumerable<string> periodIDs) { foreach(var id in periodIDs) if(State.Periods.TryGetValue(id,out var p)) p.ExhaustionNotified=false; }
 public IReadOnlyList<QuotaWarningEvent> Observe(QuotaObservation o,int threshold,DateTimeOffset now) {
  if(o.Source!=ObservationSource.FullRead||(now-o.ReceivedAt).TotalSeconds is < -5 or >120) return [];
  if(State.Epoch!=o.Epoch) { State=new() { Epoch=o.Epoch }; ResetBaseline(); }
  if(o.Sequence<=sequence||receivedAt is {} last&&o.ReceivedAt<last) return [];
  sequence=o.Sequence; receivedAt=o.ReceivedAt;
  var windows=new (string Id,QuotaWindow? Window)[]{("primary",o.Quota.Primary),("secondary",o.Quota.Secondary)};
  var plan=o.Quota.Plan?.Trim();
  if(string.IsNullOrEmpty(plan)||windows.Where(w=>w.Window!=null).Any(w=>!double.IsFinite(w.Window!.UsedPercent)||w.Window.UsedPercent is <0 or >100||w.Window.WindowMinutes is null or <=0)) { previous.Clear(); return []; }
  if(State.Plan!=plan) { State.Periods.Clear(); previous.Clear(); State.Plan=plan; }
  threshold=threshold is 10 or 20 or 30?threshold:20;
  if(State.Threshold!=threshold) { State.Threshold=threshold; previous.Clear(); }
  Dictionary<NotificationCategory,List<string>> groups=[],identities=[];
  foreach(var (id,window) in windows) {
   if(window is null) { previous.Remove(id); continue; }
   var remaining=100-window.UsedPercent; var minutes=window.WindowMinutes!.Value;
   var period=State.Periods.TryGetValue(id,out var oldPeriod)?oldPeriod:new() { ResetAnchor=window.ResetsAt,WindowMinutes=minutes };
   var drift=(window.ResetsAt-period.ResetAnchor).TotalSeconds;
   if(period.WindowMinutes!=minutes||drift>=60||drift<0) { period=new() { ResetAnchor=window.ResetsAt,WindowMinutes=minutes }; previous.Remove(id); }
   NotificationCategory? category=null;
   if(previous.TryGetValue(id,out var old)) {
    if(old>0&&remaining<=0&&!period.ExhaustionNotified) { category=NotificationCategory.QuotaExhausted; period.ExhaustionNotified=true; period.Incident++; }
    else if(old>threshold&&remaining>0&&remaining<=threshold&&!period.LowNotified) { category=NotificationCategory.QuotaLow; period.LowNotified=true; }
   } else { period.LowNotified|=remaining<=threshold; period.ExhaustionNotified|=remaining<=0; }
   State.Periods[id]=period; previous[id]=remaining;
   if(category is {} c) {
    if(!groups.TryGetValue(c,out var ids)) groups[c]=ids=[];
    if(!identities.TryGetValue(c,out var keys)) identities[c]=keys=[];
    ids.Add(id); keys.Add($"{id}:{period.ResetAnchor.ToUnixTimeMilliseconds()}:{period.Incident}");
   }
  }
  return groups.OrderBy(g=>NotificationPolicy.Priority(g.Key)).Select(g=>new QuotaWarningEvent(g.Key,g.Value,threshold,$"{State.Epoch}:{g.Key}:{threshold}:"+string.Join("|",identities[g.Key]))).ToArray();
 }
}
