using System.IO.Compression;

namespace QuotaBar.Core;
public static class UpdateStaging {
    public static void RequireUpdateProtocol(byte[] proof) {
        try { using var json=System.Text.Json.JsonDocument.Parse(proof); if(!json.RootElement.TryGetProperty("updateProtocol",out var value) || value.GetInt32()!=1) throw new IOException("Package does not support this updater protocol"); }
        catch(Exception e) when(e is System.Text.Json.JsonException or InvalidOperationException or FormatException) { throw new IOException("Invalid update protocol",e); }
    }
    public static string VerifyStaged(DownloadedUpdate download,string staged,string verificationDirectory) {
        UpdateDownloadClient.VerifyFile(download.Archive,download.Release.Package).GetAwaiter().GetResult();
        UpdateDownloadClient.VerifyFile(download.Provenance,download.Release.Provenance).GetAwaiter().GetResult();
        PackageVerifier.Verify(staged);
        var trusted=VerifyPackage(download,verificationDirectory);
        if(!File.ReadAllBytes(Path.Combine(staged,"package.json")).SequenceEqual(File.ReadAllBytes(Path.Combine(trusted,"package.json")))) throw new IOException("Prepared payload differs from trusted archive");
        return trusted;
    }
    public const long MaxExpandedBytes=2L*1024*1024*1024;
    public static void RequireSpace(long expandedBytes,long availableBytes) {
        if(expandedBytes<0 || expandedBytes>MaxExpandedBytes || availableBytes<expandedBytes*2+64L*1024*1024) throw new IOException("Insufficient update space");
    }
    static void ValidateName(ZipArchiveEntry entry) {
        var name=entry.FullName;
        if(name.Length>4096 || name.Contains('\\') || name.StartsWith('/') || (entry.ExternalAttributes&0x400)!=0 || ((entry.ExternalAttributes>>16)&0xF000)==0xA000) throw new IOException("Unsafe ZIP entry");
        var parts=name.TrimEnd('/').Split('/');
        if(parts.Length==0 || parts[0]!="QuotaBar") throw new IOException("Unexpected update root");
        foreach(var part in parts) {
            if(part.Length==0 || part is "." or ".." || part.EndsWith('.') || part.EndsWith(' ') || part.Any(c=>c<32 || "<>:\"|?*".Contains(c))) throw new IOException("Unsafe ZIP path");
            var stem=part.Split('.')[0].ToUpperInvariant();
            if(new[]{"CON","PRN","AUX","NUL"}.Contains(stem) || (stem.Length==4 && (stem.StartsWith("COM",StringComparison.Ordinal)||stem.StartsWith("LPT",StringComparison.Ordinal)) && stem[3] is >= '0' and <= '9')) throw new IOException("Reserved ZIP name");
        }
        if(name.EndsWith('/') && entry.Length!=0) throw new IOException("Invalid ZIP directory");
    }
    public static string ExtractArchive(string archive,string destination,CancellationToken cancel=default) {
        if(Directory.Exists(destination)||File.Exists(destination)) throw new IOException("Staging destination exists");
        using var zip=ZipFile.OpenRead(archive);
        if(zip.Entries.Count>20000) throw new IOException("Too many ZIP entries");
        var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase); long expanded=0;
        foreach(var entry in zip.Entries) {
            ValidateName(entry); if(!names.Add(entry.FullName.TrimEnd('/'))) throw new IOException("Duplicate ZIP path");
            if(entry.Length<0 || entry.Length>MaxExpandedBytes-expanded) throw new IOException("Oversized ZIP"); expanded+=entry.Length;
        }
        var parent=Path.GetDirectoryName(Path.GetFullPath(destination))!;
        PackageVerifier.RejectLinks(parent);
        RequireSpace(expanded,new DriveInfo(Path.GetPathRoot(parent)!).AvailableFreeSpace);
        Directory.CreateDirectory(destination);
        try {
            var buffer=new byte[65536];
            foreach(var entry in zip.Entries) {
                cancel.ThrowIfCancellationRequested(); var path=Path.GetFullPath(Path.Combine(destination,entry.FullName)); PackageVerifier.EnsureInside(destination,path);
                if(entry.FullName.EndsWith('/')) { Directory.CreateDirectory(path); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                using var input=entry.Open(); using var output=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None); long written=0; int count;
                while((count=input.Read(buffer))>0) { cancel.ThrowIfCancellationRequested(); written+=count; if(written>entry.Length) throw new IOException("Invalid expanded entry"); output.Write(buffer,0,count); }
                if(written!=entry.Length) throw new IOException("Incomplete ZIP entry");
            }
            PackageVerifier.RejectLinks(destination); return Path.Combine(destination,"QuotaBar");
        } catch { Directory.Delete(destination,true); throw; }
    }
    public static string VerifyPackage(DownloadedUpdate download,string destination,CancellationToken cancel=default) {
        RequireUpdateProtocol(File.ReadAllBytes(download.Provenance));
        var package=ExtractArchive(download.Archive,destination,cancel); var manifest=PackageVerifier.Verify(package);
        if(manifest.Version!=download.Release.Version || !File.ReadAllBytes(Path.Combine(package,"PROVENANCE.json")).SequenceEqual(File.ReadAllBytes(download.Provenance))) throw new IOException("Staged package version or provenance mismatch");
        return package;
    }
}
