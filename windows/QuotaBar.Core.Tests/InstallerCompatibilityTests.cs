using System.Security.Cryptography;
using System.Text.Json;
using QuotaBar.Core;

internal static class InstallerCompatibilityTests {
    public static void Run() {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-install-compat-"+Guid.NewGuid());
        Directory.CreateDirectory(root);
        try {
            var one=Candidate(root,"one");
            var two=Candidate(root,"two");
            var target=Path.Combine(root,"Programs","QuotaBar");
            var files=new InstallationFileOperations(moveDirectory:(_,_)=>throw InvalidHandle());
            var hooks=new InstallHooks(()=>{},()=>false,(_,_)=>{},()=>{});
            var installer=new TransactionInstaller(target,hooks,files);
            installer.Install(one);
            Check(Payload(target)=="one","invalid-handle first install copies package");
            installer.Install(two);
            Check(Payload(target)=="two","invalid-handle upgrade installs new package");
            Throws(()=>installer.Install(one,()=>throw new IOException("startup failed")));
            Check(Payload(target)=="two" && !installer.RecoveryPending,"health failure restores the previous package");
            installer.Rollback();
            Check(Payload(target)=="one","rollback history survives failed startup");
            installer.Uninstall();
            Check(!Directory.Exists(target),"compatibility uninstall removes active package");
            installer.Rollback();
            Check(Payload(target)=="one","uninstall backup can be restored");

            var failCopy=true;
            var failingFiles=new InstallationFileOperations(moveDirectory:(_,_)=>throw InvalidHandle(),copyFile:(source,destination,overwrite)=> {
                if(failCopy && source.StartsWith(target+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)) {
                    failCopy=false;
                    File.WriteAllText(destination,"partial copy");
                    throw new IOException("backup copy failed");
                }
                File.Copy(source,destination,overwrite);
            });
            var failedBackup=new TransactionInstaller(target,hooks,failingFiles);
            Throws(()=>failedBackup.Install(two));
            Check(Payload(target)=="one" && !failedBackup.RecoveryPending,"failed backup copy leaves old installation intact");
            failedBackup.Install(two);
            Check(Payload(target)=="two","retry after failed backup succeeds");

            var otherErrors=new TransactionInstaller(target,hooks,new InstallationFileOperations(moveDirectory:(_,_)=>throw new IOException("sharing violation",unchecked((int)0x80070020))));
            Throws(()=>otherErrors.Install(one));
            Check(Payload(target)=="two","unrelated rename errors propagate without replacing target");
            InterruptedMoves(root,one,hooks);
            CopyIntegrity(root);
            StateWrites(root);
            Console.WriteLine("PASS installer invalid-handle install, upgrade, health rollback, uninstall, failed backup and retry");
        } finally { Directory.Delete(root,true); }
    }

    static void StateWrites(string root) {
        var path=Path.Combine(root,"state.json");
        InstallationState.Write(path,new { Value="old" });
        InstallationState.Write(path,new { Value="new" },(_,_,_)=>throw InvalidHandle());
        Check(InstallationState.Read<Dictionary<string,string>>(path)!["Value"]=="new","invalid-handle state write commits new journal");
        Throws(()=>InstallationState.Write(path,new { Value="durable" },(_,_,_)=>throw InvalidHandle(),(_,destination,_)=> {
            File.WriteAllText(destination,"partial");
            throw new IOException("state copy failed");
        }));
        Check(InstallationState.Read<Dictionary<string,string>>(path)!["Value"]=="durable","flushed temporary journal survives partial state copy");
        if(OperatingSystem.IsWindows()) {
            using(var lockedFinal=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.None)) {
                Throws(()=>InstallationState.Delete(path));
                Check(File.Exists(path+".tmp"),"failed final journal deletion retains authoritative temporary record");
            }
            Check(InstallationState.Read<Dictionary<string,string>>(path)!["Value"]=="durable","recovery record is readable after interrupted journal cleanup");
        }
        InstallationState.Delete(path);
        Check(!InstallationState.Exists(path),"journal cleanup removes temporary recovery record");
        Console.WriteLine("PASS invalid-handle state writes and interrupted journal copy recovery");
    }

    static void CopyIntegrity(string root) {
        var target=Path.Combine(root,"CopyIntegrity","QuotaBar");
        var store=Path.Combine(root,"CopyIntegrity",".QuotaBar-install");
        Directory.CreateDirectory(target);
        Directory.CreateDirectory(store);
        File.WriteAllText(Path.Combine(target,"keep"),"original");
        var destination=Path.Combine(store,"backup-integrity");
        var corrupt=new InstallationFileOperations(moveDirectory:(_,_)=>throw InvalidHandle(),copyFile:(_,output,_)=>File.WriteAllText(output,"corrupt"));
        Throws(()=>corrupt.MoveDirectory(target,destination,target,store));
        Check(File.ReadAllText(Path.Combine(target,"keep"))=="original","checksum failure preserves complete source");
        corrupt.Recover(target,store);
        Check(!Directory.Exists(destination),"checksum failure discards unverified copy");

        var interruptedDelete=new InstallationFileOperations(moveDirectory:(_,_)=>throw InvalidHandle(),deleteDirectory:(source,_)=> {
            File.Delete(Path.Combine(source,"keep"));
            throw new IOException("source cleanup interrupted");
        });
        Throws(()=>interruptedDelete.MoveDirectory(target,destination,target,store));
        Check(File.ReadAllText(Path.Combine(destination,"keep"))=="original","interrupted deletion retains verified destination");
        File.WriteAllText(Path.Combine(destination,"keep"),"damaged");
        Throws(()=>new InstallationFileOperations().Recover(target,store));
        Check(Directory.Exists(target) && interruptedDelete.RecoveryPending(store),"damaged destination blocks source cleanup and retains recovery record");
        File.WriteAllText(Path.Combine(destination,"keep"),"original");
        new InstallationFileOperations().Recover(target,store);
        Check(!Directory.Exists(target) && !interruptedDelete.RecoveryPending(store),"source cleanup resumes after destination is verified");
        Console.WriteLine("PASS copy checksums, interrupted source cleanup and damaged destination protection");
    }

    static void InterruptedMoves(string root,string candidate,InstallHooks hooks) {
        var target=Path.Combine(root,"Interrupted","QuotaBar");
        var store=Path.Combine(root,"Interrupted",".QuotaBar-install");
        var files=new InstallationFileOperations(moveDirectory:(_,_)=>throw InvalidHandle());
        var installer=new TransactionInstaller(target,hooks,files);
        installer.Install(candidate);
        var backup=Path.Combine(store,"backup-copy");
        var journal=Path.Combine(store,"copy-move.json");
        var complete=journal+".complete";
        var hashes=Directory.GetFiles(target,"*",SearchOption.AllDirectories).ToDictionary(path=>Path.GetRelativePath(target,path).Replace('\\','/'),path=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant());
        void Record()=>File.WriteAllText(journal,JsonSerializer.Serialize(new { Source=target,Destination=backup,Files=hashes }));

        Directory.CreateDirectory(backup);
        File.WriteAllText(Path.Combine(backup,"QuotaBar.exe"),"partial");
        Record();
        installer.RecoverInterrupted();
        Check(Payload(target)=="one" && !Directory.Exists(backup) && !installer.RecoveryPending,"interrupted backup copy discards partial destination");

        foreach(var (relative,_) in hashes) {
            var destination=Path.Combine(backup,relative);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(Path.Combine(target,relative),destination);
        }
        Record();
        File.WriteAllText(complete,"");
        File.Delete(Path.Combine(target,"runtime","codex.exe"));
        File.WriteAllText(Path.Combine(store,"journal.json"),JsonSerializer.Serialize(new { Target=target,Stage=Path.Combine(store,"stage-missing"),Backup=backup,HadPrevious=true,Startup=false,PreviousHistory=(string?)null }));
        installer.RecoverInterrupted();
        Check(Payload(target)=="one" && File.ReadAllText(Path.Combine(target,"runtime","codex.exe"))=="runtime" && !installer.RecoveryPending,"interrupted source deletion finishes then restores verified backup");

        // A leftover completion marker must never certify the next copy operation.
        File.WriteAllText(complete,"");
        installer.Install(candidate);
        Check(!installer.RecoveryPending,"orphan completion marker does not block next install");

        var recoveryFails=true;
        var failRestore=false;
        var broken=new InstallationFileOperations(moveDirectory:(_,_)=>throw InvalidHandle(),copyFile:(source,destination,overwrite)=> {
            if(failRestore && recoveryFails && source.Contains("backup-",StringComparison.Ordinal)) throw new IOException("restore copy failed");
            File.Copy(source,destination,overwrite);
        });
        var failedRecovery=new TransactionInstaller(target,hooks,broken);
        Exception? failure=null;
        try { failedRecovery.Install(candidate,()=> { failRestore=true;throw new IOException("startup failed"); }); }
        catch(IOException error) { failure=error; }
        Check(failure is not null && failure.ToString().Contains("startup failed") && failure.ToString().Contains("restore copy failed"),"failed recovery preserves original startup error and restore error");
        Check(failedRecovery.RecoveryPending,"failed restoration keeps recovery journal");
        recoveryFails=false;
        new TransactionInstaller(target,hooks,files).RecoverInterrupted();
        Check(Payload(target)=="one" && !installer.RecoveryPending,"new installer resumes failed restoration");

        var history=Path.Combine(store,"history.json");
        File.WriteAllText(history+".tmp",JsonSerializer.Serialize(new { Backup=Path.Combine(store,"backup-consumed"),Startup=false }));
        File.WriteAllText(Path.Combine(store,"journal.json"),JsonSerializer.Serialize(new { Target=target,Stage=Path.Combine(store,"stage-missing"),Backup=Path.Combine(store,"backup-missing"),HadPrevious=true,Startup=false,PreviousHistory=(string?)null }));
        installer.RecoverInterrupted();
        Check(!InstallationState.Exists(history),"restoring absent history removes stale temporary history");

        var outside=Path.Combine(root,"unrelated");
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside,"keep"),"keep");
        File.WriteAllText(journal,JsonSerializer.Serialize(new { Source=outside,Destination=backup,Files=hashes }));
        Throws(installer.RecoverInterrupted);
        Check(File.ReadAllText(Path.Combine(outside,"keep"))=="keep","unmanaged copy paths rejected before deletion");
        File.Delete(journal);
        Console.WriteLine("PASS interrupted copy, source cleanup, failed restore retry and unmanaged path protection");
    }

    static IOException InvalidHandle()=>new("injected invalid handle",unchecked((int)0x80070006));
    static string Payload(string target)=>File.ReadAllText(Path.Combine(target,"QuotaBar.exe"));
    static void Check(bool value,string message) { if(!value) throw new Exception(message); }
    static void Throws(Action action) {
        try { action(); } catch(IOException) { return; }
        throw new Exception("Expected installer failure");
    }
    static string Candidate(string root,string label) {
        var path=Path.Combine(root,label);
        Directory.CreateDirectory(Path.Combine(path,"setup"));
        Directory.CreateDirectory(Path.Combine(path,"runtime"));
        File.WriteAllText(Path.Combine(path,"QuotaBar.exe"),label);
        File.WriteAllText(Path.Combine(path,"setup","QuotaBar.Setup.exe"),"setup");
        File.WriteAllText(Path.Combine(path,"runtime","codex.exe"),"runtime");
        var hashes=Directory.GetFiles(path,"*",SearchOption.AllDirectories).ToDictionary(file=>Path.GetRelativePath(path,file).Replace('\\','/'),file=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))).ToLowerInvariant());
        File.WriteAllText(Path.Combine(path,"package.json"),JsonSerializer.Serialize(new PackageManifest(1,"QuotaBar","windows-x64","1.7.0-beta.4","0.144.1",hashes)));
        return path;
    }
}
