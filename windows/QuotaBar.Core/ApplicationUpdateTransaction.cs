using System.Diagnostics;
using System.Text.Json;
namespace QuotaBar.Core;
public sealed record UpdateInstallJob(int Schema,string OperationID,string Target,int ParentPID,string Nonce,DateTimeOffset ExpiresAt,TrustedUpdateRelease Release) {
    static readonly JsonSerializerOptions Json=new() { PropertyNamingPolicy=JsonNamingPolicy.CamelCase,PropertyNameCaseInsensitive=true };
    public void Validate(string directory,string expectedTarget,DateTimeOffset now) {
        if(Schema!=1 || !Guid.TryParse(OperationID,out _) || !string.Equals(Target,expectedTarget,OperatingSystem.IsWindows()?StringComparison.OrdinalIgnoreCase:StringComparison.Ordinal) || ParentPID<=1 || !TrustedUpdateRelease.Hex(Nonce,64) || now>=ExpiresAt || ExpiresAt-now>TimeSpan.FromSeconds(601) || File.Exists(Path.Combine(directory,"consumed")) || !TrustedUpdateRelease.Hex(Release.SourceCommit,40)) throw new IOException("Invalid, expired or consumed update job");
        PackageVerifier.RejectLinks(directory);
    }
    public static ApplicationUpdatePhase? ConsumeResult(string cache,string expectedTarget) {
        string[] paths;
        try { if(!Directory.Exists(cache)) return null; paths=Directory.GetDirectories(cache).OrderByDescending(Directory.GetLastWriteTimeUtc).Take(100).ToArray(); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException) { return null; }
        foreach(var directory in paths) {
            try {
                if(!Guid.TryParse(Path.GetFileName(directory),out _) || File.Exists(Path.Combine(directory,"presented"))) continue;
                PackageVerifier.RejectLinks(directory); var job=Read(directory);
                if(job.Target!=expectedTarget || DateTimeOffset.UtcNow-job.ExpiresAt>TimeSpan.FromDays(1)) continue;
                foreach(var (kind,phase) in new[]{("succeeded",ApplicationUpdatePhase.Succeeded),("rolledBack",ApplicationUpdatePhase.RolledBack),("failed",ApplicationUpdatePhase.Failed)}) if(job.HasReceipt(kind,directory)) { File.WriteAllText(Path.Combine(directory,"presented"),""); return phase; }
            } catch(Exception e) when(e is IOException or JsonException or UnauthorizedAccessException) { }
        }
        return null;
    }
    public void Write(string directory)=>Atomic(Path.Combine(directory,"job.json"),this);
    public static UpdateInstallJob Read(string directory) {
        var path=Path.Combine(directory,"job.json"); if(new FileInfo(path).Length>=65536) throw new IOException("Oversized job");
        return JsonSerializer.Deserialize<UpdateInstallJob>(File.ReadAllText(path),Json)??throw new IOException("Invalid update job");
    }
    public void Receipt(string kind,string directory)=>Atomic(Path.Combine(directory,kind+".json"),new UpdateReceipt(1,OperationID,Nonce,kind));
    public bool HasReceipt(string kind,string directory) {
        try { var path=Path.Combine(directory,kind+".json"); if(new FileInfo(path).Length>=4096) return false; var receipt=JsonSerializer.Deserialize<UpdateReceipt>(File.ReadAllText(path),Json); return receipt==new UpdateReceipt(1,OperationID,Nonce,kind); }
        catch(Exception e) when(e is IOException or JsonException or UnauthorizedAccessException) { return false; }
    }
    public static void Atomic<T>(string path,T value) {
        var temp=path+"."+Guid.NewGuid().ToString("N");
        using(var output=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { JsonSerializer.Serialize(output,value,Json); output.Flush(true); }
        File.Move(temp,path,true);
    }
}
public sealed record UpdateReceipt(int Schema,string OperationID,string Nonce,string Kind);
public static class UpdateLocations {
    public static string Target=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","QuotaBar");
    public static string Cache=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"QuotaBar","Updates");
    public static string DirectoryPath(string path) {
        var full=Path.GetFullPath(path);
        if(!string.Equals(Path.GetDirectoryName(full),Cache,StringComparison.OrdinalIgnoreCase) || !Guid.TryParse(Path.GetFileName(full),out _)) throw new IOException("Unmanaged update directory");
        PackageVerifier.RejectLinks(full); return full;
    }
    public static void AcknowledgeHealth(string[] args,string executable) {
        var index=Array.IndexOf(args,"--update-health"); if(index<0) return;
        if(args.Length<=index+2 || !string.Equals(executable,Path.Combine(Target,"QuotaBar.exe"),StringComparison.OrdinalIgnoreCase)) throw new IOException("Unexpected health target");
        var directory=DirectoryPath(args[index+1]); var job=UpdateInstallJob.Read(directory);
        if(job.Target!=Target || job.Nonce!=args[index+2] || DateTimeOffset.UtcNow>=job.ExpiresAt || !File.Exists(Path.Combine(directory,"consumed"))) throw new IOException("Invalid health handshake");
        job.Receipt("health",directory);
    }
}
public static class ApplicationUpdateTransaction {
    public static void Run(UpdateInstallJob job,string directory,TransactionInstaller installer,Action<string,string[]> launchOld) {
        job.Validate(directory,UpdateLocations.Target,DateTimeOffset.UtcNow);
        using var reservation=new UpdateHandoffReservation(UpdateLocations.Target);
        var archive=Path.Combine(directory,job.Release.Package.Name); var proof=Path.Combine(directory,job.Release.Provenance.Name);
        UpdateDownloadClient.VerifyFile(archive,job.Release.Package).GetAwaiter().GetResult(); UpdateDownloadClient.VerifyFile(proof,job.Release.Provenance).GetAwaiter().GetResult();
        var candidate=UpdateStaging.VerifyStaged(new(job.Release,directory,archive,proof),Path.Combine(directory,"expanded","QuotaBar"),Path.Combine(directory,"revalidated"));
        UpdateDownloadClient.VerifyProvenance(File.ReadAllBytes(proof),job.Release);
        if(File.ReadAllText(Path.Combine(candidate,"PROVENANCE.json"))!=File.ReadAllText(proof) || PackageVerifier.Verify(candidate).Version!=job.Release.Version) throw new IOException("Prepared package changed");
        using var parent=Process.GetProcessById(job.ParentPID);
        if(!string.Equals(parent.MainModule?.FileName,Path.Combine(job.Target,"QuotaBar.exe"),StringComparison.OrdinalIgnoreCase)) throw new IOException("Unexpected parent");
        using var locked=new FileStream(Path.Combine(directory,"operation.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        using(var consumed=new FileStream(Path.Combine(directory,"consumed"),FileMode.CreateNew,FileAccess.Write,FileShare.None)) { consumed.Flush(true); }
        job.Receipt("ready",directory);
        if(!parent.WaitForExit(20000)) { job.Receipt("failed",directory); throw new IOException("Parent did not exit; installation unchanged"); }
        if(!job.HasReceipt("handoff",directory)) { job.Receipt("failed",directory); throw new IOException("Parent exited without update handoff permission"); }
        Process? started=null;
        try {
            installer.Install(candidate,()=> {
                var start=new ProcessStartInfo(Path.Combine(job.Target,"QuotaBar.exe")) { UseShellExecute=false,WorkingDirectory=job.Target };
                foreach(var arg in new[]{"--update-health",directory,job.Nonce}) start.ArgumentList.Add(arg);
                started=Process.Start(start)??throw new IOException("Updated app did not launch");
                var deadline=DateTimeOffset.UtcNow.AddSeconds(15);
                while(!job.HasReceipt("health",directory)) {
                    if(started.HasExited || DateTimeOffset.UtcNow>=deadline) throw new IOException("Updated app did not acknowledge startup"); Thread.Sleep(50);
                }
                if(started.WaitForExit(2000)) throw new IOException("Updated app exited during startup");
            });
        } catch {
            if(started is { HasExited:false }) { started.Kill(true); started.WaitForExit(6000); }
            TryReceipt(job,installer.RecoveryPending?"failed":"rolledBack",directory);
            if(!installer.RecoveryPending) launchOld(Path.Combine(job.Target,"QuotaBar.exe"),[]);
            throw;
        } finally { started?.Dispose(); }
        TryReceipt(job,"succeeded",directory);
    }
    static void TryReceipt(UpdateInstallJob job,string kind,string directory) {
        try { job.Receipt(kind,directory); } catch(Exception e) when(e is IOException or UnauthorizedAccessException) { }
    }
}

public sealed class UpdateHandoffReservation : IDisposable {
    readonly FileStream stream;
    public UpdateHandoffReservation(string target) {
        var store=Path.Combine(Path.GetDirectoryName(target)!,".QuotaBar-install"); Directory.CreateDirectory(store);
        var path=Path.Combine(store,"handoff.lock");
        if((File.GetAttributes(store)&FileAttributes.ReparsePoint)!=0 || File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked update reservation");
        stream=new FileStream(path,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
    }
    public void Dispose()=>stream.Dispose();
}
