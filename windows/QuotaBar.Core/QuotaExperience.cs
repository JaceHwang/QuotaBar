using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace QuotaBar.Core;
public sealed record QuotaExperiencePreferences(bool Moods=false,bool Recovery=false,bool Celebration=false,bool Bank=false);
public enum QuotaMood { Good,Low,Exhausted,Unavailable,Recovered }
public static class QuotaMoods {
    public static QuotaMood Resolve(QuotaSnapshot? q,bool ready,DateTimeOffset now) {
        if(!ready || q is null || (now-q.ReceivedAt).TotalSeconds is >120 or < -5) return QuotaMood.Unavailable;
        var windows=new[]{q.Primary,q.Secondary}.OfType<QuotaWindow>().ToArray();
        if(windows.Any(w=>!double.IsFinite(w.UsedPercent) || w.UsedPercent is <0 or >100)) return QuotaMood.Unavailable;
        return windows.Any(w=>w.UsedPercent>=100)?QuotaMood.Exhausted:windows.Any(w=>w.UsedPercent>=80)?QuotaMood.Low:QuotaMood.Good;
    }
}
public enum BankFieldState { Omitted,Null,Value }
public enum ObservationSource { FullRead,Notification }
public sealed record QuotaObservation(string Epoch,long Sequence,DateTimeOffset ReceivedAt,QuotaSnapshot Quota,BankFieldState BankFieldState=BankFieldState.Omitted,ObservationSource Source=ObservationSource.FullRead) {
    public static QuotaObservation Decode(string json,string epoch,long sequence,DateTimeOffset? receivedAt=null) {
        using var doc=JsonDocument.Parse(json); var root=doc.RootElement.Get("result"); if(!root.HasValue()) root=doc.RootElement;
        var field=root.Get("rateLimitResetCredits");
        return new(epoch,sequence,receivedAt??DateTimeOffset.UtcNow,QuotaDecoder.Decode(json,receivedAt:receivedAt),field.ValueKind==JsonValueKind.Undefined?BankFieldState.Omitted:field.ValueKind==JsonValueKind.Null?BankFieldState.Null:BankFieldState.Value);
    }
}
public sealed record BankReceipt(int Stage,DateTimeOffset ExpiresAt);
public sealed record ExperienceState {
    public int Schema { get; init; }=1;
    public string Epoch { get; init; }=Guid.NewGuid().ToString();
    public Dictionary<string,BankReceipt> Receipts { get; init; }=[];
}
public sealed record BankExpiryEvent(string Key,int Stage,int Count,DateTimeOffset ExpiresAt);
public sealed record ExperienceUpdate(IReadOnlyList<string> Recoveries,IReadOnlyList<BankExpiryEvent> Bank);
public sealed class QuotaExperienceEngine(ExperienceState state,bool suppressFirstBank=false) {
    public ExperienceState State { get; private set; }=state with { Receipts=new(state.Receipts) };
    public QuotaExperiencePreferences Preferences { get; private set; }=new();
    QuotaSnapshot? baseline;
    long sequence=-1;
    sealed record Candidate(QuotaWindow Old,DateTimeOffset At);
    readonly Dictionary<string,Candidate> candidates=[];
    bool suppressBank=suppressFirstBank;
    public void Configure(QuotaExperiencePreferences p) {
        if(Preferences.Recovery!=p.Recovery || Preferences.Celebration!=p.Celebration) ResetBaseline();
        Preferences=p;
    }
    public void ResetBaseline() { baseline=null; candidates.Clear(); sequence=-1; }
    public void RotateEpoch() { State=new(); ResetBaseline(); suppressBank=false; }
    public ExperienceUpdate Observe(QuotaObservation o,DateTimeOffset now) {
        var recovery=new List<string>(); var bank=new List<BankExpiryEvent>();
        if(o.Epoch!=State.Epoch || o.Source!=ObservationSource.FullRead || o.Sequence<=sequence || (now-o.ReceivedAt).TotalSeconds is >120 or < -5) return new(recovery,bank);
        sequence=o.Sequence; var q=o.Quota;
        if(new[]{q.Primary,q.Secondary}.OfType<QuotaWindow>().Any(w=>!double.IsFinite(w.UsedPercent) || w.UsedPercent is <0 or >100)) { ResetBaseline(); return new(recovery,bank); }
        if(Preferences.Recovery || Preferences.Celebration) {
            var metadataKnown=!string.IsNullOrWhiteSpace(q.Plan) && q.Primary.WindowMinutes>0 && (q.Secondary is null || q.Secondary.WindowMinutes>0);
            var compatible=metadataKnown && baseline is not null && baseline.Plan==q.Plan && baseline.Primary.WindowMinutes==q.Primary.WindowMinutes && baseline.Secondary?.WindowMinutes==q.Secondary?.WindowMinutes && (baseline.Secondary is null)==(q.Secondary is null);
            if(compatible) {
                foreach(var (name,old,current) in new[]{("primary",baseline!.Primary,q.Primary),("secondary",baseline!.Secondary,q.Secondary)}) {
                    if(old is null || current is null) continue;
                    if(candidates.TryGetValue(name,out var pending)) {
                        var elapsed=(o.ReceivedAt-pending.At).TotalSeconds;
                        if(elapsed>120 || !Restored(pending.Old,current)) candidates.Remove(name);
                        else if(elapsed>=15) { recovery.Add(name); candidates.Remove(name); }
                    } else if(Restored(old,current)) candidates[name]=new(old,o.ReceivedAt);
                }
            } else candidates.Clear();
            baseline=q;
        }
        if(Preferences.Bank && o.BankFieldState==BankFieldState.Value && q.Bank is { } inventory) {
            bank=BankEvents(inventory,now);
            if(suppressBank) { bank.Clear(); suppressBank=false; }
        }
        State=State with { Receipts=State.Receipts.Where(p=>p.Value.ExpiresAt>now.AddDays(-1) && p.Value.ExpiresAt<now.AddDays(30)).ToDictionary() };
        if(State.Receipts.Count>2048) { State=State with { Receipts=State.Receipts.OrderBy(p=>p.Key,StringComparer.Ordinal).Take(2048).ToDictionary() }; bank.Clear(); }
        return new(recovery,bank);
    }
    static bool Restored(QuotaWindow old,QuotaWindow next) {
        var delta=(next.ResetsAt-old.ResetsAt).TotalSeconds;
        return old.UsedPercent>=100 && next.UsedPercent<=99 || delta>=60 && old.UsedPercent-next.UsedPercent>=10 || Math.Abs(delta)<60 && old.UsedPercent>=10 && next.UsedPercent<=1;
    }
    string BankKey(BankCredit c) {
        var identity=c.Id is { } id?"id:"+id:$"fallback:{c.GrantedAt?.ToUnixTimeSeconds()??0}:{c.ResetType??""}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{State.Epoch}|{identity}|{c.ExpiresAt?.ToUnixTimeSeconds()??0}")));
    }
    public bool BankEventsAreCurrent(IReadOnlyList<BankExpiryEvent> events,QuotaObservation observation,DateTimeOffset now) {
        if(events.Count==0 || observation.Epoch!=State.Epoch || observation.Source!=ObservationSource.FullRead || observation.BankFieldState!=BankFieldState.Value || (now-observation.ReceivedAt).TotalSeconds is >120 or < -5 || observation.Quota.Bank is not { AvailableCount:>0,Credits:not null } bank) return false;
        var inventory=new Dictionary<string,int>();
        foreach(var c in bank.Credits.Where(c=>c.Status=="available" && c.ExpiresAt>now && c.ExpiresAt<=now.AddHours(72))) {
            var key=BankKey(c); inventory.TryGetValue(key,out var count); inventory[key]=c.Id is null?count+1:1;
        }
        if(inventory.Values.Sum()>bank.AvailableCount || events.Sum(e=>e.Count)>bank.AvailableCount) return false;
        return events.All(e=> {
            var matches=bank.Credits.Where(c=>c.Status=="available" && BankKey(c)==e.Key).ToArray();
            var count=matches.FirstOrDefault()?.Id is null?matches.Length:Math.Min(1,matches.Length);
            var hours=(e.ExpiresAt-now).TotalHours;
            return count>=e.Count && hours>0 && hours<=72 && (hours<=24?24:72)==e.Stage;
        });
    }
    List<BankExpiryEvent> BankEvents(BankSummary bank,DateTimeOffset now) {
        if(bank.AvailableCount<=0 || bank.Credits is null) return [];
        var groups=new Dictionary<string,(int Count,DateTimeOffset Expires)>();
        foreach(var c in bank.Credits.Where(c=>c.Status=="available")) {
            if(c.ExpiresAt is not { } expires || expires<=now || expires>now.AddHours(72)) continue;
            var key=BankKey(c);
            groups.TryGetValue(key,out var prior); groups[key]=(c.Id is null?prior.Count+1:1,expires);
        }
        if(groups.Values.Sum(g=>g.Count)>bank.AvailableCount) return [];
        var result=new List<BankExpiryEvent>();
        foreach(var (key,g) in groups.OrderBy(p=>p.Key,StringComparer.Ordinal)) {
            var stage=(g.Expires-now).TotalHours<=24?24:72;
            if(State.Receipts.TryGetValue(key,out var receipt) && receipt.Stage<=stage) continue;
            State.Receipts[key]=new(stage,g.Expires); result.Add(new(key,stage,g.Count,g.Expires));
        }
        return result;
    }
}
public sealed class QuotaExperienceStore(string path) {
    public bool Corrupted { get; private set; }
    public ExperienceState Load() {
        if(!File.Exists(path)) return new();
        try {
            var state=JsonSerializer.Deserialize<ExperienceState>(File.ReadAllText(path));
            if(state is null || state.Schema!=1 || string.IsNullOrEmpty(state.Epoch) || state.Receipts is null || state.Receipts.Count>2048 || state.Receipts.Values.Any(r=>r is null)) throw new JsonException();
            return state;
        } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) {
            Corrupted=true;
            try { File.Move(path,path+"."+Guid.NewGuid()+".corrupt"); } catch(Exception x) when(x is IOException or UnauthorizedAccessException) { }
            return new();
        }
    }
    public void Save(ExperienceState state) {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temp=path+"."+Guid.NewGuid()+".tmp";
        try { File.WriteAllText(temp,JsonSerializer.Serialize(state)); File.Move(temp,path,true); }
        finally { if(File.Exists(temp)) File.Delete(temp); }
    }
}
