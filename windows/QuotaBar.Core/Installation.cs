using System.Security.Cryptography;
using System.Text.Json;

namespace QuotaBar.Core;
public sealed record PackageManifest(int Schema,string Product,string Platform,string Version,string RuntimeVersion,Dictionary<string,string> Files);
public static class PackageVerifier {
    public static PackageManifest Verify(string directory) {
        try {
            RejectLinks(directory);
            var manifest=JsonSerializer.Deserialize<PackageManifest>(File.ReadAllText(System.IO.Path.Combine(directory,"package.json")),new JsonSerializerOptions { PropertyNameCaseInsensitive=true });
            if(manifest is null || manifest.Schema!=1 || manifest.Product!="QuotaBar" || manifest.Platform!="windows-x64" || manifest.RuntimeVersion!="0.144.1" || manifest.Files.Count==0) throw new IOException("Unsupported package manifest");
            if(!manifest.Files.ContainsKey("QuotaBar.exe") || !manifest.Files.ContainsKey("runtime/codex.exe") || !manifest.Files.ContainsKey("setup/QuotaBar.Setup.exe")) throw new IOException("Incomplete standalone package");
            foreach(var (relative,expected) in manifest.Files) {
                if(relative.Contains('\\') || relative.StartsWith('/') || relative.Split('/').Any(p=>p is ".." or "." or "")) throw new IOException("Invalid manifest path");
                var path=System.IO.Path.GetFullPath(System.IO.Path.Combine(directory,relative));
                EnsureInside(directory,path);
                using var input=File.OpenRead(path);
                var actual=Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant();
                if(!string.Equals(actual,expected,StringComparison.Ordinal)) throw new IOException("Package checksum mismatch: "+relative);
            }
            foreach(var path in Directory.GetFiles(directory,"*",SearchOption.AllDirectories)) {
                var relative=System.IO.Path.GetRelativePath(directory,path).Replace('\\','/');
                if(relative!="package.json" && !manifest.Files.ContainsKey(relative)) throw new IOException("Unlisted package file: "+relative);
            }
            return manifest;
        } catch(Exception e) when(e is JsonException or UnauthorizedAccessException or ArgumentException or NullReferenceException) { throw new IOException("Invalid package",e); }
    }
    internal static void EnsureInside(string root,string path) {
        var prefix=System.IO.Path.GetFullPath(root).TrimEnd(System.IO.Path.DirectorySeparatorChar)+System.IO.Path.DirectorySeparatorChar;
        if(!System.IO.Path.GetFullPath(path).StartsWith(prefix,OperatingSystem.IsWindows()?StringComparison.OrdinalIgnoreCase:StringComparison.Ordinal)) throw new IOException("Path outside managed directory");
    }
    internal static void RejectLinks(string root) {
        if((File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked package directory is not supported");
        foreach(var p in Directory.EnumerateFileSystemEntries(root)) {
            if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked package content is not supported");
            if(Directory.Exists(p)) RejectLinks(p);
        }
    }
}

public sealed record InstallHooks(Action StopOwnedApplication,Func<bool> StartupEnabled,Action<string,bool> Activate,Action Deactivate,Func<LegacyState>? CaptureLegacy=null,Action? SuspendLegacy=null,Action<LegacyState>? RestoreLegacy=null);
public sealed class TransactionInstaller {
    private sealed record Journal(string Target,string Stage,string Backup,bool HadPrevious,bool Startup,string? PreviousHistory,LegacyState? Legacy);
    private sealed record History(string Backup,bool Startup);
    readonly string target,store,journalPath,historyPath;
    public bool RecoveryPending=>File.Exists(journalPath);
    readonly InstallHooks hooks;
    public TransactionInstaller(string target,InstallHooks hooks) {
        this.target=Path.GetFullPath(target); this.hooks=hooks;
        store=Path.Combine(Path.GetDirectoryName(this.target)!,".QuotaBar-install"); journalPath=Path.Combine(store,"journal.json"); historyPath=Path.Combine(store,"history.json");
    }
    FileStream Lock() { Directory.CreateDirectory(store); return new(Path.Combine(store,"install.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None); }
    public void Install(string candidate,Action? verifyHealth=null) {
        using var locked=Lock(); Recover();
        candidate=Path.GetFullPath(candidate); PackageVerifier.Verify(candidate);
        if(candidate==target || candidate.StartsWith(target+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)) throw new IOException("Candidate cannot be inside active installation");
        var stage=Path.Combine(store,"stage-"+Guid.NewGuid()); var backup=Path.Combine(store,"backup-"+Guid.NewGuid());
        Copy(candidate,stage); PackageVerifier.Verify(stage);
        var j=new Journal(target,stage,backup,Directory.Exists(target),hooks.StartupEnabled(),HistorySnapshot(),hooks.CaptureLegacy?.Invoke()); Write(journalPath,j);
        try {
            hooks.StopOwnedApplication();
            hooks.SuspendLegacy?.Invoke();
            if(j.HadPrevious) Directory.Move(target,backup);
            Directory.Move(stage,target);
            hooks.Activate(target,j.Startup);
            verifyHealth?.Invoke();
            if(j.HadPrevious) Write(historyPath,new History(backup,j.Startup));
            File.Delete(journalPath);
        } catch { Recover(); throw; }
    }
    public void Rollback() {
        using var locked=Lock(); Recover();
        var history=Read<History>(historyPath)??throw new IOException("No recoverable backup"); ValidateManaged(history.Backup);
        PackageVerifier.Verify(history.Backup);
        var backup=Path.Combine(store,"backup-"+Guid.NewGuid());
        var j=new Journal(target,history.Backup,backup,Directory.Exists(target),hooks.StartupEnabled(),HistorySnapshot(),hooks.CaptureLegacy?.Invoke()); Write(journalPath,j);
        try {
            hooks.StopOwnedApplication(); if(j.HadPrevious) Directory.Move(target,backup);
            hooks.SuspendLegacy?.Invoke();
            Directory.Move(history.Backup,target); hooks.Activate(target,history.Startup);
            if(j.HadPrevious) Write(historyPath,new History(backup,j.Startup)); else File.Delete(historyPath);
            File.Delete(journalPath);
        } catch { Recover(); throw; }
    }
    public void Uninstall() {
        using var locked=Lock(); Recover(); if(!Directory.Exists(target)) return;
        var backup=Path.Combine(store,"backup-"+Guid.NewGuid()); var j=new Journal(target,"",backup,true,hooks.StartupEnabled(),HistorySnapshot(),null); Write(journalPath,j);
        try {
            hooks.StopOwnedApplication(); Directory.Move(target,backup); hooks.Deactivate();
            Write(historyPath,new History(backup,j.Startup)); File.Delete(journalPath);
        } catch { Recover(); throw; }
    }
    public void RecoverInterrupted() { using var locked=Lock(); Recover(); }
    void Recover() {
        if(!File.Exists(journalPath)) return;
        var j=Read<Journal>(journalPath)??throw new IOException("Unreadable installation journal");
        if(j.Target!=target) throw new IOException("Unexpected recovery target"); ValidateManaged(j.Backup); if(j.Stage!="") ValidateManaged(j.Stage);
        hooks.StopOwnedApplication();
        if(Directory.Exists(j.Backup)) {
            if(Directory.Exists(target)) {
                // A failed rollback must put the consumed backup back where history points.
                var destination=Path.GetFileName(j.Stage).StartsWith("backup-",StringComparison.Ordinal) && !Directory.Exists(j.Stage) ? j.Stage : Path.Combine(store,"failed-"+Guid.NewGuid());
                Directory.Move(target,destination);
            }
            Directory.Move(j.Backup,target);
        } else if(!j.HadPrevious && Directory.Exists(target) && !Directory.Exists(j.Stage)) {
            Directory.Move(target,Path.Combine(store,"failed-"+Guid.NewGuid()));
        }
        var failures=new List<Exception>();
        void Attempt(Action action) {
            try { action(); }
            catch(Exception e) when(e is IOException or UnauthorizedAccessException or InvalidOperationException or System.ComponentModel.Win32Exception or System.Runtime.InteropServices.COMException or JsonException) { failures.Add(e); }
        }
        // Restore independent registrations even when a shortcut or startup service remains unavailable.
        if(j.Legacy is not null) Attempt(()=>hooks.RestoreLegacy?.Invoke(j.Legacy));
        Attempt(()=> { if(Directory.Exists(target)) hooks.Activate(target,j.Startup); else hooks.Deactivate(); });
        Attempt(()=> {
        if(j.PreviousHistory is null) File.Delete(historyPath); else {
            var old=JsonSerializer.Deserialize<History>(j.PreviousHistory)??throw new IOException("Invalid previous installation history");
            ValidateManaged(old.Backup); Write(historyPath,old);
        }
        });
        if(failures.Count>0) throw new IOException("Installation recovery incomplete; journal retained for retry",new AggregateException(failures));
        File.Delete(journalPath);
    }
    string? HistorySnapshot()=>File.Exists(historyPath)?File.ReadAllText(historyPath):null;
    void ValidateManaged(string path) { PackageVerifier.EnsureInside(store,path); }
    static T? Read<T>(string path) {
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(path)); }
        catch(Exception e) when(e is JsonException or IOException) { throw new IOException("Invalid installation state",e); }
    }
    static void Write<T>(string path,T value) {
        var temp=path+".tmp";
        using(var stream=new FileStream(temp,FileMode.Create,FileAccess.Write,FileShare.None)) { JsonSerializer.Serialize(stream,value); stream.Flush(true); }
        File.Move(temp,path,true);
    }
    static void Copy(string source,string destination) {
        Directory.CreateDirectory(destination);
        foreach(var file in Directory.GetFiles(source)) File.Copy(file,Path.Combine(destination,Path.GetFileName(file)));
        foreach(var dir in Directory.GetDirectories(source)) Copy(dir,Path.Combine(destination,Path.GetFileName(dir)));
    }
}
