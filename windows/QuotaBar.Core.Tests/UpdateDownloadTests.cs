using System.Text.Json.Nodes;
using System.Text;
using System.IO.Compression;
using System.Security.Cryptography;
using QuotaBar.Core;
internal static class UpdateDownloadTests {
    sealed class Transport : IUpdateTransport {
        public int DownloadCalls { get; private set; }
        readonly byte[] release,tag,proof; readonly bool corrupt,late;
        public Transport(bool corrupt=false,bool late=false,bool wrongSource=false,string version="2.0.0") {
            this.corrupt=corrupt; this.late=late;
            var rows=JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/in-app-updates/release-cases.json")))!.AsArray(); var row=rows[0]!; var r=row["release"]!.DeepClone(); tag=Encoding.UTF8.GetBytes(row["tag"]!.ToJsonString());
            if(version!="2.0.0") { r=JsonNode.Parse(r.ToJsonString().Replace("2.0.0",version))!; r["prerelease"]=true; }
            proof=Encoding.UTF8.GetBytes(new JsonObject { ["kind"]="release",["workingTreeDirty"]=false,["version"]=version,["releaseTag"]="v"+version,["sourceCommit"]=new string(wrongSource?'c':'b',40) }.ToJsonString());
            foreach(var i in new[]{2,3}) { var bytes=i==2?"package"u8.ToArray():proof; r["assets"]![i]!["size"]=bytes.Length; r["assets"]![i]!["digest"]="sha256:"+Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(); }
            release=Encoding.UTF8.GetBytes(r.ToJsonString());
        }
        public Task<byte[]> Metadata(Uri url,int limit,CancellationToken cancel)=>Task.FromResult(url.AbsolutePath.Contains("/releases/")?release:tag);
        public async Task Download(UpdateAsset asset,string destination,Action<long> progress,CancellationToken cancel) {
            DownloadCalls++;
            var bytes=asset.Name.EndsWith(".zip")?Encoding.UTF8.GetBytes(corrupt?"corrupt":"package"):proof;
            await File.WriteAllBytesAsync(destination,bytes,CancellationToken.None); progress(bytes.Length);
            if(late) try { await Task.Delay(50,cancel); } catch(OperationCanceledException) { }
        }
    }
    public static async Task CacheTests() {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-cache-"+Guid.NewGuid());Directory.CreateDirectory(root);
        try {
            var firstTransport=new Transport();
            var first=await new UpdateDownloadClient(firstTransport).Download("2.0.0","windows-x64","1.3.0",root);
            CheckCache(firstTransport.DownloadCalls==2,"first request downloads package and provenance");
            File.WriteAllText(Path.Combine(first.Directory,"consumed"),"");
            var secondTransport=new Transport();
            var second=await new UpdateDownloadClient(secondTransport).Download("2.0.0","windows-x64","1.3.0",root);
            CheckCache(secondTransport.DownloadCalls==0,"retry after installation failure reuses verified assets");
            CheckCache(first.Directory!=second.Directory && !File.Exists(Path.Combine(second.Directory,"consumed")),"retry gets a fresh installation job directory");
            Directory.Delete(first.Directory,true);Directory.Delete(second.Directory,true);
            var restartedTransport=new Transport();
            var restarted=await new UpdateDownloadClient(restartedTransport).Download("2.0.0","windows-x64","1.3.0",root);
            CheckCache(restartedTransport.DownloadCalls==0,"cache survives operation cleanup and client restart");

            var legacy=Path.Combine(root,"legacy");var legacyJob=Path.Combine(legacy,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(legacyJob);
            File.Copy(restarted.Archive,Path.Combine(legacyJob,restarted.Release.Package.Name));
            File.Copy(restarted.Provenance,Path.Combine(legacyJob,restarted.Release.Provenance.Name));
            File.WriteAllText(Path.Combine(legacyJob,"rolledBack.json"),"historical receipt");
            var legacyTransport=new Transport();
            await new UpdateDownloadClient(legacyTransport).Download("2.0.0","windows-x64","1.3.0",legacy);
            CheckCache(legacyTransport.DownloadCalls==0,"existing failed update archives are imported without downloading");

            var cachedArchive=Path.Combine(root,"downloads",restarted.Release.Package.Sha256);
            foreach(var job in Directory.GetDirectories(root).Where(path=>Guid.TryParse(Path.GetFileName(path),out _))) Directory.Delete(job,true);
            await File.WriteAllTextAsync(cachedArchive,"corrupt");
            var repairedTransport=new Transport();
            var repaired=await new UpdateDownloadClient(repairedTransport).Download("2.0.0","windows-x64","1.3.0",root);
            CheckCache(repairedTransport.DownloadCalls==1 && await File.ReadAllTextAsync(repaired.Archive)=="package","corrupt cached package is replaced while valid provenance is reused");
            using(var reservation=new FileStream(Path.Combine(root,"downloads","download.lock"),FileMode.Open,FileAccess.ReadWrite,FileShare.None)) {
                var refused=false;
                try { await new UpdateDownloadClient(new Transport()).Download("2.0.0","windows-x64","1.3.0",root); } catch(IOException) { refused=true; }
                CheckCache(refused,"concurrent cache writer is rejected before mutation");
            }
            await UpdateDownloadClient.VerifyFile(cachedArchive,repaired.Release.Package);
            var interruptedCache=Path.Combine(root,"interrupted");
            var interrupted=false;
            try { await new UpdateDownloadClient(new InterruptedTransport(true)).Download("2.0.0","windows-x64","1.3.0",interruptedCache); } catch(IOException) { interrupted=true; }
            CheckCache(interrupted,"truncated HTTP response reaches the update client as a failed attempt");
            var resumed=await new UpdateDownloadClient(new InterruptedTransport(false)).Download("2.0.0","windows-x64","1.3.0",interruptedCache);
            CheckCache(await File.ReadAllTextAsync(resumed.Archive)=="package","new operation completes interrupted cached transfer");
            var poisoned=Path.Combine(root,"poisoned");Directory.CreateDirectory(Path.Combine(poisoned,"downloads"));
            var poisonedAsset=Path.Combine(poisoned,"downloads",repaired.Release.Package.Sha256);
            await File.WriteAllTextAsync(poisonedAsset,"bad");
            var rejected=false;
            try { await new UpdateDownloadClient(new InterruptedTransport(false)).Download("2.0.0","windows-x64","1.3.0",poisoned); } catch(IOException) { rejected=true; }
            CheckCache(rejected && !File.Exists(poisonedAsset),"corrupt resumed prefix is rejected and removed after final checksum");
            var fresh=await new UpdateDownloadClient(new Transport()).Download("2.0.0","windows-x64","1.3.0",poisoned);
            CheckCache(await File.ReadAllTextAsync(fresh.Archive)=="package","checksum failure permits a fresh successful retry");
            Console.WriteLine("PASS verified cache reuse, fresh install jobs, cleanup retention, legacy imports and corrupt cache repair");
        } finally { Directory.Delete(root,true); }
    }
    static void CheckCache(bool value,string message) { if(!value) throw new Exception(message); }
    sealed class InterruptedTransport(bool interrupt):IUpdateTransport {
        readonly Transport metadata=new();
        public Task<byte[]> Metadata(Uri url,int limit,CancellationToken cancel)=>metadata.Metadata(url,limit,cancel);
        public async Task Download(UpdateAsset asset,string destination,Action<long> progress,CancellationToken cancel) {
            if(!asset.Name.EndsWith(".zip")) { await metadata.Download(asset,destination,progress,cancel);return; }
            using var http=new UpdateHttpTransport(new HttpFixture(request=> {
                if(!interrupt) CheckCache(request.Headers.Range?.ToString()=="bytes=3-","new client resumes the previous failed operation's offset");
                var response=new HttpResponseMessage(interrupt?System.Net.HttpStatusCode.OK:System.Net.HttpStatusCode.PartialContent) { Content=new ByteArrayContent(Encoding.UTF8.GetBytes(interrupt?"pac":"kage")) };
                if(!interrupt) response.Content.Headers.ContentRange=new System.Net.Http.Headers.ContentRangeHeaderValue(3,6,7);
                return response;
            }));
            await http.Download(asset,destination,progress,cancel);
        }
    }
    sealed class HttpFixture(Func<HttpRequestMessage,HttpResponseMessage> response) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancel)=>Task.FromResult(response(request));
    }
    static async Task HttpBounds() {
        var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root);
        try {
            foreach(var mode in new[]{"valid","truncated","oversized","redirect","loop","metadata"}) {
                using var transport=new UpdateHttpTransport(new HttpFixture(request=> {
                    if(mode is "redirect" or "loop") { var r=new HttpResponseMessage(System.Net.HttpStatusCode.Found); r.Headers.Location=new Uri(mode=="loop"?"https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/a":"https://evil.example/a"); return r; }
                    return new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content=new ByteArrayContent(Encoding.UTF8.GetBytes(mode=="truncated"?"a":mode=="oversized"?"abcdef":"abc")) };
                }));
                var path=Path.Combine(root,mode); var rejected=false;
                try {
                    if(mode=="metadata") await transport.Metadata(TrustedUpdateRelease.ApiUrl("2.0.0"),2,default);
                    else await transport.Download(new UpdateAsset("a",new Uri("https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/a"),3,new string('a',64)),path,_=>{},default);
                } catch(IOException) { rejected=true; }
                if(rejected!=(mode!="valid")) throw new Exception("HTTP bounds/redirect handling: "+mode);
                if(mode=="truncated" && File.ReadAllText(path)!="a") throw new Exception("Interrupted transfer lost partial data");
                if(rejected && mode!="truncated" && File.Exists(path)) throw new Exception("Invalid response created a file");
            }
            var zip=Path.Combine(root,"valid.zip"); using(var archive=ZipFile.Open(zip,ZipArchiveMode.Create)) { using var output=archive.CreateEntry("QuotaBar/a").Open(); output.Write("abc"u8); }
            var extracted=UpdateStaging.ExtractArchive(zip,Path.Combine(root,"out"));
            if(File.ReadAllText(Path.Combine(extracted,"a"))!="abc") throw new Exception("ZIP extraction changed content");
        } finally { Directory.Delete(root,true); }
    }
    static void PreparedPayloadMustMatchArchive() {
        var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root);
        try {
            var candidate=Path.Combine(root,"expanded","QuotaBar"); Directory.CreateDirectory(Path.Combine(candidate,"runtime")); Directory.CreateDirectory(Path.Combine(candidate,"setup"));
            File.WriteAllText(Path.Combine(candidate,"QuotaBar.exe"),"app"); File.WriteAllText(Path.Combine(candidate,"runtime","codex.exe"),"runtime"); File.WriteAllText(Path.Combine(candidate,"setup","QuotaBar.Setup.exe"),"setup");
            var proof=Path.Combine(root,"proof.json"); File.WriteAllText(proof,new JsonObject { ["updateProtocol"]=1,["kind"]="release",["workingTreeDirty"]=false,["version"]="2.0.0",["releaseTag"]="v2.0.0",["sourceCommit"]=new string('b',40) }.ToJsonString()); File.Copy(proof,Path.Combine(candidate,"PROVENANCE.json"));
            void Manifest() { var files=Directory.GetFiles(candidate,"*",SearchOption.AllDirectories).Where(p=>Path.GetFileName(p)!="package.json").ToDictionary(p=>Path.GetRelativePath(candidate,p).Replace('\\','/'),p=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))).ToLowerInvariant()); File.WriteAllText(Path.Combine(candidate,"package.json"),System.Text.Json.JsonSerializer.Serialize(new PackageManifest(1,"QuotaBar","windows-x64","2.0.0","0.144.1",files))); }
            Manifest(); var archive=Path.Combine(root,"archive.zip"); ZipFile.CreateFromDirectory(Path.Combine(root,"expanded"),archive);
            UpdateAsset Asset(string path)=>new(Path.GetFileName(path),new Uri("https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/"+Path.GetFileName(path)),new FileInfo(path).Length,Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant());
            var release=new TrustedUpdateRelease("2.0.0","windows-x64",new string('b',40),Asset(archive),Asset(proof)); var download=new DownloadedUpdate(release,root,archive,proof);
            UpdateStaging.VerifyStaged(download,candidate,Path.Combine(root,"first"));
            File.WriteAllText(Path.Combine(candidate,"QuotaBar.exe"),"forged"); Manifest();
            var refused=false; try { UpdateStaging.VerifyStaged(download,candidate,Path.Combine(root,"second")); } catch(IOException) { refused=true; }
            if(!refused) throw new Exception("Self-consistent forged staged manifest accepted");
        } finally { Directory.Delete(root,true); }
    }
    static void BetaPackageMustCarryMatchingFullIdentity() {
        var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root);
        try {
            var candidate=Path.Combine(root,"input","QuotaBar"); Directory.CreateDirectory(Path.Combine(candidate,"runtime")); Directory.CreateDirectory(Path.Combine(candidate,"setup"));
            File.WriteAllText(Path.Combine(candidate,"QuotaBar.exe"),"app"); File.WriteAllText(Path.Combine(candidate,"runtime","codex.exe"),"runtime"); File.WriteAllText(Path.Combine(candidate,"setup","QuotaBar.Setup.exe"),"setup");
            var version="2.0.0-beta.1"; var proof=Path.Combine(root,"proof.json");
            File.WriteAllText(proof,new JsonObject { ["updateProtocol"]=1,["kind"]="release",["workingTreeDirty"]=false,["version"]=version,["releaseTag"]="v"+version,["sourceCommit"]=new string('b',40) }.ToJsonString());
            File.Copy(proof,Path.Combine(candidate,"PROVENANCE.json"));
            UpdateAsset Asset(string path)=>new(Path.GetFileName(path),new Uri("https://github.com/JaceHwang/QuotaBar/releases/download/v"+version+"/"+Path.GetFileName(path)),new FileInfo(path).Length,Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant());
            void Check(bool shouldAccept,string suffix) {
                var files=Directory.GetFiles(candidate,"*",SearchOption.AllDirectories).Where(p=>Path.GetFileName(p)!="package.json").ToDictionary(p=>Path.GetRelativePath(candidate,p).Replace('\\','/'),p=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))).ToLowerInvariant());
                File.WriteAllText(Path.Combine(candidate,"package.json"),System.Text.Json.JsonSerializer.Serialize(new PackageManifest(1,"QuotaBar","windows-x64",version,"0.144.1",files)));
                var archive=Path.Combine(root,"archive-"+suffix+".zip"); ZipFile.CreateFromDirectory(Path.Combine(root,"input"),archive);
                var release=new TrustedUpdateRelease(version,"windows-x64",new string('b',40),Asset(archive),Asset(proof)); var download=new DownloadedUpdate(release,root,archive,proof);
                var accepted=true; try { UpdateStaging.VerifyPackage(download,Path.Combine(root,"extract-"+suffix)); } catch(IOException) { accepted=false; }
                if(accepted!=shouldAccept) throw new Exception("Beta full identity validation: "+suffix);
            }
            Check(false,"missing");
            File.WriteAllText(Path.Combine(candidate,"PRODUCT-VERSION.json"),"{\"version\":\"2.0.0-beta.1\",\"numericVersion\":\"2.0.0\"}"); Check(false,"missing-assembly");
            var assembly=Path.Combine(candidate,"QuotaBar.dll"); var fixture=Path.Combine(AppContext.BaseDirectory,"fixtures","QuotaBar.dll");
            File.WriteAllText(assembly,"not a managed assembly"); Check(false,"invalid-assembly");
            File.Copy(fixture,assembly,true); Check(true,"valid");
            File.Copy(typeof(UpdateDownloadTests).Assembly.Location,assembly,true); Check(false,"wrong-assembly");
            File.Copy(Path.Combine(AppContext.BaseDirectory,"fixtures","mismatch","QuotaBar.dll"),assembly,true); Check(false,"wrong-assembly-version");
            File.Copy(fixture,assembly,true);
            File.WriteAllText(Path.Combine(candidate,"PRODUCT-VERSION.json"),"{\"version\":\"2.0.0-beta.2\",\"numericVersion\":\"2.0.0\"}"); Check(false,"mismatch");
        } finally { Directory.Delete(root,true); }
    }
    public static async Task Run() {
        await CacheTests();
        BetaPackageMustCarryMatchingFullIdentity();
        var betaRoot=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString());
        try {
            var beta=new UpdateDownloadClient(new Transport(version:"2.0.0-beta.1")); var refused=false;
            try { await beta.Download("2.0.0-beta.1","windows-x64","1.9.0",betaRoot); } catch(FormatException) { refused=true; }
            if(!refused) throw new Exception("Beta downloaded without consent");
            var downloaded=await beta.Download("2.0.0-beta.1","windows-x64","1.9.0",betaRoot,allowBeta:true);
            if(downloaded.Release.Version!="2.0.0-beta.1") throw new Exception("Beta download identity mismatch");
        } finally { if(Directory.Exists(betaRoot)) Directory.Delete(betaRoot,true); }
        PreparedPayloadMustMatchArchive();
        foreach(var value in new[]{"{}","{\"updateProtocol\":2}","{\"updateProtocol\":1}"}) {
            var refused=false; try { UpdateStaging.RequireUpdateProtocol(Encoding.UTF8.GetBytes(value)); } catch(IOException) { refused=true; }
            if(refused==(value.EndsWith("1}"))) throw new Exception("Unsupported updater protocol accepted");
        }
        await HttpBounds();
        for(var mode=0;mode<4;mode++) {
            var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root); File.WriteAllText(Path.Combine(root,"keep"),"keep");
            try {
                var client=new UpdateDownloadClient(new Transport(mode==1,mode==3,mode==2)); using var cancel=new CancellationTokenSource();
                var task=client.Download("2.0.0","windows-x64","1.3.0",root,null,cancel.Token); if(mode==3) { await Task.Delay(5); cancel.Cancel(); }
                try { var result=await task; if(mode!=0||File.ReadAllText(result.Archive)!="package") throw new Exception("Invalid download accepted"); }
                catch(Exception e) when(e is IOException or OperationCanceledException or FormatException) { if(mode==0) throw; }
                if(mode!=0 && Directory.GetDirectories(root).Any(path=>Guid.TryParse(Path.GetFileName(path),out _))) throw new Exception("Failed installation workspace leaked");
                if(!File.Exists(Path.Combine(root,"keep"))) throw new Exception("Unrelated file removed");
            } finally { Directory.Delete(root,true); }
        }
        foreach(var names in new[]{new[]{"../outside"},new[]{"QuotaBar/a","QuotaBar/A"},new[]{"QuotaBar/a:ads"},new[]{"QuotaBar/link"}}) {
            var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString()); Directory.CreateDirectory(root); var zip=Path.Combine(root,"input.zip");
            try {
                using(var a=ZipFile.Open(zip,ZipArchiveMode.Create)) foreach(var name in names) { var e=a.CreateEntry(name); if(name.EndsWith("link")) e.ExternalAttributes=unchecked((int)0xA1FF0000); using var s=e.Open(); s.WriteByte(1); }
                var refused=false; try { UpdateStaging.ExtractArchive(zip,Path.Combine(root,"output")); } catch(IOException) { refused=true; }
                if(!refused) throw new Exception("Unsafe ZIP accepted");
            } finally { Directory.Delete(root,true); }
        }
        var noSpace=false; try { UpdateStaging.RequireSpace(1024,0); } catch(IOException) { noSpace=true; } if(!noSpace) throw new Exception("Disk capacity ignored");
        Console.WriteLine("PASS update download digest/provenance/cancellation and ZIP/disk safety");
    }
}
