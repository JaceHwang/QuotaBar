using QuotaBar.Core;
using System.Text;
internal static class BarkTests {
 public static void Run() {
  static void Check(bool ok) { if(!ok) throw new Exception("Bark regression"); }
  using(var fixture=System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/bark/scenarios.json")))) {
   foreach(var key in fixture.RootElement.GetProperty("validKeys").EnumerateArray()) Check(BarkPayload.IsValidDeviceKey(key.GetString()!));
   foreach(var key in fixture.RootElement.GetProperty("invalidKeys").EnumerateArray()) Check(!BarkPayload.IsValidDeviceKey(key.GetString()!));
   foreach(var row in fixture.RootElement.GetProperty("responses").EnumerateArray()) Check(BarkResponse.Classify(row.GetProperty("status").GetInt32(),Encoding.UTF8.GetBytes(row.GetProperty("body").GetString()!))==row.GetProperty("result").GetString() switch { "accepted"=>BarkResponse.Accepted,"rejected"=>BarkResponse.Rejected,_=>BarkResponse.Unknown });
  }
  Check(!new BarkPreferences().Enabled);
  Check(!BarkPayload.IsValidDeviceKey("https://api.day.app/key"));
  Check(BarkPayload.Encode("fake-key","Hello",string.Concat(Enumerable.Repeat("👨‍👩‍👧‍👦中\n\"",1000))).Length<=3000);
  Check(BarkResponse.Classify(200,Encoding.UTF8.GetBytes("{\"code\":200}"))==BarkResponse.Accepted);
  var dir=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString());
  try { var path=Path.Combine(dir,"receipts.json"); var now=DateTimeOffset.UtcNow; var id=new BarkEventIdentity("event"); var store=new BarkDeliveryStore(path); Check(store.Reserve(id,now)); Check(!new BarkDeliveryStore(path).Reserve(id,now));
   for(var i=1;i<256;i++) Check(store.Reserve(new(i.ToString()),now)); Check(!store.Reserve(new("full"),now));
   File.WriteAllText(path,"broken"); Check(Directory.GetFiles(dir,"*.corrupt-*").Length==0); var broken=new BarkDeliveryStore(path); Check(Directory.GetFiles(dir,"*.corrupt-*").Length==1); Check(broken.NeedsBaseline); Check(!broken.Reserve(id,now)); Check(broken.EstablishBaseline([id],now)); Check(!broken.Reserve(id,now));
   var livePath=Path.Combine(dir,"live"); var live=new BarkDeliveryStore(livePath); Check(live.Reserve(id,now)); live.MarkAccepted(id,now); Check(live.Reserve(new("later"),now.AddDays(31),new HashSet<BarkEventIdentity>{id})); Check(!new BarkDeliveryStore(livePath).Reserve(id,now.AddDays(31)));
   var blocker=Path.Combine(dir,"blocker"); File.WriteAllText(blocker,""); var fail=new BarkDeliveryStore(Path.Combine(blocker,"state")); Check(!fail.Reserve(id,now)&&fail.HasPersistenceError);
   Check(BarkResponse.Classify(200,new byte[65537])==BarkResponse.Unknown);
   using(var encoded=System.Text.Json.JsonDocument.Parse(BarkPayload.Encode(" fake-key ","title",string.Concat(Enumerable.Repeat("e\u0301👨‍👩‍👧‍👦",1000))))) { var output=encoded.RootElement.GetProperty("body").GetString()!; Check(output==string.Concat(Enumerable.Repeat("e\u0301👨‍👩‍👧‍👦",1000))[..output.Length]); Check(!output.EndsWith("e",StringComparison.Ordinal)&&!output.EndsWith("‍",StringComparison.Ordinal)); Check(encoded.RootElement.GetProperty("device_key").GetString()=="fake-key"); Check(encoded.RootElement.EnumerateObject().Count()==5); }
   foreach(var malformed in new[]{"{\"Schema\":1,\"Receipts\":[{\"Identity\":{\"Id\":\"old\",\"Generation\":\"initial\"}}]}","{\"Schema\":1,\"Receipts\":[],\"NeedsBaseline\":null}","{\"Schema\":1,\"NeedsBaseline\":false,\"Receipts\":[{\"Identity\":{\"Id\":\"old\"},\"At\":\"2026-10-23T00:00:00Z\",\"Accepted\":false}]}","{\"Schema\":1,\"NeedsBaseline\":false,\"Receipts\":[{\"Identity\":{\"Id\":\"old\",\"Generation\":\"initial\"}}]}"}) {
    var damagedPath=Path.Combine(dir,Guid.NewGuid()+".json"); File.WriteAllText(damagedPath,malformed); var damaged=new BarkDeliveryStore(damagedPath);
    Check(damaged.NeedsBaseline); Check(Directory.GetFiles(dir,Path.GetFileName(damagedPath)+".corrupt-*").Length==1); Check(!damaged.Reserve(new("current"),now));
   }
   var crashPath=Path.Combine(dir,"crash.json"); File.WriteAllText(crashPath,"broken"); _=new BarkDeliveryStore(crashPath); var restarted=new BarkDeliveryStore(crashPath); Check(restarted.NeedsBaseline); Check(!restarted.Reserve(new("old-update"),now));
   Check(restarted.EstablishBaseline([],now)); for(var n=0;n<255;n++) Check(restarted.Reserve(new("event-"+n),now)); Check(restarted.EstablishBaseline([new("new-current")],now.AddDays(31))); Check(!restarted.Reserve(new("new-current"),now.AddDays(31)));
   var pref=Path.Combine(dir,"prefs"); File.WriteAllText(pref,"{\"Bark\":{\"Schema\":\"bad\"},\"Theme\":\"dark\",\"FloatingEnabled\":false}"); var p=new PreferencesStore(pref).Load(); Check(p.Theme=="dark"&&!p.FloatingEnabled&&!p.Bark.Enabled);
   foreach(var bark in new[]{"null","\"bad\"","{\"Enabled\":\"bad\"}"}) { File.WriteAllText(pref,"{\"Bark\":"+bark+",\"Theme\":\"dark\",\"FloatingEnabled\":false}"); p=new PreferencesStore(pref).Load(); Check(p.Theme=="dark"&&!p.FloatingEnabled&&!p.Bark.Enabled); }
  } finally { if(Directory.Exists(dir)) Directory.Delete(dir,true); }
 }
}
