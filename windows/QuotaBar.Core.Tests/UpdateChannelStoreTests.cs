using QuotaBar.Core;

static class UpdateChannelStoreTests {
    public static void Run() {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-channel-save-"+Guid.NewGuid());
        Directory.CreateDirectory(root);
        try {
            var path=Path.Combine(root,"update-channel.json");
            var store=new UpdateChannelStore(path);
            store.Save(true);
            if(!new UpdateChannelStore(path).Load()) throw new Exception("Enabled beta must survive restart");
            store.Save(false);
            if(new UpdateChannelStore(path).Load()) throw new Exception("Disabled beta must survive restart");
            Console.WriteLine("PASS beta channel saves enabled and disabled on the local filesystem");
            var compatible=new UpdateChannelStore(path,(_,_,_)=>throw new IOException("Invalid handle",unchecked((int)0x80070006)));
            compatible.Save(true);
            if(!new UpdateChannelStore(path).Load()) throw new Exception("Fallback must persist enabled beta");
            compatible.Save(false);
            if(new UpdateChannelStore(path).Load()) throw new Exception("Fallback must persist disabled beta");
            if(!new UpdateChannelStore(path+".backup").Load()) throw new Exception("Fallback must retain the previous setting");
            TestOtherErrors(root);
            TestFailedWrites(root);
            TestFailedRestore(root);
            TestValidFileAfterFailedRestore(root);
            TestMissingFileAfterFailedRestore(root);
            TestSaveAfterExternalRecovery(root);
            TestCorruption(root);
            TestFailedQuarantine(root);
            if(Directory.EnumerateFiles(root,"*.tmp").Any()) throw new Exception("Temporary settings files must be cleaned");
            Console.WriteLine("PASS beta invalid-handle fallback, corruption quarantine, I/O errors and backup recovery protection");
        } finally { Directory.Delete(root,true); }
    }

    static void InvalidHandle(string source,string destination,bool overwrite) =>
        throw new IOException("Invalid handle",unchecked((int)0x80070006));

    static void Fails(Action action) {
        try { action(); }
        catch(IOException) { return; }
        throw new Exception("Expected the failed save to propagate");
    }

    static void TestOtherErrors(string root) {
        var path=Path.Combine(root,"other-errors.json");
        File.WriteAllText(path,"{\"schema\":1,\"betaEnabled\":false}");
        var original=File.ReadAllBytes(path);
        foreach(var error in new[]{5,32}) {
            var store=new UpdateChannelStore(path,(_,_,_)=>throw new IOException("Other I/O error",unchecked((int)0x80070000)|error),
                (_,_,_)=>throw new Exception("Unrelated I/O errors must not use the fallback"));
            Fails(()=>store.Save(true));
            if(!original.SequenceEqual(File.ReadAllBytes(path))) throw new Exception("Other I/O errors must preserve the original setting");
        }
    }

    static void TestFailedWrites(string root) {
        var path=Path.Combine(root,"partial-write.json");
        File.WriteAllText(path,"{\"schema\":1,\"betaEnabled\":false}");
        var original=File.ReadAllBytes(path);
        var store=new UpdateChannelStore(path,InvalidHandle,(source,destination,overwrite)=> {
            if(destination==path && source.EndsWith(".tmp",StringComparison.Ordinal)) {
                File.WriteAllText(destination,"{broken");
                throw new IOException("Partial write");
            }
            File.Copy(source,destination,overwrite);
        });
        Fails(()=>store.Save(true));
        if(!original.SequenceEqual(File.ReadAllBytes(path))) throw new Exception("A partial overwrite must restore the original setting");

        var fresh=Path.Combine(root,"failed-first-save.json");
        var firstSave=new UpdateChannelStore(fresh,InvalidHandle,(source,destination,overwrite)=> {
            File.WriteAllText(destination,"{broken");
            throw new IOException("Partial first write");
        });
        Fails(()=>firstSave.Save(true));
        if(File.Exists(fresh)) throw new Exception("Failed first save must remove the partial file");
        new UpdateChannelStore(fresh,InvalidHandle).Save(true);
        if(!new UpdateChannelStore(fresh).Load()) throw new Exception("First save can be retried after cleanup");

        var backupFailure=new UpdateChannelStore(path,InvalidHandle,(_,_,_)=>throw new IOException("Backup failed"));
        Fails(()=>backupFailure.Save(true));
        if(!original.SequenceEqual(File.ReadAllBytes(path))) throw new Exception("Backup failure must preserve the original setting");
    }

    static void TestFailedRestore(string root) {
        var path=Path.Combine(root,"failed-restore.json");
        File.WriteAllText(path,"{\"schema\":1,\"betaEnabled\":false}");
        var original=File.ReadAllBytes(path);
        var store=new UpdateChannelStore(path,InvalidHandle,(source,destination,overwrite)=> {
            if(destination==path) {
                File.WriteAllText(destination,"{broken");
                throw new IOException("Write and restore failed");
            }
            File.Copy(source,destination,overwrite);
        });
        Fails(()=>store.Save(true));
        Fails(()=>store.Save(true));
        var restarted=new UpdateChannelStore(path,InvalidHandle);
        if(restarted.Load()) throw new Exception("A failed restore must keep beta disabled");
        Fails(()=>restarted.Save(true));
        if(!original.SequenceEqual(File.ReadAllBytes(path+".backup"))) throw new Exception("Retry and restart must preserve the last valid backup");
        if(File.ReadAllText(path)!="{broken") throw new Exception("Loading must retain failed recovery evidence");
    }

    static void TestMissingFileAfterFailedRestore(string root) {
        var path=Path.Combine(root,"missing-after-restore.json");
        var backup=path+".backup";
        File.WriteAllText(backup,"{\"schema\":1,\"betaEnabled\":false}");
        var original=File.ReadAllBytes(backup);
        var store=new UpdateChannelStore(path,InvalidHandle);
        if(store.Load()) throw new Exception("Missing settings must keep beta disabled");
        Fails(()=>store.Save(true));
        if(File.Exists(path) || !original.SequenceEqual(File.ReadAllBytes(backup))) throw new Exception("Missing-file recovery must preserve the backup");
    }

    static void TestValidFileAfterFailedRestore(string root) {
        var path=Path.Combine(root,"valid-failed-restore.json");
        File.WriteAllText(path,"{\"schema\":1,\"betaEnabled\":false}");
        var original=File.ReadAllBytes(path);
        var store=new UpdateChannelStore(path,InvalidHandle,(source,destination,overwrite)=> {
            if(destination==path) {
                if(source.EndsWith(".tmp",StringComparison.Ordinal)) File.Copy(source,destination,overwrite);
                throw new IOException("Failed after a complete write; restore also fails");
            }
            File.Copy(source,destination,overwrite);
        });
        Fails(()=>store.Save(true));
        if(store.Load()) throw new Exception("Failed restore must not enable beta even when the new JSON is valid");
        var restarted=new UpdateChannelStore(path,InvalidHandle);
        if(restarted.Load()) throw new Exception("Restart must not accept the uncommitted valid JSON");
        Fails(()=>restarted.Save(true));
        if(!original.SequenceEqual(File.ReadAllBytes(path+".backup"))) throw new Exception("Restart must preserve the original backup after a valid-file restore failure");
    }

    static void TestSaveAfterExternalRecovery(string root) {
        var path=Path.Combine(root,"external-recovery.json");
        var backup=path+".backup";
        File.WriteAllText(backup,"{\"schema\":1,\"betaEnabled\":true}");
        Directory.CreateDirectory(path);
        var store=new UpdateChannelStore(path,InvalidHandle);
        Fails(()=>store.Save(false));
        Directory.Delete(path);
        File.Copy(backup,path);
        store.Save(false);
        if(new UpdateChannelStore(path).Load()) throw new Exception("Saving must resume after an external recovery");
    }

    static void TestCorruption(string root) {
        var path=Path.Combine(root,"corrupt-load.json");
        const string corrupt="{\"schema\":1,\"betaEnabled\":\"yes\"}";
        File.WriteAllText(path,corrupt);
        var store=new UpdateChannelStore(path,InvalidHandle);
        if(store.Load()) throw new Exception("Corrupt settings must keep beta disabled");
        var quarantined=Directory.GetFiles(root,"corrupt-load.json.corrupt-*").Single();
        if(File.Exists(path) || File.ReadAllText(quarantined)!=corrupt) throw new Exception("Fallback quarantine must preserve the exact corrupt file");
        store.Save(true);
        if(!new UpdateChannelStore(path).Load()) throw new Exception("Saving after quarantine must work");

        var direct=Path.Combine(root,"corrupt-save.json");
        File.WriteAllText(direct,corrupt);
        new UpdateChannelStore(direct,InvalidHandle).Save(false);
        if(new UpdateChannelStore(direct).Load() || File.ReadAllText(Directory.GetFiles(root,"corrupt-save.json.corrupt-*").Single())!=corrupt)
            throw new Exception("Direct save must quarantine corrupt settings before replacing them");
    }

    static void TestFailedQuarantine(string root) {
        var path=Path.Combine(root,"quarantine-failure.json");
        File.WriteAllText(path,"{broken");
        var store=new UpdateChannelStore(path,InvalidHandle,(_,_,_)=>throw new IOException("Quarantine copy failed"));
        if(store.Load()) throw new Exception("Failed quarantine must keep beta disabled");
        Fails(()=>store.Save(true));
        if(File.ReadAllText(path)!="{broken") throw new Exception("Failed quarantine must retain the original file");
    }
}
