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
        state.SetInteracting(false,now.AddSeconds(30)); Check(!state.Tick(now.AddSeconds(33)),"remaining"); Check(state.Tick(now.AddSeconds(34)),"timeout");
        Check(state.Unread(now.AddHours(25)).Count==0,"retention"); state.Stop(); state.Enqueue(M("stopped"),true,now); Check(state.Unread(now).Count==0,"stop");
        var rect=NotificationBubbleLayout.Place(new(-100,550,90,30),new(-800,0,800,600),368,150);
        Check(rect is { } r && r.X>=-792 && r.X+r.Width<=-8 && r.Y+r.Height==542,"placement");
        Check(NotificationBubbleLayout.Place(new(0,0,10,30),new(0,0,200,100),368,150)==null,"narrow");
        var pref=JsonSerializer.Deserialize<Preferences>("{\"UpdateReminders\":false,\"Experience\":{\"Moods\":false}}")!.Validated();
        Check(pref.Notifications.Mode==NotificationDeliveryMode.Bubble&&!pref.UpdateReminders&&!pref.Experience.Moods,"migration preserves false");
        var fixture=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"../../../../../contracts/notifications/presentation-sequences.json")));
        foreach(var row in fixture.RootElement.EnumerateArray()) {
            var s=new NotificationPresentationState(); var id=row.GetProperty("id").GetString()!; s.Enqueue(M(id),row.GetProperty("visible").GetBoolean(),now);
            Check((s.Next(true,now)?.Id)==(row.GetProperty("expected").ValueKind==JsonValueKind.Null?null:row.GetProperty("expected").GetString()),"shared fixture");
        }
        Console.WriteLine("PASS notification presentation state, migration, layout and shared sequences");
    }
}
