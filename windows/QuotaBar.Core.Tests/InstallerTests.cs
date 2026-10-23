using System.Security.Cryptography;
using System.Text.Json;
using QuotaBar.Core;

static class InstallerTests {
    public static void Run() {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-install-"+Guid.NewGuid()); Directory.CreateDirectory(root);
        try {
            var one=Candidate(root,"one"); var two=Candidate(root,"two");
            var target=Path.Combine(root,"Programs","QuotaBar");
            var activated=""; var fail=false; var stops=0;
            var installer=new TransactionInstaller(target,new InstallHooks(()=>stops++,()=>true,(path,startup)=> { activated=path; if(fail) { fail=false; throw new IOException("injected activation failure"); } },()=>{}));
            installer.Install(one); Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one","first install");
            installer.Install(two); Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="two","upgrade");
            fail=true; Throws(()=>installer.Rollback()); Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="two","failed rollback keeps current");
            installer.Rollback(); Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one","rollback");
            fail=true; Throws(()=>installer.Install(two)); Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one" && activated==target,"failed activation restored");
            Throws(()=>installer.Install(two,()=>throw new IOException("new application failed health")));
            Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one","health failure restores old version under transaction lock");
            File.WriteAllText(Path.Combine(two,"QuotaBar.exe"),"tampered"); Throws(()=>installer.Install(two));
            Check(File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one","tampering rejected before mutation");
            installer.Uninstall(); Check(!Directory.Exists(target),"uninstalled into recoverable backup");
            installer.Rollback(); Check(Directory.Exists(target),"uninstall recoverable");
            var store=Path.Combine(root,"Programs",".QuotaBar-install"); var backup=Path.Combine(store,"backup-interrupted");
            Directory.Move(target,backup);
            Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target,"QuotaBar.exe"),"interrupted new version");
            File.WriteAllText(Path.Combine(store,"journal.json"),JsonSerializer.Serialize(new { Target=target,Stage=Path.Combine(store,"stage-missing"),Backup=backup,HadPrevious=true,Startup=true,PreviousHistory=(string?)null }));
            var before=stops; installer.RecoverInterrupted();
            Check(stops>before && File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one","interrupted recovery stops active app first");
            var legacyEnabled=true;
            // A failed first install has no previous package to reactivate, so restoration can complete.
            var newTarget=Path.Combine(root,"Fresh","QuotaBar");
            var migration=new TransactionInstaller(newTarget,new InstallHooks(()=>{},()=>false,(_,_)=>throw new IOException("activation failed after migration"),()=>{},()=>new LegacyState(legacyEnabled,false,[]),()=>legacyEnabled=false,s=>legacyEnabled=s.PluginEnabled==true));
            Throws(()=>migration.Install(one)); Check(legacyEnabled && !Directory.Exists(newTarget),"failed installation restores legacy registration");
            legacyEnabled=true;
            var upgradeFailure=new TransactionInstaller(target,new InstallHooks(()=>{},()=>false,(_,_)=>throw new IOException("persistent shortcut failure"),()=>{},()=>new LegacyState(legacyEnabled,false,[]),()=>legacyEnabled=false,s=>legacyEnabled=s.PluginEnabled==true));
            Throws(()=>upgradeFailure.Install(one));
            Check(upgradeFailure.RecoveryPending,"incomplete recovery retains journal for manual recovery");
            Check(legacyEnabled && File.ReadAllText(Path.Combine(target,"QuotaBar.exe"))=="one","legacy restored even when old application activation still fails");
        } finally { Directory.Delete(root,true); }
    }
    static string Candidate(string root,string label) {
        var dir=Path.Combine(root,label); Directory.CreateDirectory(Path.Combine(dir,"runtime")); Directory.CreateDirectory(Path.Combine(dir,"setup"));
        File.WriteAllText(Path.Combine(dir,"setup","QuotaBar.Setup.exe"),"fixture setup");
        File.WriteAllText(Path.Combine(dir,"QuotaBar.exe"),label); File.WriteAllText(Path.Combine(dir,"runtime","codex.exe"),"fixture runtime");
        var files=new Dictionary<string,string>();
        foreach(var path in Directory.GetFiles(dir,"*",SearchOption.AllDirectories)) files[Path.GetRelativePath(dir,path).Replace('\\','/')]=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant();
        File.WriteAllText(Path.Combine(dir,"package.json"),JsonSerializer.Serialize(new PackageManifest(1,"QuotaBar","windows-x64","0.6.0","0.144.1",files)));
        return dir;
    }
    static void Check(bool b,string m) { if(!b) throw new Exception(m); }
    static void Throws(Action run) { try { run(); } catch(IOException) { return; } throw new Exception("Expected install rejection"); }
}
