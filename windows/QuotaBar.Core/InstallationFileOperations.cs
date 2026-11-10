using System.Security.Cryptography;
using System.Text.Json;

namespace QuotaBar.Core;

internal sealed class InstallationFileOperations {
    internal sealed record CopyMove(string Source,string Destination,Dictionary<string,string> Files);
    readonly Action<string,string> moveDirectory;
    readonly Action<string,string,bool> copyFile;
    readonly Action<string,bool> deleteDirectory;

    internal InstallationFileOperations(Action<string,string>? moveDirectory=null,Action<string,string,bool>? copyFile=null,Action<string,bool>? deleteDirectory=null) {
        this.moveDirectory=moveDirectory??Directory.Move;
        this.copyFile=copyFile??File.Copy;
        this.deleteDirectory=deleteDirectory??Directory.Delete;
    }

    internal void MoveDirectory(string source,string destination,string target,string store) {
        try { moveDirectory(source,destination);return; }
        catch(IOException error) when(error.HResult==unchecked((int)0x80070006)) { }
        ValidatePaths(source,destination,target,store);
        if(Directory.Exists(destination) || File.Exists(destination)) throw new IOException("Copy destination already exists");
        PackageVerifier.RejectLinks(source);
        var inventory=Directory.GetFiles(source,"*",SearchOption.AllDirectories)
            .ToDictionary(path=>Path.GetRelativePath(source,path).Replace('\\','/'),Hash);
        var operation=new CopyMove(source,destination,inventory);
        var journal=Path.Combine(store,"copy-move.json");
        if(InstallationState.Exists(journal)) throw new IOException("A directory copy still requires recovery");
        File.Delete(journal+".complete");
        InstallationState.Write(journal,operation);
        Copy(source,destination);
        Verify(operation);
        // The source may be removed only after the complete destination is durable.
        using(var complete=new FileStream(journal+".complete",FileMode.CreateNew,FileAccess.Write,FileShare.None)) { complete.Flush(true); }
        Finish(operation,journal);
    }

    internal bool RecoveryPending(string store)=>InstallationState.Exists(Path.Combine(store,"copy-move.json"));

    internal void Recover(string target,string store) {
        var journal=Path.Combine(store,"copy-move.json");
        if(!InstallationState.Exists(journal)) return;
        var operation=InstallationState.Read<CopyMove>(journal)??throw new IOException("Unreadable copy recovery record");
        ValidatePaths(operation.Source,operation.Destination,target,store);
        if(File.Exists(journal+".complete")) {
            // Verification also protects the only remaining copy after interrupted source cleanup.
            Verify(operation);
            Finish(operation,journal);
            return;
        }
        if(!Directory.Exists(operation.Source)) throw new IOException("Incomplete copy lost its source; recovery record retained");
        PackageVerifier.RejectLinks(operation.Source);
        if(Directory.Exists(operation.Destination)) {
            PackageVerifier.RejectLinks(operation.Destination);
            deleteDirectory(operation.Destination,true);
        }
        InstallationState.Delete(journal);
    }

    void Finish(CopyMove operation,string journal) {
        if(Directory.Exists(operation.Source)) {
            PackageVerifier.RejectLinks(operation.Source);
            deleteDirectory(operation.Source,true);
        }
        // An orphan completion marker is discarded before the next copy begins.
        InstallationState.Delete(journal);
        File.Delete(journal+".complete");
    }

    void Copy(string source,string destination) {
        Directory.CreateDirectory(destination);
        foreach(var file in Directory.GetFiles(source)) {
            var output=Path.Combine(destination,Path.GetFileName(file));
            copyFile(file,output,false);
            using var durable=new FileStream(output,FileMode.Open,FileAccess.Write,FileShare.Read);
            durable.Flush(true);
        }
        foreach(var directory in Directory.GetDirectories(source)) Copy(directory,Path.Combine(destination,Path.GetFileName(directory)));
    }

    static void Verify(CopyMove operation) {
        PackageVerifier.RejectLinks(operation.Destination);
        if(Directory.GetFiles(operation.Destination,"*",SearchOption.AllDirectories).Length!=operation.Files.Count) throw new IOException("Directory copy file count mismatch");
        foreach(var (relative,expected) in operation.Files) {
            var path=Path.GetFullPath(Path.Combine(operation.Destination,relative));
            PackageVerifier.EnsureInside(operation.Destination,path);
            if(Hash(path)!=expected) throw new IOException("Directory copy checksum mismatch: "+relative);
        }
    }

    static string Hash(string path) {
        using var input=File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant();
    }

    static void ValidatePaths(string source,string destination,string target,string store) {
        if(source==destination || (source!=target && destination!=target)) throw new IOException("Unexpected directory copy paths");
        var managed=source==target?destination:source;
        if(Path.GetDirectoryName(managed)!=store || !new[]{"stage-","backup-","failed-"}.Any(prefix=>Path.GetFileName(managed).StartsWith(prefix,StringComparison.Ordinal))) throw new IOException("Directory copy outside installation store");
        if((File.GetAttributes(store)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked installation store");
        if(Directory.Exists(target) && (File.GetAttributes(target)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked installation target");
    }
}

internal static class InstallationState {
    internal static bool Exists(string path)=>File.Exists(path) || File.Exists(path+".tmp");

    internal static T? Read<T>(string path) {
        var temporary=path+".tmp";
        // A flushed temporary record remains authoritative if compatibility copying
        // was interrupted while writing the final journal.
        if(File.Exists(temporary)) {
            try { return JsonSerializer.Deserialize<T>(File.ReadAllText(temporary)); }
            catch(JsonException) when(File.Exists(path)) { }
        }
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path));
    }

    internal static void Write<T>(string path,T value,Action<string,string,bool>? moveFile=null,Action<string,string,bool>? copyFile=null) {
        var temporary=path+".tmp";
        using(var output=new FileStream(temporary,FileMode.Create,FileAccess.Write,FileShare.None)) {
            JsonSerializer.Serialize(output,value);
            output.Flush(true);
        }
        Commit(temporary,path,moveFile,copyFile);
    }

    internal static void Commit(string temporary,string path,Action<string,string,bool>? moveFile=null,Action<string,string,bool>? copyFile=null) {
        try { (moveFile??File.Move)(temporary,path,true); }
        catch(IOException error) when(error.HResult==unchecked((int)0x80070006)) {
            (copyFile??File.Copy)(temporary,path,true);
            using(var output=new FileStream(path,FileMode.Open,FileAccess.Write,FileShare.Read)) { output.Flush(true); }
            File.Delete(temporary);
        }
    }

    internal static void Delete(string path) {
        File.Delete(path);
        File.Delete(path+".tmp");
    }
}
