using Microsoft.Win32;
using System.Drawing;
using Forms=System.Windows.Forms;

namespace QuotaBar.Windows;
internal sealed class Coordinator : IDisposable {
    readonly Application app;
    public UpdateController Updates { get; }
    internal AppNotificationRouter Notifications { get; }
    internal QuotaExperienceController Experience { get; }
    readonly string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"QuotaBar");
    readonly PreferencesStore store;
    readonly OwnedJob job=new();
    readonly Forms.NotifyIcon tray=new();
    readonly FloatingWindow floating=new();
    readonly DetailWindow detail=new();
    readonly DetailInteractionState interaction=new();
    readonly TrayClickGate trayClickGate=new();
    readonly DispatcherTimer tick=new() { Interval=TimeSpan.FromSeconds(5) };
    readonly DispatcherTimer pointer=new() { Interval=TimeSpan.FromMilliseconds(150) };
    RuntimeSession? runtime;
    OutsideMouse? outside;
    SettingsWindow? settings;
    bool trayDetail,trayLocked,detailFromFloating,sleeping,stopping,reloading;
    Icon? trayIcon;
    string? menuKey;
    Rect trayAnchor=Rect.Empty;
    public RefreshState State { get; private set; }=new();
    public Preferences Preferences { get; private set; }
    public QuotaSnapshot? Snapshot { get; private set; }
    public TokenUsage? Tokens { get; private set; }
    public AccountIdentity? Identity { get; private set; }
    public Copy Copy=>new(Preferences.Language);
    public Coordinator(Application app,string? dataRoot=null,System.Net.Http.HttpClient? updatesTransport=null) {
        this.app=app; if(dataRoot is not null) root=dataRoot; Directory.CreateDirectory(root); store=new(Path.Combine(root,"preferences.json")); Preferences=store.Load();
        Updates=new(this,root,updatesTransport); Updates.Changed+=()=> { if(!stopping) { settings?.UpdateUpdateStatus(); menuKey=null; UpdateTray(); } };
        Notifications=new(tray,
            m=>m.Kind==ExperienceNotificationKind.Update ? Preferences.UpdateReminders && Updates.Available is { } r && m.Id=="update-"+r.Version : Experience?.Valid(m)==true,
            m=> { if(m.Kind==ExperienceNotificationKind.Update) Updates.Open(); else OpenExperienceDetail(); },
            m=> { if(m.Kind==ExperienceNotificationKind.Update) Updates.ReminderShown(m.Id[7..]); });
        Experience=new(this,root); Notifications.Failed=Experience.NotificationFailed;
        floating.Primary+=()=> {
            if(Snapshot is null) { ShowSettings(); return; }
            detailFromFloating=true; trayDetail=false; trayLocked=false; interaction.TogglePinned(true); Render(); Refresh();
        };
        floating.Entered+=()=> {
            if(Snapshot is null || trayDetail) return;
            detailFromFloating=true; interaction.UpdatePointer(true); Render(); pointer.Start();
        };
        floating.CloseRequested+=()=>SetFloating(false);
        floating.PositionChanged+=p=>Save(Preferences with { FloatingX=p.X,FloatingY=p.Y },false);
        floating.Secondary+=()=> {
            var menu=new ContextMenu();
            foreach(var item in MenuItems()) menu.Items.Add(item);
            floating.ContextMenu=menu; menu.IsOpen=true;
        };
        detail.LockRequested+=()=> {
            if(detailFromFloating) { interaction.ToggleLocked(true); pointer.Start(); } else trayLocked=!trayLocked;
            Render();
        };
        detail.SettingsRequested+=ShowSettings;
        detail.HeightChanged+=height=> {
            try { var updated=Preferences with { DetailHeight=height }; store.Save(updated); Preferences=updated; }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException) { }
        };
        tick.Tick+=(_,_)=> { if(!sleeping && State.ShouldRefresh(DateTimeOffset.UtcNow)) Refresh(); Render(); };
        pointer.Tick+=(_,_)=> {
            if(!detailFromFloating) { pointer.Stop(); return; }
            var p=Platform.Cursor;
            var visible=interaction.ShouldShow;
            interaction.UpdatePointer(Platform.Bounds(floating).Contains(p) || Platform.Bounds(detail).Contains(p));
            if(visible!=interaction.ShouldShow) RenderDetail(); if(!interaction.ShouldShow && !floating.IsMouseOver) pointer.Stop();
        };
        tray.MouseClick+=(_,e)=> {
            if(e.Button!=Forms.MouseButtons.Left) return;
            if(!trayClickGate.SuppressTrayClick()) ToggleTrayDetail();
        };
    }
    public void Start() {
        outside=new OutsideMouse(p=> {
            trayClickGate.BeginMouseDown();
            if(!detail.IsVisible || Platform.Bounds(detail).Contains(p) || Platform.Bounds(floating).Contains(p)) return;
            if(detailFromFloating) interaction.DismissOutside();
            else if(!trayLocked) { trayClickGate.OutsideDismissed(); trayDetail=false; }
            RenderDetail();
        });
        SystemEvents.PowerModeChanged+=PowerChanged;
        SystemEvents.UserPreferenceChanged+=ThemeChanged;
        SystemEvents.DisplaySettingsChanged+=DisplayChanged;
        System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged+=NetworkChanged;
        tray.Visible=true; tick.Start(); Render(); Reload();
    }
    public void Save(Preferences prefs,bool rebuildSettings=true) {
        try { store.Save(prefs); Preferences=prefs.Validated(); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException) { MessageBox.Show(Copy.Text("Could not save preferences","无法保存设置","無法儲存設定")); return; }
        Experience.Configure();
        Updates.PreferencesChanged();
        Render(); if(rebuildSettings) settings?.Build();
    }
    void SetFloating(bool enabled) {
        Save(Preferences with { FloatingEnabled=enabled },false);
        if(!Preferences.FloatingEnabled) {
            floating.HideFloat(); interaction.Reset(); pointer.Stop();
            if(detailFromFloating) { trayDetail=false; trayLocked=false; detail.Hide(); }
        }
        Render();
    }
    IEnumerable<MenuItem> MenuItems() {
        var copy=Copy;
        MenuItem Item(string name,Action action) { var i=new MenuItem { Header=name }; i.Click+=(_,_)=>action(); return i; }
        yield return Item(copy.Text("Quota details","额度详情","額度詳情"),ToggleTrayDetail);
        yield return Item(copy.Text("Refresh","刷新","重新整理"),Refresh);
        var floatItem=Item(copy.Text("Show floating button","显示悬浮按钮","顯示懸浮按鈕"),()=>SetFloating(!Preferences.FloatingEnabled)); floatItem.IsCheckable=true; floatItem.IsChecked=Preferences.FloatingEnabled; yield return floatItem;
        yield return Item(copy.Text("Check for updates…","检查更新…","檢查更新…"),()=> { ShowSettings(); Updates.Check(true); });
        yield return Item(copy.Text("Settings…","设置…","設定…"),ShowSettings);
        yield return Item(copy.Text("Quit","退出","結束"),Quit);
    }
    void UpdateTray() {
        var copy=Copy;
        var key=copy.Language+":"+Preferences.FloatingEnabled;
        if(menuKey!=key && tray.ContextMenuStrip?.Visible!=true) {
        var menu=new Forms.ContextMenuStrip();
        void Item(string text,Action action) { menu.Items.Add(text,null,(_,_)=>action()); }
        Item(copy.Text("Quota details","额度详情","額度詳情"),ToggleTrayDetail); Item(copy.Text("Refresh","刷新","重新整理"),Refresh);
        var floatItem=new Forms.ToolStripMenuItem(copy.Text("Show floating button","显示悬浮按钮","顯示懸浮按鈕")) { Checked=Preferences.FloatingEnabled };
        floatItem.Click+=(_,_)=> { SetFloating(!Preferences.FloatingEnabled); floatItem.Checked=Preferences.FloatingEnabled; }; menu.Items.Add(floatItem);
        Item(copy.Text("Check for updates…","检查更新…","檢查更新…"),()=> { ShowSettings(); Updates.Check(true); });
        Item(copy.Text("Settings…","设置…","設定…"),ShowSettings); Item(copy.Text("Quit","退出","結束"),Quit);
        menu.Closed+=(_,_)=>app.Dispatcher.BeginInvoke(()=> { if(!stopping && ReferenceEquals(tray.ContextMenuStrip,menu)) UpdateTray(); });
        var old=tray.ContextMenuStrip; tray.ContextMenuStrip=menu; old?.Dispose(); menuKey=key;
        }
        var text=Preferences.ShowsQuotaInformation?copy.Indicator(Snapshot,State.Phase)+"\n"+copy.PhaseLabel(State.Phase):"QuotaBar";
        tray.Text=text.Length<=127?text:text[..126]+"…";
        if(trayIcon is null) { trayIcon=MakeTrayIcon(); tray.Icon=trayIcon; }
    }
    internal static Icon MakeTrayIcon() {
        var resource=Application.GetResourceStream(new Uri("pack://application:,,,/QuotaBar;component/Assets/QuotaBar.ico"))??throw new IOException("Application icon resource missing");
        using var stream=resource.Stream; using var icon=new Icon(stream,new System.Drawing.Size(32,32)); return (Icon)icon.Clone();
    }
    void Render() {
        if(stopping) return;
        UpdateTray(); floating.Render(Snapshot,State,Preferences,Copy,Platform.IsDark(Preferences)); RenderDetail(); settings?.UpdateStatus();
        WriteDiagnostic();
    }
    void RenderDetail() {
        if(Snapshot is null || !(trayDetail || interaction.ShouldShow)) { detail.Hide(); return; }
        Rect anchor;
        if(detailFromFloating) anchor=Platform.Bounds(floating);
        else anchor=trayAnchor;
        if(anchor.IsEmpty) { detail.Hide(); return; }
        detail.Render(Snapshot,Tokens,Identity,State,Preferences,Copy,Platform.IsDark(Preferences),detailFromFloating?interaction.IsLocked:trayLocked,anchor);
    }
    public void ToggleTrayDetail() {
        if(Snapshot is null) { ShowSettings(); return; }
        interaction.Reset(); pointer.Stop(); detailFromFloating=false; trayLocked=false;
        var p=Platform.Cursor; var screen=Platform.WorkArea(p); trayAnchor=new Rect(p.X,screen.Y+screen.Height,1,1);
        trayDetail=!trayDetail; Render(); Refresh();
    }
    internal void PreviewCelebration()=>floating.Celebrate();
    internal void CancelCelebration()=>floating.CancelCelebration();
    void OpenExperienceDetail() {
        if(Snapshot is null) { ShowSettings(); return; }
        var p=Platform.Cursor; var screen=Platform.WorkArea(p); trayAnchor=new Rect(p.X,screen.Y+screen.Height,1,1);
        detailFromFloating=false; trayDetail=true; Render(); Refresh();
    }
    internal bool ShowUpdateReminder(string version,string? summary=null) {
        Notifications.Enqueue(new("update-"+version,ExperienceNotificationKind.Update,null,"QuotaBar "+Copy.Text("update available","有新版本","有新版本")+" "+version,summary??Copy.Text("Click to view release notes","点击查看更新说明","點擊查看更新說明"),DateTimeOffset.UtcNow)); return true;
    }
    public void ShowSettings() {
        if(settings is null) { settings=new(this); settings.Closed+=(_,_)=>settings=null; }
        settings.Show(); settings.Activate();
    }
    public async void Refresh() {
        if(stopping || sleeping || runtime is null || State.Phase is Phase.NeedsLogin or Phase.SigningIn) return;
        try { await runtime.RefreshAsync(); }
        catch(Exception e) when(e is IOException or OperationCanceledException) { State.Error("account/rateLimits/read","Runtime unavailable"); Render(); }
    }
    public async void Login() { if(runtime is null) return; State.BeginLogin(); Render(); await runtime.LoginAsync(); }
    public async void CancelLogin() { if(runtime is not null) await runtime.CancelLoginAsync(); }
    public async void Logout() { if(runtime is not null) await runtime.LogoutAsync(); }
    public async void Reload() {
        if(stopping || reloading) return; reloading=true;
        try {
            if(runtime is not null) await runtime.DisposeAsync();
            Experience.ResetBaseline(); State=new(); Snapshot=null; Tokens=null; Identity=null;
            var executable=Path.Combine(AppContext.BaseDirectory,"runtime","codex.exe");
            if(!File.Exists(executable)) { State.Error("initialize","Runtime unavailable"); ShowSettings(); Render(); return; }
            var current=new RuntimeSession(()=>new ProcessTransport(executable,Path.Combine(root,"CodexHome"),job.Add,ShutdownDiagnostic)); runtime=current;
            current.Event+=value=>app.Dispatcher.BeginInvoke(()=> { if(!stopping && ReferenceEquals(runtime,current)) Receive(value); });
            await current.StartAsync(); await current.RefreshAsync();
        } catch(Exception e) when(e is IOException or InvalidOperationException or System.ComponentModel.Win32Exception or OperationCanceledException) { State.Error("initialize","Runtime unavailable"); Render(); }
        finally { reloading=false; }
    }
    void Receive(RuntimeEvent e) {
        if(runtime is not null && !runtime.IsCurrentEvent(e)) return;
        switch(e.Kind) {
            case "quotaRead": if(e.Observation is { } raw) Experience.Receive(raw); break;
            case "quota": Snapshot=e.Quota; State.Received(DateTimeOffset.UtcNow); break;
            case "tokens": Tokens=e.Tokens; break;
            case "tokensUnavailable": Tokens=null; break;
            case "account": Identity=e.Account; break;
            case "cleared": Experience.ClearAccount(); Snapshot=null; Tokens=null; Identity=null; break;
            case "loggedOut": State.LoginCompleted(false); break;
            case "loginCompleted": State.LoginCompleted(e.Success==true); break;
            case "loginUrl": if(e.LoginUrl is not null) Platform.OpenUrl(e.LoginUrl.AbsoluteUri); break;
            case "failure": State.Error(e.Method??"initialize",e.Message??"Request failed"); if(State.Phase!=Phase.Ready) Experience.ResetBaseline(); if(e.Method=="account/login/start") State.LoginCompleted(false); break;
        }
        Render(); if(State.Phase==Phase.NeedsLogin) ShowSettings();
    }
    void WriteDiagnostic() {
        try { File.WriteAllText(Path.Combine(root,"standalone-state.txt"),$"pid={Environment.ProcessId} mode=standalone phase={State.Phase} has_quota={Snapshot is not null} host_ui=false floating_visible={floating.IsVisible} floating_enabled={Preferences.FloatingEnabled} detail_visible={detail.IsVisible}\n"); }
        catch(IOException) { }
    }
    void PowerChanged(object sender,PowerModeChangedEventArgs e) { app.Dispatcher.BeginInvoke(()=> { sleeping=e.Mode==PowerModes.Suspend; if(sleeping) Experience.ResetBaseline(); if(e.Mode==PowerModes.Resume) { sleeping=false; Refresh(); Updates.Check(); } }); }
    void ThemeChanged(object sender,UserPreferenceChangedEventArgs e) { app.Dispatcher.BeginInvoke(()=> { Render(); settings?.Build(); }); }
    void DisplayChanged(object? sender,EventArgs e) { app.Dispatcher.BeginInvoke(Render); }
    void NetworkChanged(object? sender,System.Net.NetworkInformation.NetworkAvailabilityEventArgs e) { if(e.IsAvailable) app.Dispatcher.BeginInvoke(()=> { Refresh(); Updates.Check(); }); }
    public async void Quit() {
        if(stopping) return; stopping=true; Experience.Stop(); Notifications.Dispose(); Updates.Dispose(); ShutdownDiagnostic("requested"); tick.Stop(); pointer.Stop(); tray.Visible=false; floating.Hide(); detail.Hide(); settings?.Close();
        ShutdownDiagnostic("runtime-disposing"); if(runtime is not null) await runtime.DisposeAsync(); ShutdownDiagnostic("runtime-disposed"); app.Shutdown();
    }
    void ShutdownDiagnostic(string stage) { try { File.WriteAllText(Path.Combine(root,"shutdown-state.txt"),$"pid={Environment.ProcessId} stage={stage}\n"); } catch(IOException) { } }
    public void Dispose() {
        stopping=true; Experience.Stop(); Notifications.Dispose(); Updates.Dispose(); tick.Stop(); pointer.Stop(); outside?.Dispose(); tray.Dispose(); trayIcon?.Dispose(); job.Dispose();
        SystemEvents.PowerModeChanged-=PowerChanged; SystemEvents.UserPreferenceChanged-=ThemeChanged; SystemEvents.DisplaySettingsChanged-=DisplayChanged;
        System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged-=NetworkChanged;
    }
}
