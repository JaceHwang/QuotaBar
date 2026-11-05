using System.Text.Json;

namespace QuotaBar.Core;
public sealed class UpdateChannelStore(string path) {
    bool Read() {
        var info=new FileInfo(path);
        if(info.Length>65536 || (info.Attributes&FileAttributes.ReparsePoint)!=0) throw new FormatException("Invalid channel preference");
        using var json=JsonDocument.Parse(File.ReadAllBytes(path)); var root=json.RootElement;
        if(root.ValueKind!=JsonValueKind.Object || root.EnumerateObject().Count()!=2 || root.EnumerateObject().Count(p=>p.Name is "schema" or "betaEnabled")!=2 ||
           !root.TryGetProperty("schema",out var schema) || schema.ValueKind!=JsonValueKind.Number || !schema.TryGetInt32(out var n) || n!=1 ||
           !root.TryGetProperty("betaEnabled",out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new FormatException("Invalid channel preference");
        return value.GetBoolean();
    }
    void Quarantine()=>File.Move(path,path+".corrupt-"+Guid.NewGuid().ToString("N"));
    public bool Load() {
        if(!File.Exists(path)) return false;
        try { return Read(); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException or FormatException) {
            try { Quarantine(); } catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) { }
            return false;
        }
    }
    public void Save(bool enabled) {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        if(File.Exists(path)) {
            try { _=Read(); }
            catch(Exception e) when(e is JsonException or FormatException) { Quarantine(); }
        }
        var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try { File.WriteAllText(temp,JsonSerializer.Serialize(new { schema=1,betaEnabled=enabled })); File.Move(temp,path,true); }
        finally { if(File.Exists(temp)) File.Delete(temp); }
    }
}
