using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace QuotaBar.Windows;
internal sealed class UpdateController : IDisposable {
    readonly Coordinator owner;
    readonly Func<DateTimeOffset> now;
    readonly string statePath;
    readonly DispatcherTimer timer=new() { Interval=TimeSpan.FromMinutes(1) };
    readonly HttpClient http;
    readonly CancellationTokenSource lifetime=new();
    bool inFlight,stopped;
    DateTimeOffset next,lastManual=DateTimeOffset.MinValue;
    string? pendingReminder;
    DateTimeOffset retryReminder=DateTimeOffset.MinValue;
    int failures;
    string? cache,etag;
    UpdateState state=new();
    public UpdateRelease? Available { get; private set; }
    (string English,string Chinese,string Traditional)? statusMessage;
    public string Status=>statusMessage is { } message?Text(message.English,message.Chinese,message.Traditional):"";
    void SetStatus(string english,string chinese,string traditional) { statusMessage=(english,chinese,traditional); }
    public bool Checking=>inFlight;
    public string Version=>typeof(UpdateController).Assembly.GetName().Version?.ToString(3)??"0.0.0";
    public string DisplayVersion {
        get {
            var development=true;
            try {
                using var proof=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"PROVENANCE.json")));
                development=proof.RootElement.ValueKind!=JsonValueKind.Object || !proof.RootElement.TryGetProperty("kind",out var kind) || kind.ValueKind!=JsonValueKind.String || kind.GetString()!="release";
            } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) { }
            return Version+(development?" ("+Text("development candidate","开发候选","開發候選")+")":"");
        }
    }
    public event Action? Changed;
    sealed record UpdateState {
        public DateTimeOffset? LastSuccess { get; init; }
        public UpdateReminderPolicy Policy { get; init; }=new();
    }
    public UpdateController(Coordinator owner,string root,HttpClient? transport=null,Func<DateTimeOffset>? clock=null) {
        now=clock??(()=>DateTimeOffset.UtcNow); next=now().AddSeconds(30);
        http=transport??new HttpClient(new HttpClientHandler { AllowAutoRedirect=false }) { Timeout=TimeSpan.FromSeconds(15) };
        this.owner=owner; statePath=Path.Combine(root,"updates.json");
        try { state=JsonSerializer.Deserialize<UpdateState>(File.ReadAllText(statePath))??new(); } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) { }
        state=state with { Policy=state.Policy??new UpdateReminderPolicy() };
        timer.Tick+=(_,_)=> { Check(); Notify(); }; timer.Start();
        _=InitialCheck();
    }
    async Task InitialCheck() { try { await Task.Delay(TimeSpan.FromSeconds(30),lifetime.Token); Check(); } catch(OperationCanceledException) { } }
    string Text(string en,string zh,string tw)=>owner.Copy.Text(en,zh,tw);
    public async void Check(bool manual=false) {
        var now=this.now();
        if(stopped || inFlight || (manual?now-lastManual<TimeSpan.FromSeconds(10):!owner.Preferences.AutomaticUpdates || now<next)) return;
        if(manual) lastManual=now;
        inFlight=true; SetStatus("Checking…","正在检查…","正在檢查…"); Changed?.Invoke();
        try {
            using var timeout=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token); timeout.CancelAfter(TimeSpan.FromSeconds(15));
            using var request=new HttpRequestMessage(HttpMethod.Get,UpdateFeed.Endpoint);
            if(etag is not null) request.Headers.TryAddWithoutValidation("If-None-Match",etag);
            using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout.Token);
            string json;
            if(response.StatusCode==HttpStatusCode.NotModified && cache is not null) json=cache;
            else {
                if(response.StatusCode!=HttpStatusCode.OK || response.Content.Headers.ContentLength>262144) throw new HttpRequestException("Invalid feed response");
                await using var input=await response.Content.ReadAsStreamAsync(timeout.Token); using var data=new MemoryStream();
                var buffer=new byte[4096]; int count;
                while((count=await input.ReadAsync(buffer,timeout.Token))>0) { if(data.Length+count>262144) throw new FormatException("Feed too large"); data.Write(buffer,0,count); }
                json=new UTF8Encoding(false,true).GetString(data.ToArray());
            }
            var release=UpdateFeed.Available(json,"windows-x64",Version,Environment.OSVersion.Version.ToString(3));
            if(stopped) return;
            Available=release; cache=json;
            if(response.StatusCode==HttpStatusCode.OK) etag=response.Headers.ETag?.ToString();
            failures=0; next=this.now().AddHours(24);
            state=state with { LastSuccess=this.now() }; Persist();
            if(release is null) SetStatus("No newer release found","未发现更新版本","未發現更新版本"); else SetStatus("Update available","有新版本可用","有新版本可用"); Notify();
        } catch(Exception e) when(e is HttpRequestException or IOException or OperationCanceledException or FormatException or DecoderFallbackException) {
            if(stopped) return;
            failures=Math.Min(failures+1,6); next=this.now().AddSeconds(Math.Min(21600,300*Math.Pow(2,failures-1)));
            SetStatus("Could not check. Try again later.","检查失败，请稍后重试。","檢查失敗，請稍後重試。");
        } finally { inFlight=false; if(!stopped) Changed?.Invoke(); }
    }
    void Persist() {
        try { var temp=statePath+".tmp"; File.WriteAllText(temp,JsonSerializer.Serialize(state)); File.Move(temp,statePath,true); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException) { SetStatus("Could not save update preferences","无法保存更新偏好","無法儲存更新偏好"); }
    }
    public void Open() { if(Available is { } release) Platform.OpenUrl(release.ReleaseNotesURL.AbsoluteUri); }
    public void Snooze() { if(Available is { } release) owner.Notifications.CancelMessage("update-"+release.Version); pendingReminder=null; retryReminder=DateTimeOffset.MinValue; state=state with { Policy=state.Policy with { SkippedVersion=state.Policy.SkippedVersion==Available?.Version?null:state.Policy.SkippedVersion,SnoozeUntil=DateTimeOffset.UtcNow.AddDays(1) } }; SetStatus("Reminder postponed for 24 hours","已延后提醒 24 小时","已延後提醒 24 小時"); Persist(); Changed?.Invoke(); }
    public void Skip() { if(Available is { } release) owner.Notifications.CancelMessage("update-"+release.Version); pendingReminder=null; state=state with { Policy=state.Policy with { SkippedVersion=Available?.Version,SnoozeUntil=null } }; SetStatus("Version skipped","已跳过此版本","已跳過此版本"); Persist(); Changed?.Invoke(); }
    public bool ReminderValid(string version)=>!stopped && owner.Preferences.UpdateReminders && Available?.Version==version && state.Policy.SkippedVersion!=version && !(state.Policy.SnoozeUntil>DateTimeOffset.UtcNow);
    public void Notify() {
        if(stopped || !owner.Preferences.UpdateReminders || Available is not { } release || !state.Policy.ShouldNotify(release.Version,DateTimeOffset.UtcNow)) return;
        if(DateTimeOffset.UtcNow<retryReminder) return;
        pendingReminder=release.Version; retryReminder=DateTimeOffset.UtcNow.AddMinutes(30);
        owner.ShowUpdateReminder(release.Version,release.NotificationSummary);
    }
    public void ReminderShown(string? expectedVersion=null) {
        if(expectedVersion is not null && pendingReminder!=expectedVersion) return;
        if(stopped) return;
        if(pendingReminder is { } version && owner.Preferences.UpdateReminders && Available?.Version==version && state.Policy.ShouldNotify(version,DateTimeOffset.UtcNow)) {
            state=state with { Policy=state.Policy with { NotifiedVersion=version,SnoozeUntil=null } }; Persist();
        }
        pendingReminder=null;
    }
    public void PreferencesChanged() { Changed?.Invoke(); Notify(); }
    public void Dispose() { if(stopped) return; stopped=true; timer.Stop(); lifetime.Cancel(); http.Dispose(); lifetime.Dispose(); }
}
