using System.Text;
using System.Text.RegularExpressions;

namespace QuotaBar.Core;
/// <summary>Narrow migration of the known legacy registration; never imports account data.</summary>
public sealed class LegacyPluginFlag(string path) {
    static readonly Regex Section=new(@"(?m)^\s*\[plugins\.""codex-usage-sidebar@codex-usage-sidebar""\][^\r\n]*\r?\n(?:(?![ \t]*\[).*(?:\r?\n|$))*",RegexOptions.CultureInvariant);
    static readonly Regex Flag=new(@"(?m)^(\s*enabled\s*=\s*)(true|false)\b",RegexOptions.CultureInvariant);
    public bool? Read()=>Change(null);
    public void Set(bool enabled)=>Change(enabled);
    bool? Change(bool? enabled) {
        if(!File.Exists(path)) return null;
        var content=File.ReadAllText(path); var section=Section.Match(content);
        if(!section.Success) return null;
        var flag=Flag.Match(section.Value);
        if(!flag.Success) throw new IOException("Legacy plugin registration has no explicit enabled flag; configuration unchanged");
        var old=flag.Groups[2].Value=="true";
        if(enabled is null || enabled==old) return old;
        var start=section.Index+flag.Groups[2].Index; var end=start+flag.Groups[2].Length;
        var replacement=content[..start]+(enabled.Value?"true":"false")+content[end..];
        var temporary=path+".quotabar-"+Guid.NewGuid()+".tmp";
        try {
            using(var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { var bytes=new UTF8Encoding(false).GetBytes(replacement); stream.Write(bytes); stream.Flush(true); }
            if(!OperatingSystem.IsWindows()) File.SetUnixFileMode(temporary,File.GetUnixFileMode(path));
            File.Replace(temporary,path,null);
        } finally { if(File.Exists(temporary)) File.Delete(temporary); }
        return old;
    }
}
public sealed record LegacyState(bool? PluginEnabled,bool WasRunning,IReadOnlyList<string> StartupKeys);
