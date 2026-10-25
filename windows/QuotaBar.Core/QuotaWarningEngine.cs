namespace QuotaBar.Core;
public sealed record QuotaWarningPeriodState {
 public DateTimeOffset ResetAnchor { get; init; }
 public int WindowMinutes { get; init; }
 public List<int>? ConsumedThresholds { get; set; }
 public bool LowNotified { get; set; }
 public bool ExhaustionNotified { get; set; }
 public int Incident { get; set; }
}
public sealed record QuotaWarningState {
 public int Schema { get; init; }=1;
 public string Epoch { get; set; }="";
 public string Plan { get; set; }="";
 public List<int>? Thresholds { get; set; }
 public int Threshold { get; set; }=20;
 public Dictionary<string,QuotaWarningPeriodState> Periods { get; set; }=[];
}
public sealed record QuotaWarningEvent(NotificationCategory Category,IReadOnlyList<string> PeriodIDs,int Threshold,string IncidentID);
public sealed class QuotaWarningEngine {
 public QuotaWarningState State { get; private set; }
 readonly Dictionary<string,double> previous=[];
 readonly Dictionary<string,DateTimeOffset> availableSince=[];
 HashSet<int>? configuredLowThresholds;
 readonly HashSet<int> pendingLowBaselines=[];
 long sequence=-1;
 DateTimeOffset? receivedAt;
 public QuotaWarningEngine(QuotaWarningState? state=null) { State=state is { Schema:1,Periods.Count:<=2 }?state:new(); }
 // Record policy transitions without resetting depletion comparison or recovery timing.
 public void ConfigureLowThresholds(IEnumerable<int> thresholds) {
  var levels=thresholds.Where(x=>x is >=1 and <=99).Distinct().OrderDescending().Take(32).ToHashSet();
  if(configuredLowThresholds is {} previous) pendingLowBaselines.UnionWith(levels.Except(previous));
  configuredLowThresholds=levels;
 }
 public void ResetBaseline() { previous.Clear(); availableSince.Clear(); sequence=-1; receivedAt=null; }
 public void ConfirmRecovery(IEnumerable<string> periodIDs) { foreach(var id in periodIDs) if(State.Periods.TryGetValue(id,out var p)) { p.ExhaustionNotified=false; availableSince.Remove(id); } }
 public IReadOnlyList<QuotaWarningEvent> Observe(QuotaObservation o,int threshold,DateTimeOffset now) => Observe(o,[threshold is >=1 and <=99?threshold:20],now,true);
 public IReadOnlyList<QuotaWarningEvent> Observe(QuotaObservation o,IReadOnlyList<int> thresholds,DateTimeOffset now) => Observe(o,thresholds,now,false);
 IReadOnlyList<QuotaWarningEvent> Observe(QuotaObservation o,IReadOnlyList<int> levels,DateTimeOffset now,bool scalar) {
  if(o.Source!=ObservationSource.FullRead||(now-o.ReceivedAt).TotalSeconds is < -5 or >120) return [];
  if(State.Epoch!=o.Epoch) { State=new() { Epoch=o.Epoch }; ResetBaseline(); }
  if(o.Sequence<=sequence||receivedAt is {} last&&o.ReceivedAt<last) return [];
  sequence=o.Sequence; receivedAt=o.ReceivedAt;
  var windows=new (string Id,QuotaWindow? Window)[]{("primary",o.Quota.Primary),("secondary",o.Quota.Secondary)};
  var plan=o.Quota.Plan?.Trim();
  if(string.IsNullOrEmpty(plan)||windows.Where(w=>w.Window!=null).Any(w=>!double.IsFinite(w.Window!.UsedPercent)||w.Window.UsedPercent is <0 or >100||w.Window.WindowMinutes is null or <=0)) { previous.Clear(); availableSince.Clear(); return []; }
  if(State.Plan!=plan) { State.Periods.Clear(); previous.Clear(); availableSince.Clear(); State.Plan=plan; }
  var thresholds=levels.Where(x=>x is >=1 and <=99).Distinct().OrderDescending().Take(32).ToArray();
  var oldThresholds=State.Thresholds??[State.Threshold];
  var added=thresholds.Except(oldThresholds).Concat(pendingLowBaselines).ToHashSet();
  pendingLowBaselines.Clear();
  var threshold=thresholds.FirstOrDefault(20);
  var scalarChanged=scalar&&State.Threshold!=threshold;
  State.Thresholds=thresholds.ToList(); State.Threshold=threshold;
  Dictionary<NotificationCategory,List<string>> groups=[],identities=[];
  List<(string Id,int Threshold,string Identity)> lowCrossings=[];
  foreach(var (id,window) in windows) {
   if(window is null) { previous.Remove(id); availableSince.Remove(id); continue; }
   var remaining=100-window.UsedPercent; var minutes=window.WindowMinutes!.Value;
   var period=State.Periods.TryGetValue(id,out var oldPeriod)?oldPeriod:new() { ResetAnchor=window.ResetsAt,WindowMinutes=minutes };
   var drift=(window.ResetsAt-period.ResetAnchor).TotalSeconds;
   if(period.WindowMinutes!=minutes||drift>=60||drift<0) { period=new() { ResetAnchor=window.ResetsAt,WindowMinutes=minutes }; previous.Remove(id); availableSince.Remove(id); }
   if(period.ExhaustionNotified&&remaining>=1) {
    if(availableSince.TryGetValue(id,out var since)) { var elapsed=(o.ReceivedAt-since).TotalSeconds; if(elapsed>120) availableSince[id]=o.ReceivedAt; else if(elapsed>=15) { period.ExhaustionNotified=false; availableSince.Remove(id); } }
    else availableSince[id]=o.ReceivedAt;
   } else availableSince.Remove(id);
   var consumed=(period.ConsumedThresholds??(period.LowNotified?[oldThresholds.FirstOrDefault(State.Threshold)]:new List<int>())).ToHashSet();
   if(scalarChanged&&period.LowNotified) consumed.UnionWith(thresholds);
   NotificationCategory? category=null;
   if(previous.TryGetValue(id,out var old)) {
    foreach(var level in added.Where(x=>remaining<=x)) consumed.Add(level);
    var crossed=thresholds.Where(x=>!added.Contains(x)&&old>x&&remaining<=x&&!consumed.Contains(x)).ToArray();
    if(old>0&&remaining<=0&&!period.ExhaustionNotified) { category=NotificationCategory.QuotaExhausted; period.ExhaustionNotified=true; period.Incident++; }
    if(remaining>0&&!scalarChanged&&crossed.Length>0) lowCrossings.Add((id,crossed.Min(),$"{id}:{period.ResetAnchor.ToUnixTimeMilliseconds()}:{period.Incident}"));
    consumed.UnionWith(crossed);
   } else { consumed.UnionWith(thresholds.Where(x=>remaining<=x)); period.ExhaustionNotified|=remaining<=0; }
   period.ConsumedThresholds=consumed.OrderDescending().ToList(); period.LowNotified|=consumed.Count>0;
   State.Periods[id]=period; previous[id]=remaining;
   if(category is {} c) {
    if(!groups.TryGetValue(c,out var ids)) groups[c]=ids=[];
    if(!identities.TryGetValue(c,out var keys)) identities[c]=keys=[];
    ids.Add(id); keys.Add($"{id}:{period.ResetAnchor.ToUnixTimeMilliseconds()}:{period.Incident}");
   }
  }
  var events=groups.OrderBy(g=>NotificationPolicy.Priority(g.Key)).Select(g=>new QuotaWarningEvent(g.Key,g.Value,threshold,$"{State.Epoch}:{g.Key}:{threshold}:"+string.Join("|",identities[g.Key]))).ToList();
  if(lowCrossings.Count>0) {
   var level=lowCrossings.Min(x=>x.Threshold); var selected=lowCrossings.Where(x=>x.Threshold==level).ToArray();
   events.Add(new(NotificationCategory.QuotaLow,selected.Select(x=>x.Id).ToArray(),level,$"{State.Epoch}:{NotificationCategory.QuotaLow}:{level}:"+string.Join("|",selected.Select(x=>x.Identity))));
  }
  return events.OrderBy(x=>NotificationPolicy.Priority(x.Category)).ToArray();
 }
}
