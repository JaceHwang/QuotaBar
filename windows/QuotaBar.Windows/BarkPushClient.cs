using System;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;
using QuotaBar.Core;

namespace QuotaBar.Windows;
internal enum BarkPushResult { Accepted,Rejected,Unknown,Cancelled,Unavailable,InvalidKey }
internal interface IBarkPushClient { Task<BarkPushResult> Send(string key,string title,string body,CancellationToken token); }
internal sealed class BarkPushClient : IBarkPushClient,IDisposable {
    readonly HttpClient http;
    public BarkPushClient(HttpClient? transport=null) { http=transport??new HttpClient(new HttpClientHandler { AllowAutoRedirect=false }); http.Timeout=TimeSpan.FromSeconds(10); }
    public async Task<BarkPushResult> Send(string key,string title,string body,CancellationToken token) {
        if(!BarkPayload.IsValidDeviceKey(key)) return BarkPushResult.InvalidKey;
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token); timeout.CancelAfter(TimeSpan.FromSeconds(10));
        try {
            using var request=new HttpRequestMessage(HttpMethod.Post,"https://api.day.app/push");
            request.Content=new ByteArrayContent(BarkPayload.Encode(key,title,body)); request.Content.Headers.ContentType=new MediaTypeHeaderValue("application/json");
            using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout.Token).ConfigureAwait(false);
            // Never follow a redirect, even for injected handlers.
            if((int)response.StatusCode is >=300 and <400) return BarkPushResult.Rejected;
            if(response.Content.Headers.ContentLength>65536) return BarkPushResult.Unknown;
            await using var stream=await response.Content.ReadAsStreamAsync(timeout.Token).ConfigureAwait(false); using var data=new MemoryStream(); var buffer=new byte[4096]; int count;
            while((count=await stream.ReadAsync(buffer,timeout.Token).ConfigureAwait(false))>0) { if(data.Length+count>65536) return BarkPushResult.Unknown; data.Write(buffer,0,count); }
            var classified=BarkResponse.Classify((int)response.StatusCode,data.ToArray());
            return classified==BarkResponse.Accepted?BarkPushResult.Accepted:classified==BarkResponse.Rejected?BarkPushResult.Rejected:BarkPushResult.Unknown;
        } catch(OperationCanceledException) { return token.IsCancellationRequested?BarkPushResult.Cancelled:BarkPushResult.Unknown; }
        catch(Exception error) when(error is HttpRequestException or IOException or ArgumentException or InvalidOperationException) { return BarkPushResult.Unknown; }
    }
    public void Dispose()=>http.Dispose();
}
