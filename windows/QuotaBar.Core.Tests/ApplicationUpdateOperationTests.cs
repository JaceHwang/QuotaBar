using QuotaBar.Core;
internal static class ApplicationUpdateOperationTests {
    sealed class DeliveryContext : SynchronizationContext { public int Posts; public override void Post(SendOrPostCallback callback,object? state) { Interlocked.Increment(ref Posts); callback(state); } }
    sealed class PausedContext : SynchronizationContext {
        readonly System.Collections.Concurrent.ConcurrentQueue<Action> queue=new();
        public override void Post(SendOrPostCallback callback,object? state)=>queue.Enqueue(()=>callback(state));
        public void Flush() { while(queue.TryDequeue(out var next)) next(); }
    }
    public static async Task Run() {
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseCleanup=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cleaned=false;
        var quitting=new ApplicationUpdateOperation(async (_,_,cancel)=> { entered.SetResult(); try { await Task.Delay(Timeout.Infinite,cancel); } finally { await releaseCleanup.Task; } },abandon:_=>cleaned=true);
        quitting.Start("2.0.0"); await entered.Task;
        var cleanup=quitting.WaitForCleanup(); await Task.Delay(30);
        if(cleanup.IsCompleted || cleaned) throw new Exception("Quit completed before cancellation cleanup");
        releaseCleanup.SetResult(); await cleanup;
        if(!cleaned) throw new Exception("Quit skipped owned helper cleanup");
        var paused=new PausedContext(); var earlyPermits=0;
        var awaitingUi=new ApplicationUpdateOperation((_,_,_)=>Task.CompletedTask,paused,commit:_=>earlyPermits++);
        awaitingUi.Start("2.0.0"); await Task.Delay(40); if(earlyPermits!=0) throw new Exception("Helper permission committed before UI handoff");
        awaitingUi.Cancel(); paused.Flush(); await Task.Delay(40); if(earlyPermits!=0 || awaitingUi.Progress.Phase!=ApplicationUpdatePhase.Cancelled) throw new Exception("Queued handoff survived cancellation");
        var dispatch=new DeliveryContext(); var dispatched=new ApplicationUpdateOperation((_,_,_)=>Task.CompletedTask,dispatch); dispatched.Start("2.0.0"); await Task.Delay(30); if(dispatch.Posts<2) throw new Exception("Update events bypassed UI context");
        var count=0; var ready=0; var permits=0;
        var operation=new ApplicationUpdateOperation(async (_,emit,cancel)=> { Interlocked.Increment(ref count); emit(new(ApplicationUpdatePhase.Downloading,1,3,null)); await Task.Delay(150); },commit:_=>Interlocked.Increment(ref permits));
        operation.Ready+=()=>ready++;
        await Task.Delay(10); if(count!=0) throw new Exception("Update started without a click");
        operation.Start("2.0.0"); operation.Start("3.0.0"); if(operation.TargetVersion!="2.0.0") throw new Exception("Running target snapshot changed"); await Task.Delay(20); operation.Cancel(); await Task.Delay(200);
        if(permits!=0 || count!=1 || ready!=0 || operation.Progress.Phase!=ApplicationUpdatePhase.Cancelled) throw new Exception("Cancelled/double update installed");
        var failure=new ApplicationUpdateOperation((_,_,_)=>throw new IOException("fixture")); failure.Start("2.0.0"); await Task.Delay(30);
        if(failure.Progress.Phase!=ApplicationUpdatePhase.Failed) throw new Exception("Failure not retryable");
        var late=new ApplicationUpdateOperation((version,emit,cancel)=> { _=Task.Run(async ()=> { await Task.Delay(10); emit(new(ApplicationUpdatePhase.Downloading,1,2,null)); }); return Task.CompletedTask; });
        late.Start("2.0.0"); await Task.Delay(80); if(late.Progress.Phase!=ApplicationUpdatePhase.HandingOff) throw new Exception("Late progress reopened cancellation after ready");
        var result=new ApplicationUpdateOperation((_,_,_)=>Task.CompletedTask); result.ReportResult(ApplicationUpdatePhase.Succeeded);
        if(result.Progress.Phase!=ApplicationUpdatePhase.Succeeded) throw new Exception("Startup result was lost");
        Console.WriteLine("PASS explicit update click, duplicate guard, late cancellation and failure state");
    }
}
