using Microsoft.Win32;
using System.Drawing;
using Forms=System.Windows.Forms;

namespace QuotaBar.Windows;
internal sealed class Coordinator : IDisposable {
    readonly Application app;
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
    bool? iconDark,iconContrast;
    Rect trayAnchor=Rect.Empty;
    public RefreshState State { get; private set; }=new();
    public Preferences Preferences { get; private set; }
    public QuotaSnapshot? Snapshot { get; private set; }
    public TokenUsage? Tokens { get; private set; }
    public AccountIdentity? Identity { get; private set; }
    public Copy Copy=>new(Preferences.Language);
    public Coordinator(Application app) {
        this.app=app; Directory.CreateDirectory(root); store=new(Path.Combine(root,"preferences.json")); Preferences=store.Load();
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
        detail.CloseRequested+=()=> { interaction.Reset(); trayDetail=false; trayLocked=false; detail.Hide(); };
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
        Item(copy.Text("Settings…","设置…","設定…"),ShowSettings); Item(copy.Text("Quit","退出","結束"),Quit);
        menu.Closed+=(_,_)=>app.Dispatcher.BeginInvoke(()=> { if(!stopping && ReferenceEquals(tray.ContextMenuStrip,menu)) UpdateTray(); });
        var old=tray.ContextMenuStrip; tray.ContextMenuStrip=menu; old?.Dispose(); menuKey=key;
        }
        var text=Preferences.ShowsQuotaInformation?copy.Indicator(Snapshot,State.Phase)+"\n"+copy.PhaseLabel(State.Phase):"QuotaBar";
        tray.Text=text.Length<=127?text:text[..126]+"…";
        var dark=Platform.IsDark(Preferences); var contrast=SystemParameters.HighContrast;
        if(trayIcon is null || iconDark!=dark || iconContrast!=contrast) {
            var icon=MakeTrayIcon(dark); var previous=trayIcon; trayIcon=icon; tray.Icon=icon; previous?.Dispose(); iconDark=dark; iconContrast=contrast;
        }
    }
    internal static Icon MakeTrayIcon(bool dark) {
        using var bitmap=new Bitmap(32,32); using var g=Graphics.FromImage(bitmap);
        g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        var color=SystemParameters.HighContrast?System.Drawing.SystemColors.WindowText:dark?System.Drawing.Color.FromArgb(202,215,245):System.Drawing.Color.FromArgb(36,55,95);
        var accent=SystemParameters.HighContrast?System.Drawing.SystemColors.WindowText:System.Drawing.Color.FromArgb(250,112,82);
        using var pen=new System.Drawing.Pen(color,4) { StartCap=System.Drawing.Drawing2D.LineCap.Round,EndCap=System.Drawing.Drawing2D.LineCap.Round };
        g.DrawArc(pen,4,4,24,24,130,300); using var brush=new SolidBrush(accent); g.FillEllipse(brush,9,10,3,3); g.FillEllipse(brush,17,9,3,3);
        using var path=new System.Drawing.Drawing2D.GraphicsPath(); path.AddBezier(6,21,13,27,18,15,26,18); path.AddBezier(26,18,24,29,9,29,6,21); path.CloseFigure(); g.FillPath(brush,path);
        var h=bitmap.GetHicon(); try { return (Icon)Icon.FromHandle(h).Clone(); } finally { DestroyIcon(h); }
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);
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
            State=new(); Snapshot=null; Tokens=null; Identity=null;
            var executable=Path.Combine(AppContext.BaseDirectory,"runtime","codex.exe");
            if(!File.Exists(executable)) { State.Error("initialize","Runtime unavailable"); ShowSettings(); Render(); return; }
            var current=new RuntimeSession(()=>new ProcessTransport(executable,Path.Combine(root,"CodexHome"),job.Add)); runtime=current;
            current.Event+=value=>app.Dispatcher.BeginInvoke(()=> { if(!stopping && ReferenceEquals(runtime,current)) Receive(value); });
            await current.StartAsync(); await current.RefreshAsync();
        } catch(Exception e) when(e is IOException or InvalidOperationException or System.ComponentModel.Win32Exception or OperationCanceledException) { State.Error("initialize","Runtime unavailable"); Render(); }
        finally { reloading=false; }
    }
    void Receive(RuntimeEvent e) {
        if(runtime is not null && !runtime.IsCurrentEvent(e)) return;
        switch(e.Kind) {
            case "quota": Snapshot=e.Quota; State.Received(DateTimeOffset.UtcNow); break;
            case "tokens": Tokens=e.Tokens; break;
            case "tokensUnavailable": Tokens=null; break;
            case "account": Identity=e.Account; break;
            case "cleared": Snapshot=null; Tokens=null; Identity=null; break;
            case "loggedOut": State.LoginCompleted(false); break;
            case "loginCompleted": State.LoginCompleted(e.Success==true); break;
            case "loginUrl": if(e.LoginUrl is not null) Platform.OpenUrl(e.LoginUrl.AbsoluteUri); break;
            case "failure": State.Error(e.Method??"initialize",e.Message??"Request failed"); if(e.Method=="account/login/start") State.LoginCompleted(false); break;
        }
        Render(); if(State.Phase==Phase.NeedsLogin) ShowSettings();
    }
    void WriteDiagnostic() {
        try { File.WriteAllText(Path.Combine(root,"standalone-state.txt"),$"pid={Environment.ProcessId} mode=standalone phase={State.Phase} has_quota={Snapshot is not null} host_ui=false floating_visible={floating.IsVisible} floating_enabled={Preferences.FloatingEnabled} detail_visible={detail.IsVisible}\n"); }
        catch(IOException) { }
    }
    void PowerChanged(object sender,PowerModeChangedEventArgs e) { app.Dispatcher.BeginInvoke(()=> { sleeping=e.Mode==PowerModes.Suspend; if(e.Mode==PowerModes.Resume) { sleeping=false; Refresh(); } }); }
    void ThemeChanged(object sender,UserPreferenceChangedEventArgs e) { app.Dispatcher.BeginInvoke(()=> { Render(); settings?.Build(); }); }
    void DisplayChanged(object? sender,EventArgs e) { app.Dispatcher.BeginInvoke(Render); }
    void NetworkChanged(object? sender,System.Net.NetworkInformation.NetworkAvailabilityEventArgs e) { if(e.IsAvailable) app.Dispatcher.BeginInvoke(Refresh); }
    public async void Quit() {
        if(stopping) return; stopping=true; tick.Stop(); pointer.Stop(); tray.Visible=false; floating.Hide(); detail.Hide(); settings?.Close();
        if(runtime is not null) await runtime.DisposeAsync(); app.Shutdown();
    }
    public void Dispose() {
        stopping=true; tick.Stop(); pointer.Stop(); outside?.Dispose(); tray.Dispose(); trayIcon?.Dispose(); job.Dispose();
        SystemEvents.PowerModeChanged-=PowerChanged; SystemEvents.UserPreferenceChanged-=ThemeChanged; SystemEvents.DisplaySettingsChanged-=DisplayChanged;
        System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged-=NetworkChanged;
    }
}
