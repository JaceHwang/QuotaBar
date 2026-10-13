using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace QuotaBar.Core;
public sealed record UpdateRelease(string Version,string MinOS,Uri ReleaseNotesURL);
public static class UpdateFeed {
    public static readonly Uri Endpoint=new("https://jacehwang.github.io/codex-usage-sidebar/updates.json");
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
            var parsed=ParseVersion(version); var link=e.GetProperty("releaseNotesURL").GetString();
            if(link!=$"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v{version}") throw new FormatException("Unsafe release URL");
            return ParseVersion(current)<parsed && ParseVersion(os,true)>=ParseVersion(minimum,true)?new(version,minimum,new Uri(link)):null;
        } catch(Exception e) when(e is JsonException or KeyNotFoundException or InvalidOperationException or ArgumentException or OverflowException) { throw new FormatException("Invalid update feed",e); }
    }
}
public sealed record UpdateReminderPolicy {
    public string? NotifiedVersion { get; init; }
    public string? SkippedVersion { get; init; }
    public DateTimeOffset? SnoozeUntil { get; init; }
    public bool ShouldNotify(string version,DateTimeOffset now)=>version!=SkippedVersion && (SnoozeUntil is { } until?now>=until:version!=NotifiedVersion);
}
