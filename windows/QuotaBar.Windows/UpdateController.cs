using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace QuotaBar.Windows;
internal sealed class UpdateController : IDisposable {
    readonly Coordinator owner;
    readonly BetaConsent beta;
    long channelGeneration;
    bool channelSaving;
    (string English,string Chinese,string Traditional)? channelError;
    public string? BetaError=>channelError is { } error?Text(error.English,error.Chinese,error.Traditional):null;
    public bool BetaEnabled=>beta.Persisted;
    public bool BetaEffective=>beta.Effective;
    public bool BetaBusy=>channelSaving || Installer.Operation.Progress.Phase is ApplicationUpdatePhase.HandingOff or ApplicationUpdatePhase.Installing;
    public ApplicationUpdateService Installer { get; }
    public void Install() { if(Available is { } release && !stopped && (!ProductVersion.Parse(release.Version).IsBeta || beta.Effective)) Installer.Operation.Start(release.Version); }
    public void CancelInstall()=>Installer.Operation.Cancel();
    public void OpenSettings()=>owner.ShowUpdateSettings();
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
    public string Status=>Installer.Operation.Progress.Phase!=ApplicationUpdatePhase.Idle?InstallStatus():statusMessage is { } message?Text(message.English,message.Chinese,message.Traditional):"";
    string InstallStatus() {
        var p=Installer.Operation.Progress;
        return p.Phase switch {
            ApplicationUpdatePhase.Resolving=>Text("Resolving official release…","正在获取官方版本…","正在取得官方版本…"),
            ApplicationUpdatePhase.Downloading=>Text("Downloading","正在下载","正在下載")+$" {p.Received/1048576d:F1} / {p.Total/1048576d:F1} MB",
            ApplicationUpdatePhase.Verifying=>Text("Verifying download…","正在校验安装包…","正在驗證安裝套件…"),
            ApplicationUpdatePhase.Preparing=>Text("Preparing update…","正在准备更新…","正在準備更新…"),
            ApplicationUpdatePhase.HandingOff or ApplicationUpdatePhase.Installing=>Text("Installing and restarting…","正在安装并重启…","正在安裝並重新啟動…"),
            ApplicationUpdatePhase.Succeeded=>Text("Update installed successfully.","更新安装成功。","更新安裝成功。"),
            ApplicationUpdatePhase.RolledBack=>Text("The new version could not start. Your previous version was restored.","新版未能正常启动，已恢复旧版本。","新版未能正常啟動，已恢復舊版本。"),
            ApplicationUpdatePhase.Cancelled=>Text("Download cancelled; current version unchanged.","已取消下载，当前版本未变更。","已取消下載，目前版本未變更。"),
            ApplicationUpdatePhase.Failed=>Text("Update failed. Retry or install manually from the release page. Use the standard per-user installation.","更新失败，可重试或从更新页面手动安装。请使用标准每用户安装目录。","更新失敗，可重試或從更新頁面手動安裝。請使用標準每使用者安裝目錄。"),
            _=>""
        };
    }
    void SetStatus(string english,string chinese,string traditional) { statusMessage=(english,chinese,traditional); }
    public bool Checking=>inFlight;
    public string Version {
        get {
            var numeric=typeof(UpdateController).Assembly.GetName().Version?.ToString(3)??"0.0.0";
            var proof=Path.Combine(AppContext.BaseDirectory,"PROVENANCE.json");
            if(!File.Exists(proof)) return string.Equals(Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar),UpdateLocations.Target,StringComparison.OrdinalIgnoreCase)?"—":numeric;
            try {
                var manifest=Path.Combine(AppContext.BaseDirectory,"package.json"); string? full=null;
                if(File.Exists(manifest)) { using var doc=JsonDocument.Parse(File.ReadAllText(manifest)); full=doc.RootElement.GetProperty("version").GetString(); }
                return ProductIdentity.Resolve(numeric,full,File.ReadAllText(proof)).Version;
            } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException or FormatException or KeyNotFoundException or InvalidOperationException) { return "—"; }
        }
    }
    public string DisplayVersion {
        get {
            var development=true;
            try {
                using var proof=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"PROVENANCE.json")));
                development=proof.RootElement.ValueKind!=JsonValueKind.Object || !proof.RootElement.TryGetProperty("kind",out var kind) || kind.ValueKind!=JsonValueKind.String || kind.GetString()!="release";
            } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) { }
            var betaLabel=IsBetaVersion(Version)?" ("+Text("Beta","内测版","內測版")+")":"";
            return Version+betaLabel+(development?" ("+Text("development candidate","开发候选","開發候選")+")":"");
        }
    }
    public event Action? Changed;
    sealed record UpdateState {
        public DateTimeOffset? LastSuccess { get; init; }
        public UpdateReminderPolicy Policy { get; init; }=new();
    }
    public UpdateController(Coordinator owner,string root,HttpClient? transport=null,Func<DateTimeOffset>? clock=null,Func<string,Action<ApplicationUpdateProgress>,CancellationToken,Task>? updateExecute=null) {
        now=clock??(()=>DateTimeOffset.UtcNow); next=now().AddSeconds(10);
        http=transport??new HttpClient(new HttpClientHandler { AllowAutoRedirect=false }) { Timeout=TimeSpan.FromSeconds(15) };
        this.owner=owner; beta=new(new UpdateChannelStore(Path.Combine(root,"update-channel.json"))); Installer=new(Version,updateExecute,()=>beta.Effective); Installer.Operation.Changed+=()=>Changed?.Invoke(); Installer.Operation.Ready+=owner.Quit; statePath=Path.Combine(root,"updates.json");
        try { state=JsonSerializer.Deserialize<UpdateState>(File.ReadAllText(statePath))??new(); } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) { }
        state=state with { Policy=state.Policy??new UpdateReminderPolicy() };
        timer.Tick+=(_,_)=> { Check(); Notify(); }; timer.Start();
        _=InitialCheck();
    }
    async Task InitialCheck() { try { await Task.Delay(TimeSpan.FromSeconds(10),lifetime.Token); Check(); } catch(OperationCanceledException) { } }
    string Text(string en,string zh,string tw)=>owner.Copy.Text(en,zh,tw);
    internal static bool IsBetaVersion(string value) { try { return ProductVersion.Parse(value).IsBeta; } catch(FormatException) { return false; } }
    public async void Check(bool manual=false) {
        var now=this.now();
        if(stopped || inFlight || (manual?now-lastManual<TimeSpan.FromSeconds(10):!owner.Preferences.AutomaticUpdates || now<next)) return;
        if(manual) lastManual=now;
        inFlight=true; var generation=channelGeneration; SetStatus("Checking…","正在检查…","正在檢查…"); Changed?.Invoke();
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
            var selection=UpdateFeed.Select(json,"windows-x64",Version,Environment.OSVersion.Version.ToString(3),beta.Effective); var release=selection.Release;
            if(stopped || generation!=channelGeneration) return;
            Available=release; cache=json;
            if(response.StatusCode==HttpStatusCode.OK) etag=response.Headers.ETag?.ToString();
            failures=0; next=this.now().AddHours(24);
            state=state with { LastSuccess=this.now() }; Persist();
            if(selection.BetaError) SetStatus("Could not check beta updates. Stable updates remain available.","内测更新检查失败，正式更新仍可用。","內測更新檢查失敗，正式更新仍可用。");
            else if(release is null) SetStatus("No newer release found","未发现更新版本","未發現更新版本"); else SetStatus("Update available","有新版本可用","有新版本可用"); Notify();
        } catch(Exception e) when(e is HttpRequestException or IOException or OperationCanceledException or FormatException or DecoderFallbackException) {
            if(stopped || generation!=channelGeneration) return;
            failures=Math.Min(failures+1,6); next=this.now().AddSeconds(Math.Min(21600,300*Math.Pow(2,failures-1)));
            SetStatus("Could not check. Try again later.","检查失败，请稍后重试。","檢查失敗，請稍後重試。");
        } finally { inFlight=false; if(!stopped) { Changed?.Invoke(); if(generation!=channelGeneration && owner.Preferences.AutomaticUpdates) { next=DateTimeOffset.MinValue;Check(); } } }
    }
    void InvalidateChannel() {
        channelGeneration++; pendingReminder=null; retryReminder=DateTimeOffset.MinValue; next=DateTimeOffset.MinValue;
        if(Available is { } release && ProductVersion.Parse(release.Version).IsBeta) { owner.Notifications.CancelMessage("update-"+release.Version); Available=null; }
    }
    public async Task SetBetaAsync(bool enabled,Func<int,bool> confirm) {
        if(stopped || BetaBusy) return;
        if(enabled) {
            if(beta.Persisted) return;
            try {
                if(!beta.Enable(confirm)) { Changed?.Invoke();return; }
                channelError=null; InvalidateChannel(); SetStatus("Beta experience enabled","内测体验已开启","內測體驗已開啟");
            } catch(Exception e) when(e is IOException or UnauthorizedAccessException) { channelError=("Could not save beta setting","无法保存内测设置","無法儲存內測設定"); SetStatus(channelError.Value.English,channelError.Value.Chinese,channelError.Value.Traditional); }
        } else {
            if(!beta.Persisted) return;
            var target=Installer.Operation.TargetVersion;
            var cancelBeta=ApplicationUpdateOperation.CanCancel(Installer.Operation.Progress.Phase) && target is not null && ProductVersion.Parse(target).IsBeta;
            beta.Suspend(); InvalidateChannel(); channelSaving=true; Changed?.Invoke();
            if(cancelBeta) await Installer.Operation.WaitForCleanup();
            try { beta.FinishDisable(); channelError=null; SetStatus("Beta experience disabled","内测体验已关闭","內測體驗已關閉"); }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException) { channelError=("Could not save. Beta remains enabled after restart.","未能保存，重启后内测仍会开启。","未能儲存，重新啟動後內測仍會開啟。"); SetStatus(channelError.Value.English,channelError.Value.Chinese,channelError.Value.Traditional); }
            finally { channelSaving=false; }
        }
        Changed?.Invoke(); if(owner.Preferences.AutomaticUpdates) Check();
    }
    void Persist() {
        try { var temp=statePath+".tmp"; File.WriteAllText(temp,JsonSerializer.Serialize(state)); File.Move(temp,statePath,true); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException) { SetStatus("Could not save update preferences","无法保存更新偏好","無法儲存更新偏好"); }
    }
    public void Open() { if(Available is { } release) Platform.OpenUrl(release.ReleaseNotesURL.AbsoluteUri); }
    public void Snooze() { if(Available is { } release) owner.Notifications.CancelMessage("update-"+release.Version); pendingReminder=null; retryReminder=DateTimeOffset.MinValue; state=state with { Policy=state.Policy with { SkippedVersion=state.Policy.SkippedVersion==Available?.Version?null:state.Policy.SkippedVersion,SnoozeUntil=DateTimeOffset.UtcNow.AddDays(1) } }; SetStatus("Reminder postponed for 24 hours","已延后提醒 24 小时","已延後提醒 24 小時"); Persist(); Changed?.Invoke(); }
    public void Skip() { if(Available is { } release) owner.Notifications.CancelMessage("update-"+release.Version); pendingReminder=null; state=state with { Policy=state.Policy with { SkippedVersion=Available?.Version,SnoozeUntil=null } }; SetStatus("Version skipped","已跳过此版本","已跳過此版本"); Persist(); Changed?.Invoke(); }
    bool Reminders=>owner.Notifications.PolicyActive?owner.Notifications.PolicyPreferences.Rules.TryGetValue(NotificationCategory.UpdateAvailable,out var channels)&&channels.Count>0:owner.Preferences.UpdateReminders;
    public bool ReminderValid(string version)=>!stopped && Reminders && Available?.Version==version && state.Policy.SkippedVersion!=version && !(state.Policy.SnoozeUntil>DateTimeOffset.UtcNow);
    string ReminderGeneration=>state.Policy.SnoozeUntil is { } until?"snooze:"+until.ToUnixTimeMilliseconds():"initial";
    public ExperienceNotification? CurrentReminder=>Available is { } release?new("update-"+release.Version,ExperienceNotificationKind.Update,null,"", "",DateTimeOffset.UtcNow,ReminderGeneration:ReminderGeneration,Category:owner.Notifications.PolicyActive?NotificationCategory.UpdateAvailable:null):null;
    public void Notify() {
        if(stopped || !Reminders || Available is not { } release || !state.Policy.ShouldNotify(release.Version,DateTimeOffset.UtcNow)) return;
        if(DateTimeOffset.UtcNow<retryReminder) return;
        pendingReminder=release.Version; retryReminder=DateTimeOffset.UtcNow.AddMinutes(30);
        owner.ShowUpdateReminder(release.Version,release.NotificationSummary,ReminderGeneration);
    }
    public void ReminderShown(string? expectedVersion=null) {
        if(expectedVersion is not null && pendingReminder!=expectedVersion) return;
        if(stopped) return;
        if(pendingReminder is { } version && Reminders && Available?.Version==version && state.Policy.ShouldNotify(version,DateTimeOffset.UtcNow)) {
            state=state with { Policy=state.Policy with { NotifiedVersion=version,SnoozeUntil=null } }; Persist();
        }
        pendingReminder=null;
    }
    public void PreferencesChanged() { Changed?.Invoke(); Notify(); }
    public void Dispose() { if(stopped) return; Installer.Operation.Cancel(); stopped=true; timer.Stop(); lifetime.Cancel(); http.Dispose(); lifetime.Dispose(); }
}
