using System.Text.Json;
namespace QuotaBar.Core;

/// Uses atomic rename normally; preserves the last snapshot when Windows rejects rename with ERROR_INVALID_HANDLE.
internal sealed class ReminderFileCommit(string path,Func<string,bool> valid,Action<string,string,bool> moveFile,Action<string,string,bool> copyFile) {
 bool recoveryRequired;
 public void Commit(string temp) {
  if(recoveryRequired) throw new IOException("Reminder state recovery required; the previous backup was retained.");
  try { moveFile(temp,path,true); return; }
  catch(IOException error) when((error.HResult&0xffff)==6) { }
  var backup=path+".backup"; var hadPrevious=File.Exists(path);
  if(File.Exists(backup)) {
   try {
    if(!hadPrevious||!valid(File.ReadAllText(path))) throw new JsonException("Invalid reminder state");
   } catch(JsonException error) {
    recoveryRequired=true;
    throw new IOException("Reminder state recovery required; the previous backup was retained.",error);
   }
  }
  if(hadPrevious) copyFile(path,backup,true);
  try { copyFile(temp,path,true); }
  catch(Exception writeError) when(writeError is IOException or UnauthorizedAccessException) {
   try { if(hadPrevious) copyFile(backup,path,true); else File.Delete(path); }
   catch(Exception restoreError) when(restoreError is IOException or UnauthorizedAccessException) {
    recoveryRequired=true;
    throw new IOException("Reminder state write and restore failed; the previous backup was retained.",new AggregateException(writeError,restoreError));
   }
   throw;
  }
 }
}
