namespace QuotaBar.Core;
/// Owns one explicit update operation. Late callbacks from a cancelled generation are inert.
public sealed class ApplicationUpdateOperation(Func<string,Action<ApplicationUpdateProgress>,CancellationToken,Task> execute,SynchronizationContext? dispatch=null) {
    readonly object gate=new();
    readonly SynchronizationContext? context=dispatch??SynchronizationContext.Current;
    CancellationTokenSource? cancellation;
    long generation;
    ApplicationUpdateProgress progress=new(ApplicationUpdatePhase.Idle,0,0,null);
    public string? TargetVersion { get; private set; }
    public ApplicationUpdateProgress Progress { get { lock(gate) return progress; } }
    public event Action? Changed,Ready;
    static bool Busy(ApplicationUpdatePhase phase)=>phase is ApplicationUpdatePhase.Resolving or ApplicationUpdatePhase.Downloading or ApplicationUpdatePhase.Verifying or ApplicationUpdatePhase.Preparing or ApplicationUpdatePhase.HandingOff or ApplicationUpdatePhase.Installing;
    public static bool CanCancel(ApplicationUpdatePhase phase)=>phase is ApplicationUpdatePhase.Resolving or ApplicationUpdatePhase.Downloading or ApplicationUpdatePhase.Verifying or ApplicationUpdatePhase.Preparing;
    void Notify(Action? action) { if(context is null) action?.Invoke(); else context.Post(_=>action?.Invoke(),null); }
    public void Start(string version) {
        long id; CancellationTokenSource source;
        lock(gate) { if(Busy(progress.Phase)) return; id=++generation; TargetVersion=version; cancellation=source=new(); progress=new(ApplicationUpdatePhase.Resolving,0,0,null); }
        Notify(Changed);
        _=Task.Run(async ()=> {
            try {
                await execute(version,update=> { lock(gate) { if(id!=generation || !CanCancel(progress.Phase)) return; progress=update; } Notify(Changed); },source.Token);
                lock(gate) { if(id!=generation || source.IsCancellationRequested) return; progress=new(ApplicationUpdatePhase.HandingOff,0,0,null); cancellation=null; }
                Notify(Changed); Notify(Ready);
            } catch {
                lock(gate) { if(id!=generation) return; progress=new(source.IsCancellationRequested?ApplicationUpdatePhase.Cancelled:ApplicationUpdatePhase.Failed,0,0,null); cancellation=null; }
                Notify(Changed);
            } finally { source.Dispose(); }
        });
    }
    public void ReportResult(ApplicationUpdatePhase phase) {
        if(phase is not (ApplicationUpdatePhase.Succeeded or ApplicationUpdatePhase.RolledBack or ApplicationUpdatePhase.Failed)) return;
        lock(gate) { if(progress.Phase!=ApplicationUpdatePhase.Idle) return; progress=new(phase,0,0,null); }
        Notify(Changed);
    }
    public void Cancel() {
        lock(gate) { if(!CanCancel(progress.Phase)) return; generation++; cancellation?.Cancel(); cancellation=null; progress=new(ApplicationUpdatePhase.Cancelled,0,0,null); }
        Notify(Changed);
    }
}
