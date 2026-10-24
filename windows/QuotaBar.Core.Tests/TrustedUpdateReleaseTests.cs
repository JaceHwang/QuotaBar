using System.Text.Json;
using QuotaBar.Core;
internal static class TrustedUpdateReleaseTests {
    public static void Run() {
        using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/in-app-updates/release-cases.json")));
        foreach(var row in doc.RootElement.EnumerateArray()) {
            var valid=row.GetProperty("valid").GetBoolean();
            try {
                var result=TrustedUpdateRelease.Parse(row.GetProperty("release").GetRawText(),row.GetProperty("tag").GetRawText(),row.GetProperty("version").GetString()!,row.GetProperty("platform").GetString()!,row.GetProperty("current").GetString()!);
                if(!valid||result.SourceCommit!=new string('b',40)||result.Package.Size!=1024) throw new Exception("Accepted invalid contract: "+row.GetProperty("name"));
            } catch(FormatException) { if(valid) throw new Exception("Rejected valid contract: "+row.GetProperty("name")); }
        }
        foreach(var url in new[]{"http://github.com/x","https://127.0.0.1/x","https://github.com.evil/x","https://github.com:444/x","https://user@github.com/x","https://github.com/x#x"})
            if(TrustedUpdateRelease.AllowedDownloadRedirect(new Uri(url))) throw new Exception("Unsafe redirect");
        if(!TrustedUpdateRelease.AllowedDownloadRedirect(new Uri("https://release-assets.githubusercontent.com/a?sig=example"))) throw new Exception("CDN redirect rejected");
        Console.WriteLine("PASS shared official release and redirect contracts");
    }
}
