using QuotaBar.Core;

static class ReminderPersistenceTests {
 static void Check(bool condition,string message) { if(!condition) throw new Exception(message); }
 static void InvalidHandle(string source,string destination,bool overwrite)=>throw new IOException("injected invalid handle",unchecked((int)0x80070006));
 static void Fails(Action action) { try { action(); } catch(IOException) { return; } throw new Exception("Expected I/O failure"); }
 public static void Run() {
  var root=Path.Combine(Path.GetTempPath(),"reminder-persistence-"+Guid.NewGuid()); Directory.CreateDirectory(root);
  try {
   var policyPath=Path.Combine(root,"policy.json");
   var policy=new NotificationPolicyStore(policyPath,InvalidHandle);
   var initial=NotificationPolicyPreferences.AllSelected().WithLowThresholds([30,10]);
   policy.Save(initial); policy.Save(initial.ToggleColumn(NotificationChannel.Bubble));
   var loaded=new NotificationPolicyStore(policyPath).LoadOrMigrate(null);
   Check(loaded.ConfiguredLowThresholds.SequenceEqual([30,10])&&loaded.Rules[NotificationCategory.QuotaLow].Contains(NotificationChannel.Mobile)&&!loaded.Rules[NotificationCategory.QuotaLow].Contains(NotificationChannel.Bubble),"policy fallback persists column and unrelated thresholds across reload");
   Check(new NotificationPolicyStore(policyPath+".backup").LoadOrMigrate(null).Rules[NotificationCategory.QuotaLow].Contains(NotificationChannel.Bubble),"policy previous snapshot backed up");
   var saved=File.ReadAllBytes(policyPath);
   Fails(()=>new NotificationPolicyStore(policyPath,(_,_,_)=>throw new IOException("denied",unchecked((int)0x80070005))).Save(initial));
   Check(File.ReadAllBytes(policyPath).SequenceEqual(saved),"non-invalid-handle error preserves policy");
   var copies=0;
   var failing=new NotificationPolicyStore(policyPath,InvalidHandle,(source,destination,overwrite)=> { if(++copies==2) { File.WriteAllText(destination,"{broken");throw new IOException("partial write"); } File.Copy(source,destination,overwrite); });
   Fails(()=>failing.Save(initial)); Check(File.ReadAllBytes(policyPath).SequenceEqual(saved),"partial compatibility write restores policy");
   copies=0;
   var interrupted=new NotificationPolicyStore(policyPath,InvalidHandle,(source,destination,overwrite)=> { if(++copies==2) { File.WriteAllText(destination,"{broken");throw new IOException("partial write"); } if(copies==3) throw new IOException("restore failed"); File.Copy(source,destination,overwrite); });
   Fails(()=>interrupted.Save(initial)); var protectedBackup=File.ReadAllBytes(policyPath+".backup");
   Fails(()=>interrupted.Save(initial)); Fails(()=>new NotificationPolicyStore(policyPath,InvalidHandle).Save(initial));
   Check(File.ReadAllBytes(policyPath+".backup").SequenceEqual(protectedBackup)&&protectedBackup.SequenceEqual(saved),"failed restore retains good policy backup across restart");
   var experiencePath=Path.Combine(root,"experience.json"); var experience=new QuotaExperienceStore(experiencePath,InvalidHandle);
   experience.Save(new ExperienceState { Epoch="first" }); experience.Save(new ExperienceState { Epoch="second" });
   Check(new QuotaExperienceStore(experiencePath).Load().Epoch=="second"&&new QuotaExperienceStore(experiencePath+".backup").Load().Epoch=="first","experience fallback retains epoch and backup");
   var warningPath=Path.Combine(root,"warning.json"); var warning=new QuotaWarningStore(warningPath,InvalidHandle);
   warning.Save(new QuotaWarningState { Epoch="first" }); warning.Save(new QuotaWarningState { Epoch="second" });
   Check(new QuotaWarningStore(warningPath).Load().Epoch=="second"&&new QuotaWarningStore(warningPath+".backup").Load().Epoch=="first","warning fallback retains state and backup");
   var barkPath=Path.Combine(root,"bark.json"); var bark=new BarkDeliveryStore(barkPath,InvalidHandle); var now=DateTimeOffset.UtcNow; var id=new BarkEventIdentity("fixture");
   Check(bark.Reserve(id,now),"mobile receipt reserves when rename fails"); bark.MarkAccepted(id,now);
   Check(!bark.HasPersistenceError&&!new BarkDeliveryStore(barkPath).Reserve(id,now),"mobile receipt remains deduplicated after reload");
   var barkCopies=0;
   var interruptedBark=new BarkDeliveryStore(barkPath,InvalidHandle,(source,destination,overwrite)=> { if(++barkCopies==2) { File.WriteAllText(destination,"{broken"); throw new IOException("partial mobile receipt write"); } File.Copy(source,destination,overwrite); });
   Check(!interruptedBark.Reserve(new BarkEventIdentity("other"),now)&&interruptedBark.HasPersistenceError,"failed mobile receipt write fails closed");
   Check(!new BarkDeliveryStore(barkPath).Reserve(id,now),"mobile rollback preserves prior deduplication");
   Check(!Directory.EnumerateFiles(root,"*.tmp").Any(),"reminder temp files cleaned");
   Console.WriteLine("PASS reminder policy, experience and warning invalid-handle recovery");
  } finally { Directory.Delete(root,true); }
 }
}
