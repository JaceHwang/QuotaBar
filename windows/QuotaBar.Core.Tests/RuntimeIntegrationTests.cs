using System.Collections.Concurrent;
using QuotaBar.Core;

static class RuntimeIntegrationTests {
    public static async Task Run(string executable) {
        var home=Path.Combine(Path.GetTempPath(),"quotabar-isolated-protocol-"+Guid.NewGuid());
        var events=new ConcurrentQueue<RuntimeEvent>();
        var processId=0;
        try {
            await using var session=new RuntimeSession(()=>new ProcessTransport(executable,home,p=>processId=p.Id)); session.Event+=events.Enqueue;
            await session.StartAsync(); await session.RefreshAsync();
            var authFailure=events.FirstOrDefault(e=>e.Kind=="failure" && e.Method=="account/rateLimits/read");
            if(authFailure is null) throw new Exception("Fresh isolated account must require login");
            var state=new RefreshState(); state.Error(authFailure.Method!,authFailure.Message??"");
            if(state.Phase!=Phase.NeedsLogin) throw new Exception("Official unauthenticated response was not classified as needsLogin");
            await session.DisposeAsync();
            try {
                using var process=System.Diagnostics.Process.GetProcessById(processId);
                if(!process.HasExited) throw new Exception("Owned official runtime did not exit");
            } catch(ArgumentException) { }
            Console.WriteLine("PASS official runtime stdio handshake, isolated account and unauthenticated quota response");
        } finally { if(Directory.Exists(home)) Directory.Delete(home,true); }
    }
}
