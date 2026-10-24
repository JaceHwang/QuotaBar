using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace QuotaBar.Core;
public sealed record UpdateAsset(string Name,Uri Url,long Size,string Sha256);
public sealed record TrustedUpdateRelease(string Version,string Platform,string SourceCommit,UpdateAsset Package,UpdateAsset Provenance) {
    public const string Repository="JaceHwang/QuotaBar";
    public const long MaxDownloadBytes=512L*1024*1024;
    public static Uri ApiUrl(string version) { UpdateFeed.ParseVersion(version); return new($"https://api.github.com/repos/{Repository}/releases/tags/v{version}"); }
    public static Uri TagUrl(string version) { UpdateFeed.ParseVersion(version); return new($"https://api.github.com/repos/{Repository}/git/ref/tags/v{version}"); }
    public static bool AllowedDownloadRedirect(Uri url)=>url.IsAbsoluteUri && url.Scheme=="https" && url.UserInfo.Length==0 && url.IsDefaultPort && url.Fragment.Length==0 && new[]{"github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"}.Contains(url.Host);
    public static bool Hex(string value,int count)=>value.Length==count && value.All(c=>c is >= '0' and <= '9' or >= 'a' and <= 'f');
    public static TrustedUpdateRelease Parse(string releaseJSON,string tagJSON,string version,string platform,string currentVersion) {
        try {
            if(Encoding.UTF8.GetByteCount(releaseJSON)>2*1024*1024 || Encoding.UTF8.GetByteCount(tagJSON)>1024*1024 || UpdateFeed.ParseVersion(currentVersion)>=UpdateFeed.ParseVersion(version)) throw new FormatException("Invalid update version");
            using var release=JsonDocument.Parse(releaseJSON); using var tag=JsonDocument.Parse(tagJSON); var r=release.RootElement; var obj=tag.RootElement.GetProperty("object"); var commit=obj.GetProperty("sha").GetString()!;
            if(r.GetProperty("tag_name").GetString()!="v"+version || r.GetProperty("draft").GetBoolean() || r.GetProperty("prerelease").GetBoolean() || r.GetProperty("html_url").GetString()!=$"https://github.com/{Repository}/releases/tag/v{version}" || obj.GetProperty("type").GetString()!="commit" || !Hex(commit,40)) throw new FormatException("Untrusted release");
            var assets=r.GetProperty("assets").EnumerateArray().ToArray();
            if(assets.Length>1000 || assets.Select(a=>a.GetProperty("name").GetString()).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=assets.Length) throw new FormatException("Duplicate release asset");
            var names=platform switch { "macos-arm64"=>($"codex-quota-v{version}-macos-arm64.dmg","CODEX-QUOTA-PROVENANCE.json"),"windows-x64"=>($"QuotaBar-{version}-windows-x64.zip","QUOTABAR-WINDOWS-PROVENANCE.json"),_=>throw new FormatException("Unsupported platform") };
            UpdateAsset Select(string name,long limit) {
                var a=assets.SingleOrDefault(a=>a.GetProperty("name").GetString()==name);
                if(a.ValueKind==JsonValueKind.Undefined) throw new FormatException("Missing release asset");
                var size=a.GetProperty("size").GetInt64(); var digest=a.GetProperty("digest").GetString(); var url=a.GetProperty("browser_download_url").GetString();
                if(a.GetProperty("state").GetString()!="uploaded" || size<=0 || size>limit || digest is null || !digest.StartsWith("sha256:",StringComparison.Ordinal) || !Hex(digest[7..],64) || url!=$"https://github.com/{Repository}/releases/download/v{version}/{name}") throw new FormatException("Untrusted asset");
                return new(name,new Uri(url),size,digest[7..]);
            }
            return new(version,platform,commit,Select(names.Item1,MaxDownloadBytes),Select(names.Item2,1024*1024));
        } catch(Exception e) when(e is JsonException or KeyNotFoundException or InvalidOperationException or ArgumentException or OverflowException or NullReferenceException) { throw new FormatException("Invalid release metadata",e); }
    }
}
public enum ApplicationUpdatePhase { Idle,Resolving,Downloading,Verifying,Preparing,HandingOff,Installing,Succeeded,RolledBack,Failed,Cancelled }
public sealed record ApplicationUpdateProgress(ApplicationUpdatePhase Phase,long Received=0,long Total=0,string? Failure=null) {
    public bool CanCancel=>Phase is ApplicationUpdatePhase.Resolving or ApplicationUpdatePhase.Downloading or ApplicationUpdatePhase.Verifying or ApplicationUpdatePhase.Preparing;
    public bool Busy=>CanCancel || Phase is ApplicationUpdatePhase.HandingOff or ApplicationUpdatePhase.Installing;
}
