using QuotaBar.Core;
internal static class ApplicationUpdateTransactionTests {
    public static void Run() {
        var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root);
        try {
            var managed=Path.Combine(root,"Programs","QuotaBar");
            var reservation=new UpdateHandoffReservation(managed); var locked=false;
            try { using var second=new UpdateHandoffReservation(managed); } catch(IOException) { locked=true; }
            if(!locked) throw new Exception("Competing helpers both became ready"); reservation.Dispose();
            using var retryReservation=new UpdateHandoffReservation(managed);
            var asset=new UpdateAsset("a",new Uri("https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/a"),1,new string('a',64));
            var release=new TrustedUpdateRelease("2.0.0","windows-x64",new string('b',40),asset,asset);
            var job=new UpdateInstallJob(1,Guid.NewGuid().ToString("N"),Path.Combine(root,"QuotaBar"),123,new string('a',64),DateTimeOffset.UtcNow.AddMinutes(10),release);
            void Refused(Action action) { try { action(); } catch(IOException) { return; } throw new Exception("Invalid update job accepted"); }
            var betaJob=job with { Release=release with { Version="2.0.0-beta.1" } };
            Refused(()=>betaJob.Validate(root,betaJob.Target,DateTimeOffset.UtcNow));
            betaJob.Validate(root,betaJob.Target,DateTimeOffset.UtcNow,true);
            Refused(()=>job.Validate(root,"wrong",DateTimeOffset.UtcNow));
            Refused(()=>job.Validate(root,job.Target,DateTimeOffset.UtcNow.AddMinutes(11)));
            job.Validate(root,job.Target,DateTimeOffset.UtcNow);
            var receipt=Path.Combine(root,Guid.NewGuid().ToString("N")); Directory.CreateDirectory(receipt); job.Write(receipt); job.Receipt("succeeded",receipt);
            job.RecordFailure("installation",new IOException("directory replacement failed",unchecked((int)0x80070006)),receipt);
            using(var failure=System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(receipt,"failure.json")))) {
                var details=failure.RootElement;
                if(details.GetProperty("stage").GetString()!="installation" || !details.GetProperty("error").GetString()!.Contains("directory replacement failed") || details.GetProperty("hResult").GetInt32()!=unchecked((int)0x80070006)) throw new Exception("Update failure lost its stage or underlying error");
            }
            if(UpdateInstallJob.ConsumeResult(root,job.Target)!=ApplicationUpdatePhase.Succeeded || UpdateInstallJob.ConsumeResult(root,job.Target)!=null) throw new Exception("Result replayed or lost");
            File.WriteAllText(Path.Combine(root,"consumed"),""); Refused(()=>job.Validate(root,job.Target,DateTimeOffset.UtcNow));
            Console.WriteLine("PASS update job target, expiry and replay validation");
        } finally { Directory.Delete(root,true); }
    }
}
