using System.Diagnostics;
using System.Security.Cryptography;
namespace QuotaBar.Windows;
internal sealed class ApplicationUpdateService {
    public ApplicationUpdateOperation Operation { get; }
    public ApplicationUpdateService(string currentVersion,Func<string,Action<ApplicationUpdateProgress>,CancellationToken,Task>? execute=null) {
        Operation=new(execute??((version,emit,cancel)=>Perform(version,currentVersion,emit,cancel)));
        if(execute is null && string.Equals(Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar),UpdateLocations.Target,StringComparison.OrdinalIgnoreCase)) {
            if(UpdateInstallJob.ConsumeResult(UpdateLocations.Cache,UpdateLocations.Target) is { } result) Operation.ReportResult(result);
            ReadResultAfterStartup();
        }
    }
    async void ReadResultAfterStartup() {
        await Task.Delay(3000);
        if(Operation.Progress.Phase==ApplicationUpdatePhase.Idle && UpdateInstallJob.ConsumeResult(UpdateLocations.Cache,UpdateLocations.Target) is { } result) Operation.ReportResult(result);
    }
    static async Task Perform(string version,string currentVersion,Action<ApplicationUpdateProgress> emit,CancellationToken cancel) {
        if(!string.Equals(Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar),UpdateLocations.Target,StringComparison.OrdinalIgnoreCase)) throw new IOException("Install QuotaBar in the standard per-user directory first");
        using var transport=new UpdateHttpTransport();
        var download=await new UpdateDownloadClient(transport).Download(version,"windows-x64",currentVersion,UpdateLocations.Cache,(n,total)=>emit(new(ApplicationUpdatePhase.Downloading,n,total,null)),cancel);
        var handedOff=false; Process? helper=null;
        try {
            emit(new(ApplicationUpdatePhase.Verifying,0,0,null)); UpdateStaging.VerifyPackage(download,Path.Combine(download.Directory,"expanded"),cancel); cancel.ThrowIfCancellationRequested();
            emit(new(ApplicationUpdatePhase.Preparing,0,0,null));
            var current=Path.Combine(AppContext.BaseDirectory,"setup"); var copied=Path.Combine(download.Directory,"current-setup"); Copy(current,copied,cancel);
            var job=new UpdateInstallJob(1,Guid.NewGuid().ToString("N"),UpdateLocations.Target,Environment.ProcessId,Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant(),DateTimeOffset.UtcNow.AddMinutes(10),download.Release); job.Write(download.Directory);
            cancel.ThrowIfCancellationRequested(); var start=new ProcessStartInfo(Path.Combine(copied,"QuotaBar.Setup.exe")) { UseShellExecute=false,CreateNoWindow=true };
            start.ArgumentList.Add("update"); start.ArgumentList.Add(download.Directory); helper=Process.Start(start)??throw new IOException("Update helper unavailable");
            var deadline=DateTimeOffset.UtcNow.AddSeconds(10);
            while(!job.HasReceipt("ready",download.Directory)) { cancel.ThrowIfCancellationRequested(); if(helper.HasExited || DateTimeOffset.UtcNow>=deadline) throw new IOException("Update helper not ready"); await Task.Delay(50,cancel); }
            cancel.ThrowIfCancellationRequested(); handedOff=true;
        } finally {
            if(!handedOff) { if(helper is { HasExited:false }) { helper.Kill(true); helper.WaitForExit(6000); } try { Directory.Delete(download.Directory,true); } catch(IOException) { } catch(UnauthorizedAccessException) { } }
            helper?.Dispose();
        }
    }
    static void Copy(string source,string destination,CancellationToken cancel) {
        if((File.GetAttributes(source)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked local helper");
        Directory.CreateDirectory(destination);
        foreach(var path in Directory.GetFiles(source)) { cancel.ThrowIfCancellationRequested(); if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked helper file"); var output=Path.Combine(destination,Path.GetFileName(path)); File.Copy(path,output); if(!SHA256.HashData(File.ReadAllBytes(path)).SequenceEqual(SHA256.HashData(File.ReadAllBytes(output)))) throw new IOException("Helper copy mismatch"); }
        foreach(var path in Directory.GetDirectories(source)) Copy(path,Path.Combine(destination,Path.GetFileName(path)),cancel);
    }
}
