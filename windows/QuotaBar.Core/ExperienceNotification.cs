namespace QuotaBar.Core;
public enum ExperienceNotificationKind { Recovery,Bank,Update,Test }
public sealed record ExperienceNotification(string Id,ExperienceNotificationKind Kind,string? Epoch,string Title,string Body,DateTimeOffset CreatedAt,DateTimeOffset? ValidUntil=null,IReadOnlyList<BankExpiryEvent>? BankEvents=null,string? DeliveryToken=null,string ReminderGeneration="initial") {
    public bool Valid(DateTimeOffset now)=>now>=CreatedAt.AddSeconds(-5) && (ValidUntil is null || now<ValidUntil) && (Kind!=ExperienceNotificationKind.Recovery || now<=CreatedAt.AddMinutes(5));
}
public sealed class ExperienceNotificationQueue {
    readonly List<ExperienceNotification> messages=[];
    public void Enqueue(ExperienceNotification message) {
        if(messages.Any(m=>m.Id==message.Id)) return;
        messages.Add(message); messages.Sort((a,b)=>a.Kind.CompareTo(b.Kind)); if(messages.Count>32) messages.RemoveAt(messages.Count-1);
    }
    public void CancelId(string id)=>messages.RemoveAll(m=>m.Id==id);
    public void Cancel(string epoch)=>messages.RemoveAll(m=>m.Epoch==epoch);
    public ExperienceNotification? Next(DateTimeOffset now) {
        messages.RemoveAll(m=>!m.Valid(now)); if(messages.Count==0) return null;
        var result=messages[0]; messages.RemoveAt(0); return result;
    }
}
public sealed class ExperienceCopy(string language) {
    readonly Copy copy=new(language);
    public string Text(string en,string zh,string tw)=>copy.Text(en,zh,tw);
    public string MoodLabel(QuotaMood mood)=>mood switch {
        QuotaMood.Good=>Text("Quota available","额度充足","額度充足"), QuotaMood.Low=>Text("Quota low","额度偏低","額度偏低"), QuotaMood.Exhausted=>Text("A quota window is depleted","有额度周期已耗尽","有額度週期已耗盡"), QuotaMood.Recovered=>Text("Quota restored","额度已恢复","額度已恢復"), _=>Text("Quota data unavailable or stale","额度数据暂不可用或已过期","額度資料暫不可用或已過期") };
    public string RecoveryBody(QuotaSnapshot q)=>string.Join("; ",new[]{q.Primary,q.Secondary}.OfType<QuotaWindow>().Select(w=>copy.Period(w.WindowMinutes)+Text(" remaining ","额度剩余 ","額度剩餘 ")+w.RemainingPercent+"%"+(w.UsedPercent>=100?Text(" (still depleted)","（仍耗尽）","（仍耗盡）"):"")));
    public string BankBody(IReadOnlyList<BankExpiryEvent> events)=>string.Join("\n",events.GroupBy(e=>e.Stage).OrderByDescending(g=>g.Key).Select(g=>Text($"{g.Sum(e=>e.Count)} known reset credits expire within {g.Key} hours; earliest: ",$"已知 {g.Sum(e=>e.Count)} 次重置权益将在 {g.Key} 小时内到期，最近：",$"已知 {g.Sum(e=>e.Count)} 次重置權益將在 {g.Key} 小時內到期，最近：")+g.Min(e=>e.ExpiresAt).ToLocalTime().ToString("yyyy/MM/dd HH:mm")));
}
