using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
namespace QuotaBar.Core;
[JsonConverter(typeof(BarkPreferencesConverter))]
public sealed record BarkPreferences {
 public int Schema { get; init; }=1;
 public bool Enabled { get; init; }
 public string ConfigurationGeneration { get; init; }=Guid.NewGuid().ToString();
 public BarkPreferences Validated()=>Schema==1&&!string.IsNullOrWhiteSpace(ConfigurationGeneration)?this:new();
}
public sealed class BarkPreferencesConverter:JsonConverter<BarkPreferences> {
 public override BarkPreferences Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options) {
  using var doc=JsonDocument.ParseValue(ref reader); var e=doc.RootElement;
  if(e.ValueKind!=JsonValueKind.Object) return new();
  var p=new BarkPreferences();
  if(e.TryGetProperty("Schema",out var schema)) { if(schema.ValueKind!=JsonValueKind.Number||!schema.TryGetInt32(out var n)||n!=1) return new(); }
  if(e.TryGetProperty("Enabled",out var enabled)&&enabled.ValueKind==JsonValueKind.True) p=p with { Enabled=true };
  if(e.TryGetProperty("ConfigurationGeneration",out var generation)&&generation.ValueKind==JsonValueKind.String) p=p with { ConfigurationGeneration=generation.GetString()! };
  return p.Validated();
 }
 public override void Write(Utf8JsonWriter writer,BarkPreferences value,JsonSerializerOptions options) { writer.WriteStartObject(); writer.WriteNumber("Schema",1); writer.WriteBoolean("Enabled",value.Enabled); writer.WriteString("ConfigurationGeneration",value.ConfigurationGeneration); writer.WriteEndObject(); }
}
public sealed record BarkEventIdentity([property:JsonRequired] string Id,[property:JsonRequired] string Generation="initial");
public static class BarkPayload {
 public static bool IsValidDeviceKey(string key) { var k=key.Trim(); return k.Length>0&&Encoding.UTF8.GetByteCount(k)<=512&&!k.Any(c=>char.IsWhiteSpace(c)||char.IsControl(c)||"/\\?#".Contains(c))&&!k.Contains("://")&&ValidUnicode(k); }
 static bool ValidUnicode(string value) { try { _=new UTF8Encoding(false,true).GetByteCount(value); return true; } catch(EncoderFallbackException) { return false; } }
 public static byte[] Encode(string deviceKey,string title,string body) {
  if(!IsValidDeviceKey(deviceKey)) throw new FormatException("Invalid device key");
  byte[] EncodeParts(string t,string b)=>JsonSerializer.SerializeToUtf8Bytes(new { device_key=deviceKey.Trim(),title=t,body=b,group="QuotaBar",level="active" });
  var titles=StringInfo.ParseCombiningCharacters(title);
  var titleCount=titles.Length;
  while(EncodeParts(title,"").Length>3000&&titleCount>0) { titleCount--; title=title[..titles[titleCount]]; }
  var starts=StringInfo.ParseCombiningCharacters(body); var lo=0; var hi=starts.Length;
  string Prefix(int n)=>n==starts.Length?body:body[..starts[n]];
  while(lo<hi) { var mid=(lo+hi+1)/2; if(EncodeParts(title,Prefix(mid)).Length<=3000) lo=mid; else hi=mid-1; }
  var result=EncodeParts(title,Prefix(lo)); if(result.Length>3000) throw new FormatException("Payload too large"); return result;
 }
}
public readonly record struct BarkResponse(int Value) {
 public static readonly BarkResponse Accepted=new(0), Rejected=new(1), Unknown=new(2);
 public static BarkResponse Classify(int statusCode,byte[] body) {
  if(body.Length>65536) return Unknown;
  if(statusCode<200||statusCode>=300) return Rejected;
  try { using var doc=JsonDocument.Parse(body); return doc.RootElement.ValueKind==JsonValueKind.Object&&doc.RootElement.TryGetProperty("code",out var code)&&code.ValueKind==JsonValueKind.Number&&code.TryGetDecimal(out var n)?n==200?Accepted:Rejected:Unknown; }
  catch(JsonException) { return Unknown; }
 }
}
