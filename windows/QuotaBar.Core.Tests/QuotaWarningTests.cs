using System.Text.Json;
using QuotaBar.Core;
static class QuotaWarningTests {
 public static void Run() {
  DynamicCases();
  using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/notifications/warning-cases.json")));
  var now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
  foreach(var item in doc.RootElement.EnumerateArray()) {
   var engine=new QuotaWarningEngine(); var i=0;
   foreach(var step in item.GetProperty("steps").EnumerateArray()) {
    i++; bool Flag(string key)=>step.TryGetProperty(key,out var v)&&v.GetBoolean();
    int Number(string key,int fallback)=>step.TryGetProperty(key,out var v)?v.GetInt32():fallback;
    if(Flag("restart")) engine=new(JsonSerializer.Deserialize<QuotaWarningState>(JsonSerializer.Serialize(engine.State))!);
    if(Flag("confirm")) engine.ConfirmRecovery(["primary","secondary"]);
    var remaining=Number("remaining",0); var reset=Number("reset",3600); var at=now.AddSeconds(Number("seconds",i*20)-Number("age",0));
    var second=step.TryGetProperty("second",out var s)?new QuotaWindow(100-s.GetInt32(),s.GetInt32(),now.AddDays(7),10080):null;
    var used=step.TryGetProperty("used",out var u)?u.GetDouble():100-remaining;
    var q=new QuotaSnapshot(new(used,remaining,now.AddSeconds(reset),300),second,"plus",null,null,at);
    var epoch=step.TryGetProperty("epoch",out var ep)?ep.GetString()!:"a";
    var result=engine.Observe(new(epoch,i,at,q),Number("threshold",20),now.AddSeconds(Number("seconds",i*20)));
    var expected=step.GetProperty("expected").EnumerateArray().Select(x=>Enum.Parse<NotificationCategory>(x.GetString()!,true)).ToArray();
    if(!result.Select(x=>x.Category).SequenceEqual(expected)) throw new Exception(item.GetProperty("name").GetString()+" step "+i);
   }
  }
 }
 static void DynamicCases() {
  using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/notifications/dynamic-warning-cases.json")));
  var now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
  foreach(var item in doc.RootElement.EnumerateArray()) {
   var engine=new QuotaWarningEngine(); var i=0;
   foreach(var step in item.GetProperty("steps").EnumerateArray()) {
    if(step.TryGetProperty("legacy",out var legacy)&&legacy.GetBoolean()) {
     var json=System.Text.Json.Nodes.JsonNode.Parse(JsonSerializer.Serialize(engine.State))!.AsObject(); json.Remove("Thresholds");
     foreach(var period in json["Periods"]!.AsObject()) period.Value!.AsObject().Remove("ConsumedThresholds");
     engine=new(JsonSerializer.Deserialize<QuotaWarningState>(json.ToJsonString())!);
    }
    i++; if(step.TryGetProperty("restart",out var restart)&&restart.GetBoolean()) engine=new(JsonSerializer.Deserialize<QuotaWarningState>(JsonSerializer.Serialize(engine.State))!);
    if(step.TryGetProperty("configure",out var edits)) foreach(var edit in edits.EnumerateArray()) engine.ConfigureLowThresholds(edit.EnumerateArray().Select(x=>x.GetInt32()));
    var remaining=step.GetProperty("remaining").GetInt32(); var at=now.AddSeconds(i*20);
    var received=step.TryGetProperty("stale",out var stale)&&stale.GetBoolean()?at.AddSeconds(-121):at;
    var second=step.TryGetProperty("second",out var s)?new QuotaWindow(100-s.GetInt32(),s.GetInt32(),now.AddDays(7),10080):null;
    var q=new QuotaSnapshot(new(100-remaining,remaining,now.AddHours(1),300),second,"plus",null,null,at);
    var events=engine.Observe(new("a",i,received,q),step.GetProperty("thresholds").EnumerateArray().Select(x=>x.GetInt32()).ToArray(),at);
    var actual=events.Select(x=>x.Category==NotificationCategory.QuotaExhausted?0:x.Threshold);
    if(!actual.SequenceEqual(step.GetProperty("expected").EnumerateArray().Select(x=>x.GetInt32()))) throw new Exception(item.GetProperty("name").GetString()+" step "+i);
    if(step.TryGetProperty("periods",out var periods)&&!events[0].PeriodIDs.SequenceEqual(periods.EnumerateArray().Select(x=>x.GetString()!))) throw new Exception("wrong threshold periods");
   }
  }
 }

}
