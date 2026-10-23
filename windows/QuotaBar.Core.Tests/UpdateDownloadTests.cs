using System.Text.Json.Nodes;
using System.Text;
using System.IO.Compression;
using System.Security.Cryptography;
using QuotaBar.Core;
internal static class UpdateDownloadTests {
    sealed class Transport : IUpdateTransport {
        readonly byte[] release,tag,proof; readonly bool corrupt,late;
        public Transport(bool corrupt=false,bool late=false,bool wrongSource=false) {
            this.corrupt=corrupt; this.late=late;
            var rows=JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"contracts/in-app-updates/release-cases.json")))!.AsArray(); var row=rows[0]!; var r=row["release"]!.DeepClone(); tag=Encoding.UTF8.GetBytes(row["tag"]!.ToJsonString());
            proof=Encoding.UTF8.GetBytes(new JsonObject { ["kind"]="release",["workingTreeDirty"]=false,["version"]="2.0.0",["releaseTag"]="v2.0.0",["sourceCommit"]=new string(wrongSource?'c':'b',40) }.ToJsonString());
            foreach(var i in new[]{2,3}) { var bytes=i==2?"package"u8.ToArray():proof; r["assets"]![i]!["size"]=bytes.Length; r["assets"]![i]!["digest"]="sha256:"+Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(); }
            release=Encoding.UTF8.GetBytes(r.ToJsonString());
        }
        public Task<byte[]> Metadata(Uri url,int limit,CancellationToken cancel)=>Task.FromResult(url.AbsolutePath.Contains("/releases/")?release:tag);
        public async Task Download(UpdateAsset asset,string destination,Action<long> progress,CancellationToken cancel) {
            var bytes=asset.Name.EndsWith(".zip")?Encoding.UTF8.GetBytes(corrupt?"corrupt":"package"):proof;
            await File.WriteAllBytesAsync(destination,bytes,CancellationToken.None); progress(bytes.Length);
            if(late) try { await Task.Delay(50,cancel); } catch(OperationCanceledException) { }
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
                if(rejected && File.Exists(path)) throw new Exception("Failed transfer leaked file");
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
    public static async Task Run() {
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
                if(mode!=0 && Directory.GetDirectories(root).Length!=0) throw new Exception("Failed stage leaked");
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
