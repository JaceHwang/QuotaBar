using System.Text.Json;
using QuotaBar.Core;
internal static class ExperienceTests {
    public static void Run() {
        void Check(bool ok,string why) { if(!ok) throw new Exception(why); }
        var now=DateTimeOffset.FromUnixTimeSeconds(1800000000);
        QuotaSnapshot Q(double used,double reset=1000,BankSummary? bank=null)=>new(new(used,(int)Math.Round(100-used),now.AddSeconds(reset),300),null,"plus",null,bank,now);
        Check(new QuotaExperiencePreferences()==new QuotaExperiencePreferences(false,false,false,false),"experience defaults off");
        using var fixtures=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/experience/recovery-sequences.json")));
        foreach(var row in fixtures.RootElement.EnumerateArray()) {
            var engine=new QuotaExperienceEngine(new ExperienceState { Epoch="a" }); engine.Configure(new(Recovery:true));
            for(var i=0;i<row.GetProperty("used").GetArrayLength();i++) {
                var at=now.AddSeconds(row.GetProperty("seconds")[i].GetDouble());
                var result=engine.Observe(new("a",i+1,at,Q(row.GetProperty("used")[i].GetDouble(),row.GetProperty("reset")[i].GetDouble())),at);
                Check(result.Recoveries.Count==row.GetProperty("events")[i].GetInt32(),row.GetProperty("name").GetString()!);
            }
        }
        Check(QuotaMoods.Resolve(Q(99.6),true,now)==QuotaMood.Low,"rounded zero not exhausted");
        Check(QuotaMoods.Resolve(Q(0),true,now.AddSeconds(121))==QuotaMood.Unavailable,"stale mood");
        var credit=new BankCredit("available",null,now.AddHours(72),null,null,"credit1","codex");
        var inventory=new BankSummary(1,[credit]); var bankEngine=new QuotaExperienceEngine(new ExperienceState { Epoch="a" }); bankEngine.Configure(new(Bank:true));
        var observation=new QuotaObservation("a",1,now,Q(0,bank:inventory),BankFieldState.Value);
        var bankEvents=bankEngine.Observe(observation,now).Bank;
        Check(bankEvents.Count==1 && bankEvents[0].Stage==72,"72h inclusive");
        Check(bankEngine.BankEventsAreCurrent(bankEvents,observation,now),"matching inventory");
        Check(!bankEngine.BankEventsAreCurrent(bankEvents,observation with { Quota=Q(0,bank:inventory with { Credits=[credit with { Id="replaced" }] }) },now),"replaced inventory cancels queued alert");
        var restored=new QuotaExperienceEngine(bankEngine.State); restored.Configure(new(Bank:true));
        Check(restored.Observe(observation,now).Bank.Count==0,"restart dedup");
        var later=now.AddHours(48); var obs24=observation with { Sequence=2,ReceivedAt=later };
        Check(restored.Observe(obs24,later).Bank.Single().Stage==24,"24h inclusive and separate stage");
        Check(restored.Observe(obs24 with { Sequence=3,ReceivedAt=later.AddSeconds(1) },later.AddSeconds(1)).Bank.Count==0,"no repeat");
        var missing=new QuotaExperienceEngine(new ExperienceState { Epoch="a" }); missing.Configure(new(Bank:true));
        Check(missing.Observe(observation with { BankFieldState=BankFieldState.Omitted },now).Bank.Count==0,"cached Bank not used");
        Check(missing.Observe(observation with { Sequence=2,ReceivedAt=now.AddSeconds(-121) },now).Bank.Count==0,"stale read ignored");
        var suppress=new QuotaExperienceEngine(new ExperienceState { Epoch="a" },true); suppress.Configure(new(Bank:true));
        Check(suppress.Observe(observation,now).Bank.Count==0 && suppress.State.Receipts.Count==1,"corrupt store baseline suppresses storm");
        var queue=new ExperienceNotificationQueue();
        queue.Enqueue(new("update",ExperienceNotificationKind.Update,null,"","",now)); queue.Enqueue(new("bank",ExperienceNotificationKind.Bank,"a","","",now));
        Check(queue.Next(now)?.Id=="bank" && queue.Next(now)?.Id=="update","queue priority");
        queue.Enqueue(new("stale",ExperienceNotificationKind.Recovery,"a","","",now.AddSeconds(-301))); Check(queue.Next(now) is null,"recovery TTL");
        var dir=Path.Combine(Path.GetTempPath(),"experience-"+Guid.NewGuid());
        try {
            var path=Path.Combine(dir,"state.json"); var store=new QuotaExperienceStore(path); store.Save(bankEngine.State); var loaded=store.Load();
            Check(loaded.Epoch=="a" && loaded.Receipts.Count==1,"atomic state roundtrip");
            File.WriteAllText(path,"bad"); store.Load(); Check(store.Corrupted && Directory.GetFiles(dir,"*.corrupt").Length==1,"corrupt preserved");
            var prefsStore=new PreferencesStore(Path.Combine(dir,"prefs.json")); var prefs=prefsStore.Load(); Check(prefs.Experience==new QuotaExperiencePreferences(),"old defaults remain disabled");
            prefsStore.Save(prefs with { Experience=new(Moods:true,Celebration:true) }); Check(prefsStore.Load().Experience==new QuotaExperiencePreferences(Moods:true,Celebration:true),"independent preferences persist");
        } finally { if(Directory.Exists(dir)) Directory.Delete(dir,true); }
        Console.WriteLine("PASS quota experience shared sequences, mood, Bank stages/inventory, queue and stores");
    }
}
