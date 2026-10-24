namespace QuotaBar.Core;
/// Original eligibility can shrink, never expand on a later settings change.
public sealed class NotificationDeliverySnapshot(NotificationCategory category,NotificationPolicyPreferences preferences,DateTimeOffset now) {
 readonly HashSet<NotificationChannel> eligible=Enum.GetValues<NotificationChannel>().Where(c=>NotificationPolicy.Decision(category,c,preferences,now)==NotificationDecision.Allowed).ToHashSet();
 readonly HashSet<NotificationChannel> accepted=[];
 public void Restrict(NotificationPolicyPreferences policy,DateTimeOffset time)=>eligible.RemoveWhere(c=>NotificationPolicy.Decision(category,c,policy,time)!=NotificationDecision.Allowed);
 public bool Eligible(NotificationChannel channel)=>eligible.Contains(channel);
 public bool Allows(NotificationChannel channel,NotificationPolicyPreferences policy,DateTimeOffset time)=>eligible.Contains(channel)&&!accepted.Contains(channel)&&NotificationPolicy.Decision(category,channel,policy,time)==NotificationDecision.Allowed;
 public void RecordAccepted(NotificationChannel channel)=>accepted.Add(channel);
}
