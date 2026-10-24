namespace QuotaBar.Windows;
public static class Program {
    [STAThread]
    public static void Main(string[] args) {
        System.Windows.Forms.Application.SetHighDpiMode(System.Windows.Forms.HighDpiMode.PerMonitorV2);
        if(args.Contains("--quit")) { try { using var signal=EventWaitHandle.OpenExisting("Local\\QuotaBar.Shutdown"); signal.Set(); } catch(WaitHandleCannotBeOpenedException) { } return; }
        using var instance=new Mutex(true,"Local\\QuotaBar.Standalone",out var first);
        if(!first) { try { using var signal=EventWaitHandle.OpenExisting("Local\\QuotaBar.ShowSettings"); signal.Set(); } catch(WaitHandleCannotBeOpenedException) { } return; }
        using var shutdown=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\QuotaBar.Shutdown");
        using var show=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\QuotaBar.ShowSettings");
        var app=new Application { ShutdownMode=ShutdownMode.OnExplicitShutdown };
        Coordinator? coordinator=null;
        var stopWait=ThreadPool.RegisterWaitForSingleObject(shutdown,(_,_)=>app.Dispatcher.BeginInvoke(()=>coordinator?.Quit()),null,Timeout.Infinite,false);
        var showWait=ThreadPool.RegisterWaitForSingleObject(show,(_,_)=>app.Dispatcher.BeginInvoke(()=>coordinator?.ShowSettings()),null,Timeout.Infinite,false);
        app.Startup+=(_,_)=> {
            try { UpdateLocations.AcknowledgeHealth(args,Environment.ProcessPath??""); } catch { app.Shutdown(1); return; }
            coordinator=new Coordinator(app);
            coordinator.Start();
        };
        app.Exit+=(_,_)=>coordinator?.Dispose();
        try { app.Run(); } finally { stopWait.Unregister(null); showWait.Unregister(null); }
    }
}
