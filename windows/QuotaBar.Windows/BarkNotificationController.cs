using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using QuotaBar.Core;

namespace QuotaBar.Windows;
internal enum BarkStatus { NotConfigured,Configured,StorageUnavailable,Sending,Accepted,Rejected,Unknown,InvalidKey,PersistenceUnavailable,HistoryRecovery }
internal sealed class BarkNotificationController : IDisposable {
    sealed record Work(ExperienceNotification Message,Func<ExperienceNotification,bool> Valid,Action<ExperienceNotification> Accepted,string Configuration,CancellationTokenSource Cancellation);
    readonly IBarkSecretStore secrets;
    readonly IBarkPushClient client;
    readonly BarkDeliveryStore deliveries;
    readonly Action<BarkPreferences> save;
    readonly Queue<Work> queue=new();
    readonly HashSet<BarkEventIdentity> pendingBaseline=[];
    readonly Dictionary<BarkEventIdentity,ExperienceNotification> known=[];
    readonly object gate=new();
    readonly SemaphoreSlim transportGate=new(1,1);
    readonly Dictionary<BarkEventIdentity,Func<ExperienceNotification,bool>> validators=[];
    Work? active;
    CancellationTokenSource? test;
    Task idle=Task.CompletedTask;
    bool pumping,stopped;
    public BarkPreferences Preferences { get; private set; }
    public BarkStatus Status { get; private set; }
    public DateTimeOffset? LastOperation { get; private set; }
    public bool HasKey { get; private set; }
    public bool Testing=>test is not null;
    public event Action? Changed;
    public Task WhenIdle { get { lock(gate) return idle; } }
    public Func<IEnumerable<ExperienceNotification>>? CurrentMessages { get; set; }
    public BarkNotificationController(IBarkSecretStore secrets,IBarkPushClient client,BarkDeliveryStore deliveries,BarkPreferences preferences,Action<BarkPreferences> save) {
        this.secrets=secrets; this.client=client; this.deliveries=deliveries; this.save=save; Preferences=preferences.Validated(); if(Preferences.Enabled) RefreshSecretStatus(); else Status=BarkStatus.NotConfigured; if(deliveries.NeedsBaseline) { Preferences=Preferences with { Enabled=false }; PersistPreferences(); Status=BarkStatus.HistoryRecovery; }
    }
    static BarkEventIdentity Identity(ExperienceNotification message)=>new(message.Id,message.ReminderGeneration);
    void SetStatus(BarkStatus value) { Status=value; LastOperation=DateTimeOffset.UtcNow; Changed?.Invoke(); }
    public void RefreshConfiguration() { lock(gate) { if(stopped) return; RefreshSecretStatus(); Changed?.Invoke(); } }
    void RefreshSecretStatus() {
        var secret=secrets.Read(); HasKey=secret.State==BarkSecretState.Available;
        if(active is not null||test is not null) return;
        Status=secret.State switch { BarkSecretState.Available=>BarkStatus.Configured,BarkSecretState.Missing=>BarkStatus.NotConfigured,_=>BarkStatus.StorageUnavailable };
    }
    void CancelAll() {
        active?.Cancellation.Cancel(); foreach(var item in queue) { item.Cancellation.Cancel(); item.Cancellation.Dispose(); } queue.Clear(); test?.Cancel();
    }
    bool PersistPreferences() {
        try { save(Preferences); return true; } catch(Exception error) when(error is System.IO.IOException or UnauthorizedAccessException) { Preferences=Preferences with { Enabled=false }; CancelAll(); SetStatus(BarkStatus.PersistenceUnavailable); return false; }
    }
    void Prune() {
        var now=DateTimeOffset.UtcNow;
        foreach(var identity in known.Where(pair=>!pair.Value.Valid(now)||validators.TryGetValue(pair.Key,out var valid)&&!valid(pair.Value)).Select(pair=>pair.Key).ToArray()) { known.Remove(identity); validators.Remove(identity); }
    }
    bool Baseline() {
        var now=DateTimeOffset.UtcNow;
        foreach(var item in CurrentMessages?.Invoke()??[]) if(item.Kind!=ExperienceNotificationKind.Test) known[Identity(item)]=item;
        Prune();
        pendingBaseline.UnionWith(known.Keys);
        if(deliveries.EstablishBaseline(pendingBaseline,now)) { pendingBaseline.Clear(); return true; }
        Preferences=Preferences with { Enabled=false }; CancelAll(); PersistPreferences(); SetStatus(BarkStatus.PersistenceUnavailable); return false;
    }
    // Called only by the explicit reveal control. Never persist or cache the returned secret.
    public string? RevealKeyForUser() { lock(gate) { if(stopped) return null; var value=secrets.Read(); if(value.State!=BarkSecretState.Available) { SetStatus(value.State==BarkSecretState.Missing?BarkStatus.NotConfigured:BarkStatus.StorageUnavailable); return null; } return value.Key; } }
    public bool SaveKey(string draft) {
        lock(gate) {
            if(stopped) return false;
            if(!BarkPayload.IsValidDeviceKey(draft)) { SetStatus(BarkStatus.InvalidKey); return false; }
            if(!secrets.Write(draft.Trim())) { SetStatus(BarkStatus.StorageUnavailable); return false; }
            CancelAll(); Preferences=Preferences with { ConfigurationGeneration=Guid.NewGuid().ToString() }; HasKey=true; if(!Baseline()||!PersistPreferences()) return false; SetStatus(BarkStatus.Configured); return true;
        }
    }
    public bool ClearKey() {
        lock(gate) {
            if(stopped) return false;
            CancelAll(); var cleared=secrets.Clear(); Preferences=Preferences with { Enabled=false,ConfigurationGeneration=Guid.NewGuid().ToString() }; var persisted=PersistPreferences(); HasKey=!cleared; if(!Baseline()) return false; SetStatus(cleared?BarkStatus.NotConfigured:BarkStatus.StorageUnavailable); return cleared&&persisted;
        }
    }
    public bool SetEnabled(bool enabled) {
        lock(gate) {
            if(stopped) return false;
            if(enabled) { RefreshSecretStatus(); if(!HasKey) { Changed?.Invoke(); return false; } }
            if(Preferences.Enabled==enabled) return true;
            CancelAll(); Preferences=Preferences with { Enabled=enabled,ConfigurationGeneration=Guid.NewGuid().ToString() }; if(!Baseline()||!PersistPreferences()) return false; Changed?.Invoke(); return true;
        }
    }
    public void Enqueue(ExperienceNotification message,Func<ExperienceNotification,bool> valid,Action<ExperienceNotification> accepted) {
        lock(gate) {
            if(stopped||message.Kind==ExperienceNotificationKind.Test) return;
            Prune(); var identity=Identity(message); if(known.Count<256||known.ContainsKey(identity)) { known[identity]=message; validators[identity]=valid; }
            if(deliveries.NeedsBaseline) { Baseline(); return; }
            if(pendingBaseline.Count>0) { if(!deliveries.EstablishBaseline(pendingBaseline,DateTimeOffset.UtcNow)) { SetStatus(BarkStatus.PersistenceUnavailable); return; } pendingBaseline.Clear(); }
            if(!Preferences.Enabled||!HasKey||!valid(message)||!message.Valid(DateTimeOffset.UtcNow)||queue.Count+(active is null?0:1)>=32||active is { } current&&Identity(current.Message)==identity||queue.Any(item=>Identity(item.Message)==identity)) return;
            queue.Enqueue(new(message,valid,accepted,Preferences.ConfigurationGeneration,new()));
            if(!pumping) { pumping=true; idle=Pump(); }
        }
    }
    async Task Pump() {
        while(true) {
            Work item;
            lock(gate) {
                if(stopped||queue.Count==0) { active=null; pumping=false; return; }
                item=queue.Dequeue(); active=item;
                if(!Eligible(item)||!deliveries.Reserve(Identity(item.Message),DateTimeOffset.UtcNow,known.Keys.ToHashSet())) { if(deliveries.HasPersistenceError) SetStatus(BarkStatus.PersistenceUnavailable); item.Cancellation.Dispose(); active=null; continue; }
                SetStatus(BarkStatus.Sending);
            }
            BarkPushResult result;
            try {
                await transportGate.WaitAsync(item.Cancellation.Token);
                try {
                    lock(gate) { if(!Eligible(item)) { item.Cancellation.Cancel(); } }
                    var secret=secrets.Read();
                    result=item.Cancellation.IsCancellationRequested?BarkPushResult.Cancelled:secret.State==BarkSecretState.Available&&secret.Key is { } key?await client.Send(key,item.Message.Title,item.Message.Body,item.Cancellation.Token):BarkPushResult.Unavailable;
                } finally { transportGate.Release(); }
            } catch(OperationCanceledException) { result=BarkPushResult.Cancelled; }
            lock(gate) {
                if(Eligible(item)) {
                    if(result==BarkPushResult.Accepted) { deliveries.MarkAccepted(Identity(item.Message),DateTimeOffset.UtcNow); item.Accepted(item.Message); }
                    SetStatus(Map(result));
                }
                if(ReferenceEquals(active,item)) active=null;
                item.Cancellation.Dispose();
            }
        }
    }
    bool Eligible(Work item)=>!stopped&&!item.Cancellation.IsCancellationRequested&&Preferences.Enabled&&item.Configuration==Preferences.ConfigurationGeneration&&item.Message.Valid(DateTimeOffset.UtcNow)&&item.Valid(item.Message);
    static BarkStatus Map(BarkPushResult result)=>result switch { BarkPushResult.Accepted=>BarkStatus.Accepted,BarkPushResult.Rejected=>BarkStatus.Rejected,BarkPushResult.Unavailable=>BarkStatus.StorageUnavailable,BarkPushResult.InvalidKey=>BarkStatus.InvalidKey,_=>BarkStatus.Unknown };
    public async Task<BarkPushResult> Test(string title,string body) {
        CancellationTokenSource operation; string generation;
        lock(gate) { if(stopped||test is not null) return BarkPushResult.Cancelled; var value=secrets.Read(); if(value.State!=BarkSecretState.Available) { SetStatus(BarkStatus.StorageUnavailable); return BarkPushResult.Unavailable; } operation=new(); test=operation; generation=Preferences.ConfigurationGeneration; SetStatus(BarkStatus.Sending); }
        try {
            await transportGate.WaitAsync(operation.Token);
            BarkPushResult result;
            try { var secret=secrets.Read(); result=secret.Key is { } key?await client.Send(key,title,body,operation.Token):BarkPushResult.Unavailable; } finally { transportGate.Release(); }
            lock(gate) { if(!stopped&&!operation.IsCancellationRequested&&generation==Preferences.ConfigurationGeneration) SetStatus(Map(result)); }
            return result;
        } catch(OperationCanceledException) { return BarkPushResult.Cancelled; } finally { lock(gate) { if(ReferenceEquals(test,operation)) test=null; operation.Dispose(); if(!stopped) Changed?.Invoke(); } }
    }
    public void Cancel(string id) { lock(gate) { if(active?.Message.Id==id) active.Cancellation.Cancel(); foreach(var item in queue.Where(item=>item.Message.Id==id)) item.Cancellation.Cancel(); foreach(var key in known.Where(pair=>pair.Value.Id==id).Select(pair=>pair.Key).ToArray()) { known.Remove(key); validators.Remove(key); } } }
    public void CancelAuthenticationEpoch(string epoch) { lock(gate) { if(active?.Message.Epoch==epoch) active.Cancellation.Cancel(); foreach(var item in queue.Where(item=>item.Message.Epoch==epoch)) item.Cancellation.Cancel(); foreach(var key in known.Where(pair=>pair.Value.Epoch==epoch).Select(pair=>pair.Key).ToArray()) { known.Remove(key); validators.Remove(key); } } }
    public void Revalidate() { lock(gate) { Prune(); if(active is { } item&&(!item.Valid(item.Message)||!item.Message.Valid(DateTimeOffset.UtcNow))) item.Cancellation.Cancel(); foreach(var work in queue.Where(work=>!work.Valid(work.Message)||!work.Message.Valid(DateTimeOffset.UtcNow))) work.Cancellation.Cancel(); } }
    public void Dispose() { lock(gate) { if(stopped) return; stopped=true; CancelAll(); if(client is IDisposable disposable) disposable.Dispose(); } }
}
