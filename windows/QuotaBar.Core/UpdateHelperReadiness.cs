using System.Diagnostics;
namespace QuotaBar.Core;

public static class UpdateHelperReadiness {
    public static Task WaitAsync(Func<bool> ready,Func<bool> exited,CancellationToken cancel) {
        var clock=Stopwatch.StartNew();
        return WaitAsync(ready,exited,cancel,()=>clock.Elapsed,(duration,token)=>Task.Delay(duration,token));
    }
    internal static async Task WaitAsync(Func<bool> ready,Func<bool> exited,CancellationToken cancel,Func<TimeSpan> elapsed,Func<TimeSpan,CancellationToken,Task> delay) {
        while(!ready()) {
            cancel.ThrowIfCancellationRequested();
            if(exited()) throw new IOException("Update helper exited before becoming ready");
            // Rehashing and extracting a full package can exceed ten seconds on a healthy device.
            if(elapsed()>=TimeSpan.FromSeconds(120)) throw new IOException("Update helper readiness timed out");
            await delay(TimeSpan.FromMilliseconds(50),cancel);
        }
        cancel.ThrowIfCancellationRequested();
    }
}
