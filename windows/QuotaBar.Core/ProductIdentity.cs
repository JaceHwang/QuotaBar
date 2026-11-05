using System.Text;
using System.Text.Json;
namespace QuotaBar.Core;
public sealed record ProductIdentity(string Version,bool Development) {
    public static ProductIdentity Resolve(string numeric,string? full,string provenance) {
        try {
            if(Encoding.UTF8.GetByteCount(provenance)>1048576 || ProductVersion.Parse(numeric).IsBeta) throw new FormatException("Invalid identity");
            using var doc=JsonDocument.Parse(provenance); var root=doc.RootElement;
            var kind=root.GetProperty("kind").GetString(); var version=full??numeric; var parsed=ProductVersion.Parse(version);
            if(parsed.NumericVersion!=numeric) throw new FormatException("Invalid identity");
            var proofVersion=root.TryGetProperty("version",out var v) && v.ValueKind!=JsonValueKind.Null?v.GetString():null;
            var tag=root.TryGetProperty("releaseTag",out var t) && t.ValueKind!=JsonValueKind.Null?t.GetString():null;
            if(kind=="release") {
                if(!root.TryGetProperty("workingTreeDirty",out var dirty) || dirty.GetBoolean() || proofVersion!=version || tag!="v"+version || !root.TryGetProperty("sourceCommit",out var source) || !TrustedUpdateRelease.Hex(source.GetString()??"",40) || (full is null && parsed.IsBeta)) throw new FormatException("Invalid identity");
                return new(version,false);
            }
            if(kind=="local-development-candidate" && tag is null && (full is not null || proofVersion is not null) && (proofVersion is null || proofVersion==version) && (!parsed.IsBeta || (full is not null && proofVersion==version))) return new(version,true);
            throw new FormatException("Invalid identity");
        } catch(Exception e) when(e is JsonException or KeyNotFoundException or InvalidOperationException or ArgumentException or NullReferenceException) { throw new FormatException("Invalid identity",e); }
    }
}
