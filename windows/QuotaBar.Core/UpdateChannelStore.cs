using System.Text.Json;

namespace QuotaBar.Core;
public sealed class UpdateChannelStore {
    readonly string path;
    readonly Action<string,string,bool> moveFile,copyFile;
    bool recoveryRequired;
    public UpdateChannelStore(string path):this(path,File.Move,File.Copy) { }
    internal UpdateChannelStore(string path,Action<string,string,bool> moveFile,Action<string,string,bool>? copyFile=null) {
        this.path=path;this.moveFile=moveFile;this.copyFile=copyFile??File.Copy;
    }
    bool Read() {
        var info=new FileInfo(path);
        if(info.Length>65536 || (info.Attributes&FileAttributes.ReparsePoint)!=0) throw new FormatException("Invalid channel preference");
        using var json=JsonDocument.Parse(File.ReadAllBytes(path)); var root=json.RootElement;
        if(root.ValueKind!=JsonValueKind.Object || root.EnumerateObject().Count()!=2 || root.EnumerateObject().Count(p=>p.Name is "schema" or "betaEnabled")!=2 ||
           !root.TryGetProperty("schema",out var schema) || schema.ValueKind!=JsonValueKind.Number || !schema.TryGetInt32(out var n) || n!=1 ||
           !root.TryGetProperty("betaEnabled",out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new FormatException("Invalid channel preference");
        return value.GetBoolean();
    }
    void Quarantine() {
        var quarantine=path+".corrupt-"+Guid.NewGuid().ToString("N");
        try { moveFile(path,quarantine,false); }
        catch(IOException error) when(error.HResult==unchecked((int)0x80070006)) {
            if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw;
            copyFile(path,quarantine,false);
            File.Delete(path);
        }
    }
    public bool Load() {
        if(recoveryRequired || File.Exists(path+".recovery-required")) return false;
        if(!File.Exists(path)) return false;
        try { return Read(); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException or FormatException) {
            // Keep a failed restore and its backup together for explicit recovery.
            if(File.Exists(path+".backup")) return false;
            try { Quarantine(); } catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) { }
            return false;
        }
    }
    public void Save(bool enabled) {
        ProtectRecoveryBackup();
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        if(File.Exists(path)) {
            try { _=Read(); }
            catch(Exception e) when(e is JsonException or FormatException) { Quarantine(); }
        }
        var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try { File.WriteAllText(temp,JsonSerializer.Serialize(new { schema=1,betaEnabled=enabled })); Commit(temp); }
        finally { if(File.Exists(temp)) File.Delete(temp); }
    }
    void ProtectRecoveryBackup() {
        if(recoveryRequired || File.Exists(path+".recovery-required")) throw new IOException("Channel preference recovery required; the previous settings backup was retained.");
        if(!File.Exists(path+".backup")) return;
        try { _=Read(); }
        catch(Exception error) when(error is IOException or UnauthorizedAccessException or JsonException or FormatException) {
            throw new IOException("Channel preference recovery required; the previous settings backup was retained.",error);
        }
    }
    void Commit(string temp) {
        try { moveFile(temp,path,true);return; }
        catch(IOException error) when(error.HResult==unchecked((int)0x80070006)) { }
        var backup=path+".backup";
        var recoveryPath=path+".recovery-required";
        // A valid JSON file can still be the result of a failed copy/restore.
        // Record the pending transaction before touching the primary or backup.
        using(var marker=File.Open(recoveryPath,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
            marker.WriteByte(1);
            marker.Flush(true);
        }
        var hadPrevious=File.Exists(path);
        var retainRecoveryMarker=false;
        try {
            if(hadPrevious) copyFile(path,backup,true);
            try { copyFile(temp,path,true); }
            catch(Exception writeError) when(writeError is IOException or UnauthorizedAccessException) {
                try {
                    if(hadPrevious) copyFile(backup,path,true);
                    else File.Delete(path);
                }
                catch(Exception restoreError) when(restoreError is IOException or UnauthorizedAccessException) {
                    recoveryRequired=true;
                    retainRecoveryMarker=true;
                    throw new IOException("Channel preference write and restore failed; the previous settings backup was retained.",new AggregateException(writeError,restoreError));
                }
                throw;
            }
        } finally {
            if(!retainRecoveryMarker) File.Delete(recoveryPath);
        }
    }
}
