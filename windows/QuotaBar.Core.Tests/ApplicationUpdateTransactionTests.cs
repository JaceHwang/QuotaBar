using QuotaBar.Core;
internal static class ApplicationUpdateTransactionTests {
    public static void Run() {
        var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root);
        try {
            var asset=new UpdateAsset("a",new Uri("https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/a"),1,new string('a',64));
            var release=new TrustedUpdateRelease("2.0.0","windows-x64",new string('b',40),asset,asset);
            var job=new UpdateInstallJob(1,Guid.NewGuid().ToString("N"),Path.Combine(root,"QuotaBar"),123,new string('a',64),DateTimeOffset.UtcNow.AddMinutes(10),release);
            void Refused(Action action) { try { action(); } catch(IOException) { return; } throw new Exception("Invalid update job accepted"); }
            Refused(()=>job.Validate(root,"wrong",DateTimeOffset.UtcNow));
            Refused(()=>job.Validate(root,job.Target,DateTimeOffset.UtcNow.AddMinutes(11)));
            job.Validate(root,job.Target,DateTimeOffset.UtcNow);
            File.WriteAllText(Path.Combine(root,"consumed"),""); Refused(()=>job.Validate(root,job.Target,DateTimeOffset.UtcNow));
            Console.WriteLine("PASS update job target, expiry and replay validation");
        } finally { Directory.Delete(root,true); }
    }
}
