using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using QuotaBar.Core;

static class AccountRegressionTests {
    public static async Task Run() {
        var failed=0; var transport=new ScriptedTransport(); var events=new ConcurrentQueue<RuntimeEvent>();
        await using var session=new RuntimeSession(()=>transport,requestTimeout:TimeSpan.FromMilliseconds(180)); session.Event+=events.Enqueue;
        await session.StartAsync(); await session.LoginAsync(); await session.CancelLoginAsync(); await session.LoginAsync();
        var before=events.Count;
        transport.Notify("{\"method\":\"account/login/completed\",\"params\":{\"loginId\":\"1\",\"success\":true}}"); await Task.Delay(40);
        Assert(!events.ToArray().Skip(before).Any(e=>e.Kind=="loginCompleted" && e.Success==true),"cancelled login A cannot complete login B");
        before=events.Count;
        transport.Notify("{\"method\":\"account/updated\",\"params\":{\"authMode\":\"chatgpt\"}}"); await Task.Delay(40);
        Assert(!events.ToArray().Skip(before).Any(e=>e.Kind=="quota"),"late account update cannot unlock pending login");
        transport.Notify("{\"method\":\"account/login/completed\",\"params\":{\"loginId\":\"2\",\"success\":true}}"); await Task.Delay(40);
        transport.HoldQuota=true;
        var refresh=session.RefreshAsync();
        for(var i=0;i<50 && !transport.HeldQuota;i++) await Task.Delay(5);
        Assert(transport.HeldQuota,"old request is actually pending before logout");
        await session.LogoutAsync(); before=events.Count; await refresh;
        Assert(!events.ToArray().Skip(before).Any(e=>e.Kind=="failure" && e.Method=="account/rateLimits/read"),"old quota timeout cannot replace logout state");
        before=events.Count;
        transport.Notify("{\"method\":\"account/updated\",\"params\":{\"authMode\":null}}"); await Task.Delay(40);
        Assert(events.ToArray().Skip(before).Any(e=>e.Kind=="cleared"),"authMode null clears account caches");
        var overlapTransport=new ScriptedTransport { HoldCancel=true }; var overlapEvents=new ConcurrentQueue<RuntimeEvent>();
        await using var overlap=new RuntimeSession(()=>overlapTransport,requestTimeout:TimeSpan.FromSeconds(1)); overlap.Event+=overlapEvents.Enqueue;
        await overlap.StartAsync(); await overlap.LoginAsync(); var cancel=overlap.CancelLoginAsync();
        for(var i=0;i<50 && overlapTransport.CancelId is null;i++) await Task.Delay(5);
        await overlap.LoginAsync();
        overlapTransport.Notify("{\"method\":\"account/login/completed\",\"params\":{\"loginId\":\"2\",\"success\":true}}"); await Task.Delay(40);
        before=overlapEvents.Count;
        overlapTransport.ReplyCancel(); await cancel;
        Assert(!overlapEvents.ToArray().Skip(before).Any(e=>e.Kind=="cleared" || e.Kind=="loggedOut" || e.Kind=="loginCompleted" && e.Success==false),"old cancellation response cannot clear new login");
        if(failed!=0) throw new Exception($"{failed} account regression failures");
        void Assert(bool pass,string name) { Console.WriteLine((pass?"PASS ":"FAIL ")+name); if(!pass) failed++; }
    }
    sealed class ScriptedTransport : ILineTransport {
        readonly Channel<string> lines=Channel.CreateUnbounded<string>(); int login;
        public volatile bool HoldQuota,HeldQuota;
        public bool HoldCancel;
        public long? CancelId;
        public Task StartAsync(CancellationToken ct)=>Task.CompletedTask;
        public IAsyncEnumerable<string> ReadLinesAsync(CancellationToken ct)=>lines.Reader.ReadAllAsync(ct);
        public void Notify(string line)=>lines.Writer.TryWrite(line);
        public Task SendAsync(string line,CancellationToken ct) {
            using var d=JsonDocument.Parse(line); var r=d.RootElement;
            if(!r.TryGetProperty("id",out var id)) return Task.CompletedTask;
            var method=r.GetProperty("method").GetString();
            if(method=="account/login/cancel" && HoldCancel) { CancelId=id.GetInt64(); return Task.CompletedTask; }
            if(method=="account/rateLimits/read" && HoldQuota) { HeldQuota=true; return Task.CompletedTask; }
            object result=method=="account/login/start" ? new { loginId=(++login).ToString(),authUrl="https://auth.openai.com/test" } : new { };
            if(method=="account/rateLimits/read") {
                using var fixture=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/rate-limits/read-response.json"))); result=fixture.RootElement.GetProperty("result").Clone();
            }
            Notify(JsonSerializer.Serialize(new { id=id.GetInt64(),result })); return Task.CompletedTask;
        }
        public ValueTask DisposeAsync() { lines.Writer.TryComplete(); return ValueTask.CompletedTask; }
        public void ReplyCancel() => Notify(JsonSerializer.Serialize(new { id=CancelId!.Value,result=new { } }));
    }
}
