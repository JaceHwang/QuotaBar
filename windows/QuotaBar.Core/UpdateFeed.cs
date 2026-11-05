using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace QuotaBar.Core;
public sealed record UpdateRelease(string Version,string MinOS,Uri ReleaseNotesURL,string? Summary=null,string? ReleaseNotes=null) {
    public string? NotificationSummary=>string.IsNullOrWhiteSpace(Summary)?null:Summary.Trim();
}
public static class UpdateFeed {
    public sealed record Selection(UpdateRelease? Release,bool BetaError);
    public static Selection Select(string json,string platform,string current,string os,bool allowBeta) {
        var stable=Available(json,platform,current,os); var installed=ProductVersion.Parse(current);
        if(!allowBeta) return new(stable,false);
        try {
            using var doc=JsonDocument.Parse(json); var root=doc.RootElement;
            if(!root.TryGetProperty("beta",out var beta)) return new(stable,false);
            if(beta.ValueKind!=JsonValueKind.Object) throw new FormatException("Invalid beta feed");
            if(!beta.TryGetProperty(platform,out var entry)) return new(stable,false);
            var version=entry.GetProperty("version").GetString()!; var parsed=ProductVersion.Parse(version);
            var minimum=entry.GetProperty("minOS").GetString()!; var link=entry.GetProperty("releaseNotesURL").GetString();
            if(!parsed.IsBeta || link is null || !new[]{"QuotaBar","codex-usage-sidebar"}.Any(repo=>link==$"https://github.com/JaceHwang/{repo}/releases/tag/v{version}")) throw new FormatException("Invalid beta release");
            var system=ParseVersion(os,true); var required=ParseVersion(minimum,true);
            var summary=Text(entry,"summary",240); var notes=Text(entry,"releaseNotes",16000);
            if(system<required || installed.CompareTo(parsed)>=0 || (stable is not null && ProductVersion.Parse(stable.Version).CompareTo(parsed)>=0)) return new(stable,false);
            return new(new UpdateRelease(version,minimum,new Uri(link),summary,notes),false);
        } catch(Exception e) when(e is JsonException or KeyNotFoundException or InvalidOperationException or ArgumentException or OverflowException or FormatException or NullReferenceException) { return new(stable,true); }
    }
    public static readonly Uri Endpoint=new("https://jacehwang.github.io/QuotaBar/updates.json");
    static string? Text(JsonElement entry,string key,int limit) {
        if(!entry.TryGetProperty(key,out var value) || value.ValueKind==JsonValueKind.Null) return null;
        var text=value.GetString()!;
        var result=string.Concat(text.EnumerateRunes().Take(limit));
        return result;
    }
    public static Version ParseVersion(string value,bool os=false) {
        if(!Regex.IsMatch(value,os?@"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$":@"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$") || !Version.TryParse(value,out var parsed)) throw new FormatException("Invalid version");
        return new Version(parsed.Major,parsed.Minor,Math.Max(0,parsed.Build));
    }
    public static UpdateRelease? Available(string json,string platform,string current,string os) {
        try {
            if(Encoding.UTF8.GetByteCount(json)>262144) throw new FormatException("Feed too large");
            using var doc=JsonDocument.Parse(json); var root=doc.RootElement;
            if(root.GetProperty("schemaVersion").GetInt32()!=1) throw new FormatException("Unsupported feed");
            var stable=root.GetProperty("stable");
            if(!stable.TryGetProperty(platform,out var e)) return null;
            var version=e.GetProperty("version").GetString()!; var minimum=e.GetProperty("minOS").GetString()!;
            var parsed=ProductVersion.Parse(version); if(parsed.IsBeta) throw new FormatException("Invalid stable version"); var link=e.GetProperty("releaseNotesURL").GetString();
            if(link is null || !new[]{"QuotaBar","codex-usage-sidebar"}.Any(repo=>link==$"https://github.com/JaceHwang/{repo}/releases/tag/v{version}")) throw new FormatException("Unsafe release URL");
            var installed=ProductVersion.Parse(current); var system=ParseVersion(os,true); var required=ParseVersion(minimum,true);
            var summary=Text(e,"summary",240); var notes=Text(e,"releaseNotes",16000);
            return installed.CompareTo(parsed)<0 && system>=required?new(version,minimum,new Uri(link),summary,notes):null;
        } catch(Exception e) when(e is JsonException or KeyNotFoundException or InvalidOperationException or ArgumentException or OverflowException) { throw new FormatException("Invalid update feed",e); }
    }
}
public sealed record UpdateReminderPolicy {
    public string? NotifiedVersion { get; init; }
    public string? SkippedVersion { get; init; }
    public DateTimeOffset? SnoozeUntil { get; init; }
    public bool ShouldNotify(string version,DateTimeOffset now)=>version!=SkippedVersion && (SnoozeUntil is { } until?now>=until:version!=NotifiedVersion);
}
