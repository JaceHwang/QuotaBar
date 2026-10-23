using System.Text.Json;
using QuotaBar.Core;
static class NotificationPresentationTests {
    public static void Run() {
        var now=DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        void Check(bool ok,string label) { if(!ok) throw new Exception("presentation: "+label); }
        ExperienceNotification M(string id,ExperienceNotificationKind kind=ExperienceNotificationKind.Recovery)=>new(id,kind,kind==ExperienceNotificationKind.Update?null:"a",id,"body",now);
        Check(new NotificationPresentationPreferences().Mode==NotificationDeliveryMode.Bubble,"default");
        var state=new NotificationPresentationState();
        state.Enqueue(M("u",ExperienceNotificationKind.Update),true,now); state.Enqueue(M("r1"),true,now); state.Enqueue(M("r2"),true,now); state.Enqueue(M("r1"),true,now);
        Check(state.Next(true,now)?.Id=="r1","priority"); state.Shown("r1",now); state.Dismiss("r1",true);
        Check(state.Next(true,now)?.Id=="r2","FIFO"); state.Suspend(); state.Enqueue(M("hidden"),false,now);
        Check(state.Next(true,now)?.Id=="u","hidden not replayed"); state.Dismiss("u",true); Check(state.Next(true,now)==null,"no hidden replay");
        Check(state.Unread(now).Count==2,"unread"); state.Cancel("a"); Check(state.Unread(now).Count==0,"epoch");
        state.Enqueue(M("timer"),true,now); state.Next(true,now); state.Shown("timer",now); state.SetInteracting(true,now.AddSeconds(2)); Check(!state.Tick(now.AddSeconds(30)),"hover");
        state.SetInteracting(false,now.AddSeconds(30)); Check(!state.Tick(now.AddSeconds(33)),"remaining"); Check(!state.Tick(now.AddSeconds(34))&&state.ActiveId=="timer","no automatic timeout"); state.Dismiss("timer",false);
        Check(state.Unread(now.AddHours(25)).Count==0,"retention"); state.Stop(); state.Enqueue(M("stopped"),true,now); Check(state.Unread(now).Count==0,"stop");
        foreach(var kind in Enum.GetValues<ExperienceNotificationKind>()) {
            var held=new NotificationPresentationState();
            QuotaObservation O(double used,long seq,DateTimeOffset at,ObservationSource source=ObservationSource.FullRead)=>new("a",seq,at,new(new(used,(int)(100-used),now.AddHours(1),300),null,null,null,null,at),Source:source);
            Check(!held.ObserveQuota(O(20,1,now),now),"initial baseline");
            held.Enqueue(M("held",kind),true,now); held.Next(true,now); held.Shown("held",now);
            Check(!held.Tick(now.AddHours(25))&&held.ActiveId=="held","all kinds remain beyond timer and retention");
            Check(!held.ObserveQuota(O(20,2,now.AddSeconds(60)),now.AddSeconds(60)),"timestamp alone unchanged");
            Check(!held.ObserveQuota(O(101,3,now.AddSeconds(65)),now.AddSeconds(65))&&held.ActiveId=="held","invalid percentage ignored");
            Check(!held.ObserveQuota(O(20,4,now.AddSeconds(66)),now.AddSeconds(66)),"invalid observation did not replace baseline");
            Check(!held.ObserveQuota(O(21,3,now.AddSeconds(70),ObservationSource.Notification),now.AddSeconds(70)),"partial notification ignored");
            Check(!held.ObserveQuota(O(21,1,now),now.AddSeconds(80)),"late sequence ignored");
            Check(!held.ObserveQuota(O(21,3,now),now.AddSeconds(180)),"stale observation ignored");
            Check(held.ObserveQuota(O(20.1,10,now.AddSeconds(120)),now.AddSeconds(120))&&held.ActiveId==null,"raw quota change dismisses");
        }
        var optional=new NotificationPresentationState();
        QuotaObservation S(double? secondary,long sequence,string epoch="a")=>new(epoch,sequence,now,new(new(20,80,now,300),secondary is { } used?new(used,50,now,10080):null,null,null,null,now));
        optional.ObserveQuota(S(40,1),now); optional.Enqueue(M("secondary"),true,now); optional.Next(true,now); optional.Shown("secondary",now);
        Check(!optional.ObserveQuota(S(null,2),now),"missing secondary is unknown");
        Check(!optional.ObserveQuota(S(101,3),now)&&optional.ActiveId=="secondary","invalid secondary ignored");
        Check(optional.ObserveQuota(S(41,4),now),"known secondary comparison survives omission and invalid response");
        optional.Enqueue(M("epoch-update",ExperienceNotificationKind.Update),true,now); optional.Next(true,now);
        Check(!optional.ObserveQuota(S(90,1,"b"),now)&&optional.ActiveId=="epoch-update","new epoch establishes baseline");
        optional.Stop(); Check(!optional.ObserveQuota(S(91,2,"b"),now),"stopped observation ignored");
        var rect=NotificationBubbleLayout.Place(new(-100,550,90,30),new(-800,0,800,600),368,150);
        Check(rect is { } r && r.X>=-792 && r.X+r.Width<=-8 && r.Y+r.Height==542,"placement");
        Check(NotificationBubbleLayout.Place(new(0,0,10,30),new(0,0,200,100),368,150)==null,"narrow");
        var pref=JsonSerializer.Deserialize<Preferences>("{\"UpdateReminders\":false,\"Experience\":{\"Moods\":false}}")!.Validated();
        Check(pref.Notifications.Mode==NotificationDeliveryMode.Bubble&&!pref.UpdateReminders&&!pref.Experience.Moods,"migration preserves false");
        var invalid=JsonSerializer.Deserialize<Preferences>("{\"UpdateReminders\":false,\"Experience\":{\"Moods\":false},\"Notifications\":{\"Mode\":\"invalid\"}}")!.Validated();
        Check(invalid.Notifications.Mode==NotificationDeliveryMode.Bubble&&!invalid.Experience.Moods,"invalid channel preserves opt-out");
        var fixture=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"../../../../../contracts/notifications/presentation-sequences.json")));
        foreach(var row in fixture.RootElement.EnumerateArray()) {
            var s=new NotificationPresentationState(); var id=row.GetProperty("id").GetString()!; s.Enqueue(M(id),row.GetProperty("visible").GetBoolean(),now);
            Check((s.Next(true,now)?.Id)==(row.GetProperty("expected").ValueKind==JsonValueKind.Null?null:row.GetProperty("expected").GetString()),"shared fixture");
        }
        Console.WriteLine("PASS notification presentation state, migration, layout and shared sequences");
    }
}
