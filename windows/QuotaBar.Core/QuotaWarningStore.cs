using System.Text.Json;
namespace QuotaBar.Core;
public sealed class QuotaWarningStore(string path) {
 public QuotaWarningState Load() {
  if(!File.Exists(path)) return new();
  try {
   var state=JsonSerializer.Deserialize<QuotaWarningState>(File.ReadAllText(path));
   return state is { Schema:1,Periods.Count:<=2 }&&state.Periods.Values.All(p=>p is not null)?state:new();
  } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException) {
   try { File.Move(path,path+"."+Guid.NewGuid()+".corrupt"); } catch(IOException) { } catch(UnauthorizedAccessException) { }
   return new();
  }
 }
 public void Save(QuotaWarningState value) {
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!); var temp=path+"."+Guid.NewGuid()+".tmp";
  try { File.WriteAllText(temp,JsonSerializer.Serialize(value)); File.Move(temp,path,true); }
  finally { if(File.Exists(temp)) File.Delete(temp); }
 }
}
