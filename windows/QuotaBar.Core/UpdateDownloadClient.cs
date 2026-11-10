using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace QuotaBar.Core;
public interface IUpdateTransport {
    Task<byte[]> Metadata(Uri url,int limit,CancellationToken cancel);
    Task Download(UpdateAsset asset,string destination,Action<long> progress,CancellationToken cancel);
}
public sealed record DownloadedUpdate(TrustedUpdateRelease Release,string Directory,string Archive,string Provenance);
public sealed class UpdateDownloadClient(IUpdateTransport transport) {
    public async Task<DownloadedUpdate> Download(string version,string platform,string currentVersion,string cache,Action<long,long>? progress=null,CancellationToken cancel=default,bool allowBeta=false) {
        var metadata=await transport.Metadata(TrustedUpdateRelease.ApiUrl(version),2*1024*1024,cancel);
        var tag=await transport.Metadata(TrustedUpdateRelease.TagUrl(version),1024*1024,cancel);
        for(var i=0;i<2;i++) {
            using var doc=JsonDocument.Parse(tag); var obj=doc.RootElement.GetProperty("object"); if(obj.GetProperty("type").GetString()=="commit") break;
            var sha=obj.GetProperty("sha").GetString()!;
            if(obj.GetProperty("type").GetString()!="tag" || !TrustedUpdateRelease.Hex(sha,40)) throw new FormatException("Invalid tag");
            tag=await transport.Metadata(new Uri($"https://api.github.com/repos/{TrustedUpdateRelease.Repository}/git/tags/{sha}"),1024*1024,cancel);
        }
        var release=TrustedUpdateRelease.Parse(new UTF8Encoding(false,true).GetString(metadata),new UTF8Encoding(false,true).GetString(tag),version,platform,currentVersion,allowBeta);
        cancel.ThrowIfCancellationRequested();
        if(Directory.Exists(cache) && (File.GetAttributes(cache)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked update cache");
        Directory.CreateDirectory(cache);
        using var assets=new UpdateDownloadCache(cache);
        var cachedArchive=await assets.Get(release.Package,transport,n=>progress?.Invoke(n,release.Package.Size),cancel);
        var cachedProof=await assets.Get(release.Provenance,transport,_=>{},cancel);
        VerifyProvenance(await File.ReadAllBytesAsync(cachedProof,cancel),release);
        cancel.ThrowIfCancellationRequested();
        var directory=Path.Combine(cache,Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
        try {
            var free=new DriveInfo(Path.GetPathRoot(Path.GetFullPath(cache))!).AvailableFreeSpace;
            if(free<release.Package.Size+release.Provenance.Size+64L*1024*1024) throw new IOException("Insufficient update space");
            var archive=Path.Combine(directory,release.Package.Name); var proof=Path.Combine(directory,release.Provenance.Name);
            File.Copy(cachedArchive,archive);
            cancel.ThrowIfCancellationRequested(); await VerifyFile(archive,release.Package,cancel);
            File.Copy(cachedProof,proof);
            cancel.ThrowIfCancellationRequested(); await VerifyFile(proof,release.Provenance,cancel);
            VerifyProvenance(await File.ReadAllBytesAsync(proof,cancel),release);
            cancel.ThrowIfCancellationRequested(); return new(release,directory,archive,proof);
        } catch { try { Directory.Delete(directory,true); } catch(IOException) { } catch(UnauthorizedAccessException) { } throw; }
    }
    public static async Task VerifyFile(string path,UpdateAsset asset,CancellationToken cancel=default) {
        if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0 || new FileInfo(path).Length!=asset.Size) throw new IOException("Invalid update file");
        await using var file=File.OpenRead(path); var digest=Convert.ToHexString(await SHA256.HashDataAsync(file,cancel)).ToLowerInvariant();
        if(digest!=asset.Sha256) throw new IOException("Update checksum mismatch");
    }
    public static void VerifyProvenance(byte[] bytes,TrustedUpdateRelease release) {
        try {
            if(bytes.Length>1024*1024) throw new FormatException("Oversized provenance");
            using var doc=JsonDocument.Parse(bytes); var r=doc.RootElement;
            if(r.GetProperty("kind").GetString()!="release" || r.GetProperty("workingTreeDirty").GetBoolean() || r.GetProperty("version").GetString()!=release.Version || r.GetProperty("releaseTag").GetString()!="v"+release.Version || r.GetProperty("sourceCommit").GetString()!=release.SourceCommit) throw new FormatException("Update source mismatch");
        } catch(Exception e) when(e is JsonException or KeyNotFoundException or InvalidOperationException) { throw new FormatException("Invalid provenance",e); }
    }
}
public sealed class UpdateHttpTransport : IUpdateTransport,IDisposable {
    readonly HttpClient client;
    public UpdateHttpTransport(HttpMessageHandler? handler=null) {
        client=new(handler??new HttpClientHandler { AllowAutoRedirect=false,UseCookies=false,UseDefaultCredentials=false }) { Timeout=TimeSpan.FromMinutes(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("QuotaBar");
    }
    public async Task<byte[]> Metadata(Uri url,int limit,CancellationToken cancel) {
        if(url.Scheme!="https" || url.Host!="api.github.com" || !url.IsDefaultPort || url.UserInfo.Length!=0 || url.Query.Length!=0 || url.Fragment.Length!=0 || !url.AbsolutePath.StartsWith($"/repos/{TrustedUpdateRelease.Repository}/",StringComparison.Ordinal)) throw new IOException("Untrusted API URL");
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancel); timeout.CancelAfter(TimeSpan.FromSeconds(30));
        using var request=new HttpRequestMessage(HttpMethod.Get,url); request.Headers.Accept.ParseAdd("application/vnd.github+json"); request.Headers.Add("X-GitHub-Api-Version","2022-11-28");
        using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout.Token);
        if(response.StatusCode!=HttpStatusCode.OK || response.Content.Headers.ContentLength>limit) throw new IOException("Update metadata unavailable");
        await using var input=await response.Content.ReadAsStreamAsync(timeout.Token); using var bytes=new MemoryStream(); var buffer=new byte[65536]; int count;
        while((count=await input.ReadAsync(buffer,timeout.Token))>0) { if(bytes.Length+count>limit) throw new IOException("Oversized update metadata"); bytes.Write(buffer,0,count); }
        return bytes.ToArray();
    }
    public async Task Download(UpdateAsset asset,string destination,Action<long> progress,CancellationToken cancel) {
        var url=asset.Url;
        if(url.Host!="github.com" || !url.AbsolutePath.StartsWith($"/{TrustedUpdateRelease.Repository}/releases/download/",StringComparison.Ordinal) || url.Query.Length!=0 || !TrustedUpdateRelease.AllowedDownloadRedirect(url)) throw new IOException("Untrusted download");
        cancel.ThrowIfCancellationRequested();
        if(File.Exists(destination) && (File.GetAttributes(destination)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked download file");
        var offset=File.Exists(destination)?new FileInfo(destination).Length:0;
        if(offset>asset.Size) offset=0;
        if(offset==asset.Size) { progress(offset);return; }
        for(var redirects=0;redirects<=10;redirects++) {
            using var request=new HttpRequestMessage(HttpMethod.Get,url);
            request.Headers.AcceptEncoding.ParseAdd("identity");
            if(offset>0) request.Headers.Range=new System.Net.Http.Headers.RangeHeaderValue(offset,null);
            using var response=await client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancel);
            if((int)response.StatusCode is 301 or 302 or 303 or 307 or 308) {
                if(redirects==10 || response.Headers.Location is not { } location) throw new IOException("Invalid redirect");
                url=location.IsAbsoluteUri?location:new Uri(url,location);
                if(!TrustedUpdateRelease.AllowedDownloadRedirect(url)) throw new IOException("Untrusted redirect"); continue;
            }
            if(response.StatusCode==HttpStatusCode.RequestedRangeNotSatisfiable && offset>0) { offset=0;continue; }
            if(response.Content.Headers.ContentEncoding.Any(value=>!value.Equals("identity",StringComparison.OrdinalIgnoreCase))) throw new IOException("Encoded update download");
            if(response.StatusCode==HttpStatusCode.PartialContent) {
                var range=response.Content.Headers.ContentRange;
                if(offset==0 || range is null || !range.Unit.Equals("bytes",StringComparison.OrdinalIgnoreCase) || range.From!=offset || range.To!=asset.Size-1 || range.Length!=asset.Size) throw new IOException("Invalid resumed download range");
            } else if(response.StatusCode==HttpStatusCode.OK) {
                offset=0;
            } else throw new IOException("Update download unavailable");
            if(response.Content.Headers.ContentLength>asset.Size-offset) throw new IOException("Oversized update download");
            await using var input=await response.Content.ReadAsStreamAsync(cancel);
            await using var output=new FileStream(destination,FileMode.OpenOrCreate,FileAccess.Write,FileShare.None,65536,true);
            if(offset==0) output.SetLength(0);
            else if(output.Length!=offset) throw new IOException("Download file changed during request");
            output.Position=offset;
            progress(offset);
            var buffer=new byte[65536]; long total=offset; int count;
            while((count=await input.ReadAsync(buffer,cancel))>0) { total+=count; if(total>asset.Size) throw new IOException("Oversized update download"); await output.WriteAsync(buffer.AsMemory(0,count),cancel); progress(total); }
            if(total!=asset.Size) throw new IOException("Incomplete update download"); return;
        }
        throw new IOException("Too many update redirects");
    }

    public void Dispose()=>client.Dispose();
}
