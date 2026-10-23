using System.Text.Json;

namespace QuotaBar.Core;
public sealed record Preferences {
    public int Schema { get; init; }=1;
    public BarkPreferences Bark { get; init; }=new();
    public NotificationPresentationPreferences Notifications { get; init; }=new();
    public QuotaExperiencePreferences Experience { get; init; }=new();
    public bool AutomaticUpdates { get; init; }=true;
    public bool UpdateReminders { get; init; }=false;
    public bool FloatingEnabled { get; init; }=true;
    public bool ShowsQuotaInformation { get; init; }=true;
    public double? FloatingX { get; init; }
    public double? FloatingY { get; init; }
    public double DetailHeight { get; init; }=580;
    public string Theme { get; init; }="system";
    public string Language { get; init; }="system";
    public Preferences Validated() => this with {
        Bark=(Bark??new()).Validated(),
        Experience=Experience??new(),
        Notifications=(Notifications??new()).Validated(),
        FloatingX=FloatingX is double x && double.IsFinite(x)?x:null,
        FloatingY=FloatingY is double y && double.IsFinite(y)?y:null,
        DetailHeight=double.IsFinite(DetailHeight)?Math.Max(220,DetailHeight):580,
        Theme=new[]{"system","light","dark"}.Contains(Theme)?Theme:"system",
        Language=new[]{"system","zh-CN","zh-TW","en"}.Contains(Language)?Language:"system"
    };
}
public sealed class PreferencesStore(string path) {
    public string Path { get; }=path;
    public Preferences Load() {
        try { var p=JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path)); return p?.Schema==1 ? p.Validated() : new(); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
    public void Save(Preferences preferences) {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
        var temp=Path+"."+Guid.NewGuid()+".tmp";
        try { File.WriteAllText(temp,JsonSerializer.Serialize(preferences.Validated(),new JsonSerializerOptions { WriteIndented=true })); File.Move(temp,Path,true); }
        finally { if(File.Exists(temp)) File.Delete(temp); }
    }
}
