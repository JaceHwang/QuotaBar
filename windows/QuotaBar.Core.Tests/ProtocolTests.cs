using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using QuotaBar.Core;

static class ProtocolTests {
    public static async Task Run() {
        var transport=new FakeTransport(); var events=new ConcurrentQueue<RuntimeEvent>();
        await using var session=new RuntimeSession(()=>transport,requestTimeout:TimeSpan.FromMilliseconds(120));
        session.Event+=events.Enqueue;
        await session.StartAsync();
        Check(transport.Methods.Contains("initialized"),"initialization handshake");
        await session.RefreshAsync(); Check(events.Any(e=>e.Quota?.Primary.RemainingPercent==76),"quota event");
        transport.HoldQuota=true;
        var read=session.RefreshAsync(); await Until(()=>transport.HeldId!=null);
        await session.LogoutAsync();
        transport.ReplyQuota(transport.HeldId!.Value); await read;
        var clearIndex=events.ToArray().ToList().FindLastIndex(e=>e.Kind=="cleared");
        Check(!events.ToArray().Skip(clearIndex+1).Any(e=>e.Kind=="quota"),"late quota after logout ignored");
        await session.LoginAsync(); Check(events.Any(e=>e.Kind=="loginUrl"),"official browser URL");
        var queuedUrl=events.Last(e=>e.Kind=="loginUrl");
        await session.CancelLoginAsync(); Check(events.Any(e=>e.Kind=="loginCompleted" && e.Success==false),"cancel completes state");
        Check(!session.IsCurrentEvent(queuedUrl),"queued UI callback from cancelled login is stale");
        var count=events.Count;
        transport.Notify("{\"method\":\"account/login/completed\",\"params\":{\"success\":true}}");
        await Task.Delay(30);
        Check(!events.ToArray().Skip(count).Any(e=>e.Kind=="loginCompleted" && e.Success==true),"late login completion after cancel ignored");
        transport.HoldLogin=true;
        await session.LoginAsync(); Check(events.Any(e=>e.Kind=="failure" && e.Method=="account/login/start"),"timeout surfaced");
        var attempts=0;
        await using var broken=new RuntimeSession(()=> { attempts++; return new FailingTransport(); },restartDelays:[TimeSpan.Zero,TimeSpan.Zero,TimeSpan.Zero]);
        try { await broken.StartAsync(); throw new Exception("Expected exhausted initialization"); } catch(IOException) { }
        Check(attempts==4 && broken.RestartAttempts==3,"initialization uses bounded recovery");
    }
    static void Check(bool b,string m) { if(!b) throw new Exception(m); }
    static async Task Until(Func<bool> ready) { for(var i=0;i<100;i++) { if(ready()) return; await Task.Delay(5); } throw new Exception("fake transport wait timeout"); }
    sealed class FakeTransport : ILineTransport {
        readonly Channel<string> output=Channel.CreateUnbounded<string>();
        public ConcurrentBag<string> Methods { get; }=[];
        public bool HoldQuota,HoldLogin;
        public long? HeldId;
        public Task StartAsync(CancellationToken ct)=>Task.CompletedTask;
        public IAsyncEnumerable<string> ReadLinesAsync(CancellationToken ct)=>output.Reader.ReadAllAsync(ct);
        public Task SendAsync(string line,CancellationToken ct) {
            using var d=JsonDocument.Parse(line); var r=d.RootElement; var method=r.GetProperty("method").GetString()!; Methods.Add(method);
            if(!r.TryGetProperty("id",out var id)) return Task.CompletedTask;
            var n=id.GetInt64();
            if(method=="account/rateLimits/read") { if(HoldQuota) HeldId=n; else ReplyQuota(n); }
            else if(method=="account/login/start") {
                if(!HoldLogin) output.Writer.TryWrite(JsonSerializer.Serialize(new { id=n,result=new { loginId="test-login",authUrl="https://auth.openai.com/test" } }));
            } else output.Writer.TryWrite(JsonSerializer.Serialize(new { id=n,result=new { } }));
            return Task.CompletedTask;
        }
        public void Notify(string line)=>output.Writer.TryWrite(line);
        public void ReplyQuota(long id) {
            var fixture=File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/rate-limits/read-response.json"));
            using var d=JsonDocument.Parse(fixture); output.Writer.TryWrite(JsonSerializer.Serialize(new { id,result=d.RootElement.GetProperty("result") }));
        }
        public ValueTask DisposeAsync() { output.Writer.TryComplete(); return ValueTask.CompletedTask; }
    }
    sealed class FailingTransport : ILineTransport {
        public Task StartAsync(CancellationToken ct)=>throw new IOException("injected start failure");
        public Task SendAsync(string line,CancellationToken ct)=>Task.CompletedTask;
        public async IAsyncEnumerable<string> ReadLinesAsync([System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct) { await Task.CompletedTask; yield break; }
        public ValueTask DisposeAsync()=>ValueTask.CompletedTask;
    }
}
