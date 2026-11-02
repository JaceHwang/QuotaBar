using QuotaBar.Core;

static class WindowsReliabilityTests {
    static void Check(bool value,string message) { if(!value) throw new Exception(message); }
    static void InvalidHandle(string source,string destination,bool overwrite)=>throw new IOException("Invalid handle",unchecked((int)0x80070006));
    public static void Settings() {
        var root=Path.Combine(Path.GetTempPath(),"preferences-compat-"+Guid.NewGuid());Directory.CreateDirectory(root);var path=Path.Combine(root,"preferences.json");
        static void Fails(Action action) { try { action(); } catch(IOException) { return; } throw new Exception("Expected failed settings save"); }
        try {
            var ordinary=Path.Combine(root,"ordinary.json");
            new PreferencesStore(ordinary,File.Move,(_,_,_)=>throw new Exception("unnecessary fallback")).Save(new());
            Check(File.Exists(ordinary)&&!File.Exists(ordinary+".backup"),"normal atomic save does not use compatibility copy");
            var store=new PreferencesStore(path,InvalidHandle);
            store.Save(new Preferences { FloatingBackgroundTransparency=35,Theme="dark",Language="zh-CN" });
            store.Save(store.Load() with { FloatingBackgroundTransparency=65 });
            Check(new PreferencesStore(path).Load() is { FloatingBackgroundTransparency:65,Theme:"dark",Language:"zh-CN" },"transparency and unrelated preferences survive reload");
            Check(new PreferencesStore(path+".backup").Load().FloatingBackgroundTransparency==35,"previous preferences backed up");
            var saved=File.ReadAllBytes(path);
            Fails(()=>new PreferencesStore(path,(_,_,_)=>throw new IOException("denied",unchecked((int)0x80070005))).Save(new()));
            Check(File.ReadAllBytes(path).SequenceEqual(saved),"unrelated I/O error preserves settings");
            var copies=0;
            var interrupted=new PreferencesStore(path,InvalidHandle,(source,destination,overwrite)=> {
                if(++copies==2) { File.WriteAllText(destination,"{broken");throw new IOException("partial write"); }
                File.Copy(source,destination,overwrite);
            });
            Fails(()=>interrupted.Save(new()));Check(File.ReadAllBytes(path).SequenceEqual(saved),"partial write restores preferences");
            copies=0;
            var failedRestore=new PreferencesStore(path,InvalidHandle,(source,destination,overwrite)=> {
                if(++copies==2) { File.WriteAllText(destination,"{broken");throw new IOException("partial write"); }
                if(copies==3)throw new IOException("restore failed");File.Copy(source,destination,overwrite);
            });
            Fails(()=>failedRestore.Save(new()));var backup=File.ReadAllBytes(path+".backup");
            Fails(()=>failedRestore.Save(new()));Fails(()=>new PreferencesStore(path,InvalidHandle).Save(new()));
            Check(File.ReadAllBytes(path+".backup").SequenceEqual(backup)&&backup.SequenceEqual(saved),"failed restore preserves backup across retry and restart");
            Check(!Directory.EnumerateFiles(root,"*.tmp").Any(),"settings temp files cleaned");
            Console.WriteLine("PASS preferences invalid-handle fallback, transparency reload and backup recovery protection");
        } finally { Directory.Delete(root,true); }
    }
    public static async Task Readiness() {
        var elapsed=TimeSpan.Zero;
        Task Advance(TimeSpan duration,CancellationToken token) { token.ThrowIfCancellationRequested();elapsed+=TimeSpan.FromSeconds(1);return Task.CompletedTask; }
        await UpdateHelperReadiness.WaitAsync(()=>elapsed>=TimeSpan.FromSeconds(15),()=>false,default,()=>elapsed,Advance);
        Check(elapsed==TimeSpan.FromSeconds(15),"slow healthy helper reaches ready after old ten-second limit");
        elapsed=TimeSpan.Zero;
        try { await UpdateHelperReadiness.WaitAsync(()=>false,()=>false,default,()=>elapsed,Advance);throw new Exception("missing timeout"); }
        catch(IOException) { Check(elapsed==TimeSpan.FromSeconds(120),"unresponsive helper remains bounded to 120 seconds"); }
        elapsed=TimeSpan.Zero;
        try { await UpdateHelperReadiness.WaitAsync(()=>false,()=>true,default,()=>elapsed,Advance);throw new Exception("ignored helper exit"); }
        catch(IOException) { Check(elapsed==TimeSpan.Zero,"helper exit fails immediately"); }
        using var cancel=new CancellationTokenSource();cancel.Cancel();
        try { await UpdateHelperReadiness.WaitAsync(()=>false,()=>false,cancel.Token,()=>elapsed,Advance);throw new Exception("ignored cancellation"); }
        catch(OperationCanceledException) { Check(elapsed==TimeSpan.Zero,"cancellation stays immediate"); }
        Console.WriteLine("PASS helper readiness slow success, bounded timeout, exit and cancellation");
    }
}
