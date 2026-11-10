namespace QuotaBar.Core;

/// Asset data survives individual installation attempts. Every use is checked
/// against freshly resolved release metadata before a new job is prepared.
internal sealed class UpdateDownloadCache : IDisposable {
    readonly string cache,directory;
    readonly FileStream reservation;

    internal UpdateDownloadCache(string cache) {
        this.cache=cache;
        directory=Path.Combine(cache,"downloads");
        if(Directory.Exists(directory) && (File.GetAttributes(directory)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked download cache");
        Directory.CreateDirectory(directory);
        var lockPath=Path.Combine(directory,"download.lock");
        if(File.Exists(lockPath) && (File.GetAttributes(lockPath)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked download lock");
        reservation=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
    }

    internal async Task<string> Get(UpdateAsset asset,IUpdateTransport transport,Action<long> progress,CancellationToken cancel) {
        var path=Path.Combine(directory,asset.Sha256);
        if(File.Exists(path)) {
            if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked cached asset");
            if(new FileInfo(path).Length>=asset.Size) {
                if(await Verified(path,asset,cancel)) { progress(asset.Size);return path; }
                File.Delete(path);
            }
        }
        if(await ImportLegacy(path,asset,cancel)) { progress(asset.Size);return path; }
        var received=File.Exists(path)?new FileInfo(path).Length:0;
        var free=new DriveInfo(Path.GetPathRoot(Path.GetFullPath(directory))!).AvailableFreeSpace;
        if(free<asset.Size-received+64L*1024*1024) throw new IOException("Insufficient download space");
        progress(received);
        await transport.Download(asset,path,progress,cancel);
        cancel.ThrowIfCancellationRequested();
        try { await UpdateDownloadClient.VerifyFile(path,asset,cancel); }
        catch(IOException) { File.Delete(path);throw; }
        return path;
    }

    async Task<bool> ImportLegacy(string destination,UpdateAsset asset,CancellationToken cancel) {
        foreach(var job in Directory.GetDirectories(cache).OrderByDescending(Directory.GetLastWriteTimeUtc).Take(100)) {
            cancel.ThrowIfCancellationRequested();
            if(!Guid.TryParse(Path.GetFileName(job),out _) || (File.GetAttributes(job)&FileAttributes.ReparsePoint)!=0) continue;
            var source=Path.Combine(job,asset.Name);
            if(!await Verified(source,asset,cancel)) continue;
            File.Copy(source,destination,true);
            await UpdateDownloadClient.VerifyFile(destination,asset,cancel);
            return true;
        }
        return false;
    }

    static async Task<bool> Verified(string path,UpdateAsset asset,CancellationToken cancel) {
        try { await UpdateDownloadClient.VerifyFile(path,asset,cancel);return true; }
        catch(Exception error) when(error is IOException or UnauthorizedAccessException) { return false; }
    }

    public void Dispose()=>reservation.Dispose();
}
