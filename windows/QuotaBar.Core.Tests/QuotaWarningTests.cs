using System.Text.Json;
using QuotaBar.Core;
static class QuotaWarningTests {
 public static void Run() {
  using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/notifications/warning-cases.json")));
  var now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
  foreach(var item in doc.RootElement.EnumerateArray()) {
   var engine=new QuotaWarningEngine(); var i=0;
   foreach(var step in item.GetProperty("steps").EnumerateArray()) {
    i++; bool Flag(string key)=>step.TryGetProperty(key,out var v)&&v.GetBoolean();
    int Number(string key,int fallback)=>step.TryGetProperty(key,out var v)?v.GetInt32():fallback;
    if(Flag("restart")) engine=new(JsonSerializer.Deserialize<QuotaWarningState>(JsonSerializer.Serialize(engine.State))!);
    if(Flag("confirm")) engine.ConfirmRecovery(["primary","secondary"]);
    var remaining=Number("remaining",0); var reset=Number("reset",3600); var at=now.AddSeconds(i*20-Number("age",0));
    var second=step.TryGetProperty("second",out var s)?new QuotaWindow(100-s.GetInt32(),s.GetInt32(),now.AddDays(7),10080):null;
    var q=new QuotaSnapshot(new(100-remaining,remaining,now.AddSeconds(reset),300),second,"plus",null,null,at);
    var epoch=step.TryGetProperty("epoch",out var ep)?ep.GetString()!:"a";
    var result=engine.Observe(new(epoch,i,at,q),Number("threshold",20),now.AddSeconds(i*20));
    var expected=step.GetProperty("expected").EnumerateArray().Select(x=>Enum.Parse<NotificationCategory>(x.GetString()!,true)).ToArray();
    if(!result.Select(x=>x.Category).SequenceEqual(expected)) throw new Exception(item.GetProperty("name").GetString()+" step "+i);
   }
  }
 }
}
