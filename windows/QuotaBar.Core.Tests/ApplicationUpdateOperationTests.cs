using QuotaBar.Core;
internal static class ApplicationUpdateOperationTests {
    public static async Task Run() {
        var count=0; var ready=0;
        var operation=new ApplicationUpdateOperation(async (_,emit,cancel)=> { Interlocked.Increment(ref count); emit(new(ApplicationUpdatePhase.Downloading,1,3,null)); await Task.Delay(150); });
        operation.Ready+=()=>ready++;
        await Task.Delay(10); if(count!=0) throw new Exception("Update started without a click");
        operation.Start("2.0.0"); operation.Start("2.0.0"); await Task.Delay(20); operation.Cancel(); await Task.Delay(200);
        if(count!=1 || ready!=0 || operation.Progress.Phase!=ApplicationUpdatePhase.Cancelled) throw new Exception("Cancelled/double update installed");
        var failure=new ApplicationUpdateOperation((_,_,_)=>throw new IOException("fixture")); failure.Start("2.0.0"); await Task.Delay(30);
        if(failure.Progress.Phase!=ApplicationUpdatePhase.Failed) throw new Exception("Failure not retryable");
        var late=new ApplicationUpdateOperation((version,emit,cancel)=> { _=Task.Run(async ()=> { await Task.Delay(10); emit(new(ApplicationUpdatePhase.Downloading,1,2,null)); }); return Task.CompletedTask; });
        late.Start("2.0.0"); await Task.Delay(80); if(late.Progress.Phase!=ApplicationUpdatePhase.HandingOff) throw new Exception("Late progress reopened cancellation after ready");
        Console.WriteLine("PASS explicit update click, duplicate guard, late cancellation and failure state");
    }
}
