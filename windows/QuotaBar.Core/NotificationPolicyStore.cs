using System.Text.Json;
namespace QuotaBar.Core;
public sealed class NotificationPolicyStore {
 readonly string path;
 readonly ReminderFileCommit commit;
 public NotificationPolicyStore(string path):this(path,File.Move) { }
 internal NotificationPolicyStore(string path,Action<string,string,bool> moveFile,Action<string,string,bool>? copyFile=null) {
  this.path=path; commit=new(path,json=>!NotificationPolicyPreferences.Decode(json).RecoveredInvalidData,moveFile,copyFile??File.Copy);
 }
 public bool Corrupted { get; private set; }
 public NotificationPolicyPreferences LoadOrMigrate(LegacyNotificationPreferences? legacy) {
  if(File.Exists(path)) {
   var json=File.ReadAllText(path);
   var value=NotificationPolicyPreferences.Decode(json);
   Corrupted=value.RecoveredInvalidData;
   return value;
  }
  var migrated=legacy is null?NotificationPolicyPreferences.AllSelected():NotificationPolicyMigration.Migrate(legacy); Save(migrated); return migrated;
 }
 public void Save(NotificationPolicyPreferences value) {
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
  var temp=path+"."+Guid.NewGuid()+".tmp";
  try { File.WriteAllText(temp,JsonSerializer.Serialize(value,NotificationPolicyPreferences.JsonOptions)); commit.Commit(temp); Corrupted=false; }
  finally { if(File.Exists(temp)) File.Delete(temp); }
 }
}
