using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using QuotaBar.Core;

internal static class UpdateResumeTests {
    sealed class Handler(Func<HttpRequestMessage,HttpResponseMessage> respond):HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancel)=>Task.FromResult(respond(request));
    }
    static UpdateAsset Asset=>new("fixture.zip",new Uri("https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/fixture.zip"),6,Convert.ToHexString(SHA256.HashData("abcdef"u8)).ToLowerInvariant());
    static void Check(bool value,string message) { if(!value) throw new Exception(message); }
    static HttpResponseMessage Response(HttpStatusCode status,string data,long? from=null,long? total=null) {
        var response=new HttpResponseMessage(status) { Content=new ByteArrayContent(Encoding.UTF8.GetBytes(data)) };
        if(from is { } start) response.Content.Headers.ContentRange=new ContentRangeHeaderValue(start,start+data.Length-1,total!.Value);
        return response;
    }
    public static async Task Run() {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-resume-"+Guid.NewGuid());Directory.CreateDirectory(root);
        try {
            var path=Path.Combine(root,"asset");
            await File.WriteAllTextAsync(path,"abc");
            using(var transport=new UpdateHttpTransport(new Handler(request=> {
                Check(request.Headers.Range?.ToString()=="bytes=3-","existing bytes produce a Range request");
                return Response(HttpStatusCode.PartialContent,"def",3,6);
            }))) await transport.Download(Asset,path,_=>{},default);
            Check(await File.ReadAllTextAsync(path)=="abcdef","206 appends the exact requested suffix");
            await File.WriteAllTextAsync(path,"abc");
            using(var transport=new UpdateHttpTransport(new Handler(_=> {
                var response=Response(HttpStatusCode.PartialContent,"def",3,6);
                response.Content.Headers.ContentRange!.Unit="BYTES";
                return response;
            }))) await transport.Download(Asset,path,_=>{},default);
            Check(await File.ReadAllTextAsync(path)=="abcdef","byte range unit is case-insensitive");

            await File.WriteAllTextAsync(path,"abc");
            using(var transport=new UpdateHttpTransport(new Handler(_=>Response(HttpStatusCode.OK,"abcdef")))) await transport.Download(Asset,path,_=>{},default);
            Check(await File.ReadAllTextAsync(path)=="abcdef","200 restarts instead of appending duplicate bytes");

            foreach(var mode in new[]{"wrong-offset","wrong-total","missing-range","encoded"}) {
                await File.WriteAllTextAsync(path,"abc");
                using var transport=new UpdateHttpTransport(new Handler(_=> {
                    var response=Response(HttpStatusCode.PartialContent,"def",mode=="wrong-offset"?2:3,mode=="wrong-total"?7:6);
                    if(mode=="missing-range") response.Content.Headers.ContentRange=null;
                    if(mode=="encoded") response.Content.Headers.ContentEncoding.Add("gzip");
                    return response;
                }));
                var refused=false;try { await transport.Download(Asset,path,_=>{},default); } catch(IOException) { refused=true; }
                Check(refused && await File.ReadAllTextAsync(path)=="abc","invalid resumed response preserves partial data: "+mode);
            }

            File.Delete(path);
            using(var transport=new UpdateHttpTransport(new Handler(_=>Response(HttpStatusCode.OK,"abc")))) {
                var interrupted=false;try { await transport.Download(Asset,path,_=>{},default); } catch(IOException) { interrupted=true; }
                Check(interrupted && await File.ReadAllTextAsync(path)=="abc","truncated response keeps received bytes for next attempt");
            }
            using(var transport=new UpdateHttpTransport(new Handler(request=> {
                Check(request.Headers.Range?.ToString()=="bytes=3-","retry resumes persisted truncated transfer");
                return Response(HttpStatusCode.PartialContent,"def",3,6);
            }))) await transport.Download(Asset,path,_=>{},default);
            await UpdateDownloadClient.VerifyFile(path,Asset);

            await File.WriteAllTextAsync(path,"abc");
            var requestCount=0;
            using(var transport=new UpdateHttpTransport(new Handler(request=> {
                Check(request.Headers.Range?.ToString()=="bytes=3-","Range survives trusted redirect");
                if(requestCount++==0) { var redirect=new HttpResponseMessage(HttpStatusCode.Found);redirect.Headers.Location=new Uri("https://release-assets.githubusercontent.com/fixture?signature=example");return redirect; }
                return Response(HttpStatusCode.PartialContent,"def",3,6);
            }))) await transport.Download(Asset,path,_=>{},default);
            Check(requestCount==2 && await File.ReadAllTextAsync(path)=="abcdef","trusted redirect resumes correctly");

            await File.WriteAllTextAsync(path,"abc");
            requestCount=0;
            using(var transport=new UpdateHttpTransport(new Handler(request=> {
                if(requestCount++==0) return new HttpResponseMessage(HttpStatusCode.RequestedRangeNotSatisfiable);
                Check(request.Headers.Range is null,"416 falls back to a fresh full request");
                return Response(HttpStatusCode.OK,"abcdef");
            }))) await transport.Download(Asset,path,_=>{},default);
            Check(await File.ReadAllTextAsync(path)=="abcdef","range refusal can recover with a full transfer");
            var data=Enumerable.Repeat((byte)7,200000).ToArray();
            var large=Asset with { Size=data.Length,Sha256=Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant() };
            File.Delete(path);
            using(var cancel=new CancellationTokenSource())
            using(var transport=new UpdateHttpTransport(new Handler(_=>new HttpResponseMessage(HttpStatusCode.OK) { Content=new ByteArrayContent(data) }))) {
                var cancelled=false;
                try { await transport.Download(large,path,n=> { if(n>0) cancel.Cancel(); },cancel.Token); } catch(OperationCanceledException) { cancelled=true; }
                Check(cancelled && new FileInfo(path).Length is >0 and <200000,"cancellation retains only the received prefix");
            }
            var retained=new FileInfo(path).Length;
            using(var transport=new UpdateHttpTransport(new Handler(request=> {
                Check(request.Headers.Range?.Ranges.Single().From==retained,"restart requests the persisted cancellation offset");
                var response=new HttpResponseMessage(HttpStatusCode.PartialContent) { Content=new ByteArrayContent(data[(int)retained..]) };
                response.Content.Headers.ContentRange=new ContentRangeHeaderValue(retained,data.Length-1,data.Length);
                return response;
            }))) await transport.Download(large,path,_=>{},default);
            await UpdateDownloadClient.VerifyFile(path,large);
            Console.WriteLine("PASS HTTP resumed ranges, full-response restart, range rejection, interruption retention and redirects");
        } finally { Directory.Delete(root,true); }
    }
}
