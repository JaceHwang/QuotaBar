using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace QuotaBar.Core;

public interface ILineTransport : IAsyncDisposable {
    Task StartAsync(CancellationToken ct);
    Task SendAsync(string line,CancellationToken ct);
    IAsyncEnumerable<string> ReadLinesAsync(CancellationToken ct);
}

public sealed class ProcessTransport(string executable,string codexHome,Action<Process>? processStarted=null,Action<string>? disposalStage=null) : ILineTransport {
    private Process? process;
    private Task? drain;
    private readonly SemaphoreSlim writes=new(1,1);
    private readonly SemaphoreSlim disposal=new(1,1);
    public Task StartAsync(CancellationToken ct) {
        Directory.CreateDirectory(codexHome);
        var info=new ProcessStartInfo(executable) {
            UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,
            RedirectStandardOutput=true,RedirectStandardError=true,
            StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8,
            WorkingDirectory=codexHome
        };
        info.ArgumentList.Add("app-server");
        info.Environment["CODEX_HOME"]=codexHome;
        foreach(var key in new[]{"OPENAI_API_KEY","CODEX_API_KEY"}) info.Environment.Remove(key);
        process=new Process { StartInfo=info };
        if(!process.Start()) throw new IOException("Runtime failed to start");
        try { processStarted?.Invoke(process); }
        catch { process.Kill(entireProcessTree:true); process.Dispose(); process=null; throw; }
        var active=process;
        drain=Task.Run(async()=> {
            try { while(await active.StandardError.ReadLineAsync() is not null) { } }
            catch(Exception e) when(e is IOException or InvalidOperationException or ObjectDisposedException) { }
        },CancellationToken.None);
        return Task.CompletedTask;
    }
    public async Task SendAsync(string line,CancellationToken ct) {
        await writes.WaitAsync(ct);
        try {
            if(process is null || process.HasExited) throw new IOException("Runtime unavailable");
            await process.StandardInput.WriteLineAsync(line.AsMemory(),ct);
            await process.StandardInput.FlushAsync(ct);
        } finally { writes.Release(); }
    }
    public async IAsyncEnumerable<string> ReadLinesAsync([EnumeratorCancellation] CancellationToken ct) {
        var current=process ?? throw new IOException("Runtime not started");
        while(await current.StandardOutput.ReadLineAsync(ct) is string line) {
            if(line.Length>2*1024*1024) throw new IOException("Runtime response too large");
            yield return line;
        }
    }
    public async ValueTask DisposeAsync() {
        await disposal.WaitAsync();
        try {
        var current=process; if(current is null) return;
        try {
            disposalStage?.Invoke("transport-stdin-closing");
            try { current.StandardInput.Close(); } catch(IOException) { }
            disposalStage?.Invoke("transport-waiting-exit");
            using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(1));
            try { await current.WaitForExitAsync(timeout.Token); }
            catch(OperationCanceledException) { if(!current.HasExited) current.Kill(entireProcessTree:true); await current.WaitForExitAsync(); }
        } catch(InvalidOperationException) { }
        finally {
            disposalStage?.Invoke("transport-draining-stderr");
            // Descendants can inherit stderr after the runtime parent has exited.
            // Drain briefly, then close our reader rather than waiting for their lifetime.
            if(drain is not null) try { await drain.WaitAsync(TimeSpan.FromSeconds(1)); }
            catch(TimeoutException) { current.StandardError.Close(); }
            current.Dispose(); process=null; disposalStage?.Invoke("transport-disposed");
        }
        } finally { disposal.Release(); }
    }
}

public sealed record RuntimeEvent(string Kind,QuotaSnapshot? Quota=null,TokenUsage? Tokens=null,AccountIdentity? Account=null,string? Method=null,string? Message=null,Uri? LoginUrl=null,bool? Success=null,long? AccountEpoch=null);

public sealed class RuntimeSession(Func<ILineTransport> factory,TimeSpan? requestTimeout=null,IReadOnlyList<TimeSpan>? restartDelays=null) : IAsyncDisposable {
    private sealed record Pending(string Method,long Epoch,TaskCompletionSource<JsonElement> Completion);
    private readonly ConcurrentDictionary<long,Pending> pending=new();
    private readonly CancellationTokenSource lifetime=new();
    private readonly SemaphoreSlim refreshGate=new(1,1),sessionGate=new(1,1);
    private readonly TimeSpan timeout=requestTimeout??TimeSpan.FromSeconds(20);
    private readonly IReadOnlyList<TimeSpan> delays=restartDelays??[TimeSpan.FromMilliseconds(500),TimeSpan.FromSeconds(2),TimeSpan.FromSeconds(5)];
    private ILineTransport? transport;
    private Task? reader,recovery;
    private long sequence,epoch,sessionNumber,quotaNotificationSerial;
    private volatile bool refreshNeeded;
    private long loginEpoch=-1;
    private readonly object accountGate=new();
    private bool stopping,initialized,suppressAccount;
    private string? loginId;
    private QuotaSnapshot? previous;
    public int RestartAttempts { get; private set; }
    public event Action<RuntimeEvent>? Event;
    public bool IsCurrentEvent(RuntimeEvent value)=>value.AccountEpoch is null || value.AccountEpoch==Volatile.Read(ref epoch);
    public async Task StartAsync() {
        Exception? failure=null; ILineTransport? failed=null; long number=0;
        await sessionGate.WaitAsync(lifetime.Token);
        try { if(transport is null) await StartSessionAsync(); }
        catch(Exception e) when(Recoverable(e)) { failure=e; failed=transport; number=sessionNumber; }
        finally { sessionGate.Release(); }
        if(failure is not null) {
            if(failed is not null) await RecoverAsync(failed,number);
            if(!initialized) throw new IOException("Runtime initialization failed after bounded recovery",failure);
        }
    }
    private async Task StartSessionAsync() {
        var next=factory(); transport=next; initialized=false;
        var number=Interlocked.Increment(ref sessionNumber);
        await next.StartAsync(lifetime.Token);
        reader=ReadAsync(next,number);
        await RequestAsync("initialize",new { clientInfo=new { name="quotabar",title="QuotaBar",version="1.0.0" },capabilities=new { experimentalApi=true,requestAttestation=false } });
        if(transport!=next || number!=sessionNumber) throw new IOException("Runtime disconnected during initialization");
        await next.SendAsync(JsonSerializer.Serialize(new { method="initialized" }),lifetime.Token);
        initialized=true;
    }
    public async Task RefreshAsync() {
        if(!initialized || suppressAccount || !await refreshGate.WaitAsync(0,lifetime.Token)) return;
        refreshNeeded=false;
        try { await Task.WhenAll(ReadQuotaAsync(),ReadTokensAsync(),ReadAccountAsync()); }
        finally { refreshGate.Release(); if(refreshNeeded && !stopping && !suppressAccount) _=RefreshAsync(); }
    }
    private async Task ReadQuotaAsync() {
        var current=Volatile.Read(ref epoch);
        var notification=Volatile.Read(ref quotaNotificationSerial);
        try {
            var result=await RequestAsync("account/rateLimits/read");
            var snapshot=QuotaDecoder.Decode(result.GetRawText());
            lock(accountGate) {
                if(current!=epoch || suppressAccount) return;
                if(notification!=quotaNotificationSerial && previous is not null) snapshot=previous.MergeSupplementary(snapshot);
                previous=snapshot; Emit(new("quota",Quota:snapshot));
            }
        } catch(Exception e) when(Recoverable(e)) { lock(accountGate) { if(current==epoch && !suppressAccount) Fail("account/rateLimits/read",e is FormatException ? new IOException("Unsupported quota response",e) : e); } }
    }
    private async Task ReadTokensAsync() {
        var current=Volatile.Read(ref epoch);
        try {
            var result=await RequestAsync("account/usage/read");
            var tokens=TokenDecoder.Decode(result.GetRawText());
            lock(accountGate) { if(current==epoch && !suppressAccount) Emit(new("tokens",Tokens:tokens)); }
        } catch(Exception e) when(Recoverable(e)) { lock(accountGate) { if(current==epoch && !suppressAccount) Emit(new("tokensUnavailable")); } }
    }
    private async Task ReadAccountAsync() {
        var current=Volatile.Read(ref epoch);
        try {
            var result=await RequestAsync("account/read",new { });
            lock(accountGate) { if(current==epoch && !suppressAccount) Emit(new("account",Account:AccountDecoder.Decode(result))); }
        } catch(Exception e) when(Recoverable(e)) { }
    }
    private void ClearAccount() { lock(accountGate) { Interlocked.Increment(ref epoch); suppressAccount=true; previous=null; loginEpoch=-1; refreshNeeded=false; Emit(new("cleared")); } }
    public async Task LoginAsync() {
        ClearAccount();
        var current=epoch; loginEpoch=current;
        try {
            var result=await RequestAsync("account/login/start",new { type="chatgpt" });
            lock(accountGate) {
                if(current!=epoch || loginEpoch!=current) return;
                loginId=result.Get("loginId").String();
                if(Uri.TryCreate(result.Get("authUrl").String(),UriKind.Absolute,out var url) && url.Scheme=="https" && (url.Host=="auth.openai.com" || url.Host=="auth0.openai.com" || url.Host=="chatgpt.com")) Emit(new("loginUrl",LoginUrl:url));
                else throw new FormatException("Unsupported login URL");
            }
        } catch(Exception e) when(Recoverable(e)) { lock(accountGate) { if(current==epoch) { Fail("account/login/start",e); Emit(new("loginCompleted",Success:false)); } } }
    }
    public async Task CancelLoginAsync() {
        var id=loginId; ClearAccount(); loginId=null;
        var current=epoch;
        Emit(new("loginCompleted",Success:false));
        if(id is not null) {
            try { await RequestAsync("account/login/cancel",new { loginId=id }); }
            catch(Exception e) when(Recoverable(e)) { lock(accountGate) { if(current==epoch) Fail("account/login/cancel",e); } }
        }
    }
    public async Task LogoutAsync() {
        ClearAccount(); loginId=null;
        var current=epoch; Emit(new("loggedOut"));
        try { await RequestAsync("account/logout"); }
        catch(Exception e) when(Recoverable(e)) { lock(accountGate) { if(current==epoch) Fail("account/logout",e); } }
    }
    private async Task<JsonElement> RequestAsync(string method,object? parameters=null) {
        var active=transport??throw new IOException("Runtime transport unavailable");
        var id=Interlocked.Increment(ref sequence);
        var item=new Pending(method,Volatile.Read(ref epoch),new(TaskCreationOptions.RunContinuationsAsynchronously));
        pending[id]=item;
        try {
            await active.SendAsync(JsonSerializer.Serialize(new { id,method,@params=parameters }),lifetime.Token);
            return await item.Completion.Task.WaitAsync(timeout,lifetime.Token);
        } catch(TimeoutException) { throw new IOException("Request timeout"); }
        finally { pending.TryRemove(id,out _); }
    }
    private async Task ReadAsync(ILineTransport active,long number) {
        try {
            await foreach(var line in active.ReadLinesAsync(lifetime.Token)) {
                if(number!=sessionNumber) return;
                try {
                    using var doc=JsonDocument.Parse(line); var root=doc.RootElement;
                    if(root.Get("id").Integer() is long id && pending.TryRemove(id,out var item)) {
                        if(root.Get("error").HasValue()) item.Completion.TrySetException(new IOException(root.Get("error").Get("message").String()??"Request failed"));
                        else {
                            var result=root.Get("result").Clone();
                            if(item.Method=="account/login/start") lock(accountGate) { if(item.Epoch==epoch && loginEpoch==epoch) loginId=result.Get("loginId").String(); }
                            item.Completion.TrySetResult(result);
                        }
                    } else if(root.Get("method").String()=="account/rateLimits/updated" && !suppressAccount) {
                        lock(accountGate) {
                            if(suppressAccount) continue;
                            var snapshot=QuotaDecoder.Decode(line,notification:true).MergeSupplementary(previous); previous=snapshot;
                            Interlocked.Increment(ref quotaNotificationSerial); refreshNeeded=true;
                            Emit(new("quota",Quota:snapshot));
                        }
                        _=RefreshAsync();
                    } else if(root.Get("method").String()=="account/login/completed") {
                        var success=root.Get("params").Get("success").Boolean();
                        lock(accountGate) {
                            if(loginEpoch!=epoch) continue;
                            var notificationId=root.Get("params").Get("loginId").String();
                            if(notificationId is not null && notificationId!=loginId) continue;
                            loginId=null; loginEpoch=-1; suppressAccount=!success; Emit(new("loginCompleted",Success:success));
                        }
                        if(success) _=RefreshAsync();
                    } else if(root.Get("method").String()=="account/updated") {
                        var mode=root.Get("params").Get("authMode");
                        if(mode.ValueKind==JsonValueKind.Null) {
                            lock(accountGate) {
                                if(loginEpoch==epoch) { previous=null; suppressAccount=true; Emit(new("cleared")); }
                                else { ClearAccount(); Emit(new("loggedOut")); }
                            }
                        }
                        else if(mode.HasValue()) {
                            lock(accountGate) {
                                if(suppressAccount) continue;
                                ClearAccount();
                                suppressAccount=false;
                            }
                            _=RefreshAsync();
                        } else if(!suppressAccount) _=ReadAccountAsync();
                    }
                } catch(Exception e) when(e is JsonException or FormatException) { /* malformed notification is local degradation */ }
            }
        } catch(Exception e) when(Recoverable(e)) { }
        if(stopping || number!=sessionNumber) return;
        initialized=false;
        foreach(var pair in pending) if(pending.TryRemove(pair.Key,out var p)) p.Completion.TrySetException(new IOException("Runtime transport unavailable"));
        Emit(new("failure",Method:"initialize",Message:"Runtime transport unavailable"));
        recovery=RecoverAsync(active,number);
    }
    private async Task RecoverAsync(ILineTransport failed,long number) {
        await Task.Yield();
        await sessionGate.WaitAsync(lifetime.Token);
        try {
            if(stopping || number!=sessionNumber) return;
            await failed.DisposeAsync(); transport=null;
            while(RestartAttempts<delays.Count && !stopping) {
                await Task.Delay(delays[RestartAttempts++],lifetime.Token);
                try { await StartSessionAsync(); await RefreshAsync(); return; }
                catch(Exception e) when(Recoverable(e)) {
                    initialized=false;
                    Interlocked.Increment(ref sessionNumber);
                    if(transport is not null) await transport.DisposeAsync(); transport=null;
                }
            }
            if(!stopping) Emit(new("failure",Method:"initialize",Message:"Runtime recovery exhausted; reload runtime"));
        } catch(OperationCanceledException) { }
        finally { sessionGate.Release(); }
    }
    private static bool Recoverable(Exception e) => e is IOException or InvalidOperationException or OperationCanceledException or FormatException or System.ComponentModel.Win32Exception;
    private void Fail(string method,Exception e) { if(!stopping) Emit(new("failure",Method:method,Message:e.Message)); }
    private void Emit(RuntimeEvent value) { if(!stopping) Event?.Invoke(value with { AccountEpoch=Volatile.Read(ref epoch) }); }
    public async ValueTask DisposeAsync() {
        if(stopping) return; stopping=true; lifetime.Cancel(); Interlocked.Increment(ref sessionNumber);
        foreach(var item in pending.Values) item.Completion.TrySetCanceled(); pending.Clear();
        if(transport is not null) await transport.DisposeAsync(); transport=null;
        if(reader is not null) { try { await reader; } catch(OperationCanceledException) { } }
        if(recovery is not null) { try { await recovery; } catch(OperationCanceledException) { } }
    }
}
