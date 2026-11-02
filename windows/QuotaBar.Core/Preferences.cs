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
    public double FloatingBackgroundTransparency { get; init; }=20;
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
        FloatingBackgroundTransparency=double.IsFinite(FloatingBackgroundTransparency)?Math.Clamp(FloatingBackgroundTransparency,0,100):20,
        DetailHeight=double.IsFinite(DetailHeight)?Math.Max(220,DetailHeight):580,
        Theme=new[]{"system","light","dark"}.Contains(Theme)?Theme:"system",
        Language=new[]{"system","zh-CN","zh-TW","en"}.Contains(Language)?Language:"system"
    };
}
public sealed class PreferencesStore {
    readonly Action<string,string,bool> moveFile,copyFile;
    bool recoveryRequired;
    public string Path { get; }
    public PreferencesStore(string path):this(path,File.Move,File.Copy) { }
    internal PreferencesStore(string path,Action<string,string,bool> moveFile,Action<string,string,bool>? copyFile=null) { Path=path;this.moveFile=moveFile;this.copyFile=copyFile??File.Copy; }
    public Preferences Load() {
        try { var p=JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path)); return p?.Schema==1 ? p.Validated() : new(); }
        catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
    public void Save(Preferences preferences) {
        if(recoveryRequired) throw new IOException("Preferences recovery required; the previous settings backup was retained.");
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
        var temp=Path+"."+Guid.NewGuid()+".tmp";
        try { File.WriteAllText(temp,JsonSerializer.Serialize(preferences.Validated(),new JsonSerializerOptions { WriteIndented=true })); Commit(temp); }
        finally { if(File.Exists(temp)) File.Delete(temp); }
    }
    void Commit(string temp) {
        try { moveFile(temp,Path,true);return; }
        catch(IOException error) when(error.HResult==unchecked((int)0x80070006)) { }
        var backup=Path+".backup";var hadPrevious=File.Exists(Path);
        // A failed compatibility write must never replace the only valid backup.
        if(File.Exists(backup)) {
            try {
                if(!hadPrevious || JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path)) is not { Schema:1 }) throw new JsonException("Invalid preferences");
            } catch(JsonException error) { recoveryRequired=true;throw new IOException("Preferences recovery required; the previous settings backup was retained.",error); }
        }
        if(hadPrevious) copyFile(Path,backup,true);
        try { copyFile(temp,Path,true); }
        catch(Exception writeError) when(writeError is IOException or UnauthorizedAccessException) {
            try { if(hadPrevious) copyFile(backup,Path,true);else File.Delete(Path); }
            catch(Exception restoreError) when(restoreError is IOException or UnauthorizedAccessException) {
                recoveryRequired=true;
                throw new IOException("Preferences write and restore failed; the previous settings backup was retained.",new AggregateException(writeError,restoreError));
            }
            throw;
        }
    }
}
