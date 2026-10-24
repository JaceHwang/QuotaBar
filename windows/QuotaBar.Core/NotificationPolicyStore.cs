using System.Text.Json;
namespace QuotaBar.Core;
public sealed class NotificationPolicyStore(string path) {
 public bool Corrupted { get; private set; }
 public NotificationPolicyPreferences LoadOrMigrate(LegacyNotificationPreferences legacy) {
  if(File.Exists(path)) {
   var json=File.ReadAllText(path);
   var value=NotificationPolicyPreferences.Decode(json);
   Corrupted=value.RecoveredInvalidData;
   return value;
  }
  var migrated=NotificationPolicyMigration.Migrate(legacy); Save(migrated); return migrated;
 }
 public void Save(NotificationPolicyPreferences value) {
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
  var temp=path+"."+Guid.NewGuid()+".tmp";
  try { File.WriteAllText(temp,JsonSerializer.Serialize(value,NotificationPolicyPreferences.JsonOptions)); File.Move(temp,path,true); Corrupted=false; }
  finally { if(File.Exists(temp)) File.Delete(temp); }
 }
}
