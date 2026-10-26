using System.Text.Json;
using System.Text.Json.Serialization;
namespace QuotaBar.Core;
public sealed record MessageCenterKey([property:JsonRequired]string Id,[property:JsonRequired]string Generation,string? Epoch=null);
public sealed record MessageCenterRecord([property:JsonRequired]MessageCenterKey Key,[property:JsonRequired]NotificationCategory Category,[property:JsonRequired]string Title,[property:JsonRequired]string Body,[property:JsonRequired]long CreatedAtMilliseconds,long? ReadAtMilliseconds,[property:JsonRequired]HashSet<NotificationChannel> Channels) {
 [JsonIgnore] public DateTimeOffset CreatedAt=>DateTimeOffset.FromUnixTimeMilliseconds(CreatedAtMilliseconds);
}
/// Persistent snapshots, deliberately independent of live notification delivery queues.
public sealed class MessageCenterStore {
 sealed record Document([property:JsonRequired]int Schema,[property:JsonRequired]MessageCenterRecord[] Messages);
 static readonly JsonSerializerOptions options=new() { PropertyNamingPolicy=JsonNamingPolicy.CamelCase,Converters={new JsonStringEnumConverter(JsonNamingPolicy.CamelCase,allowIntegerValues:false)} };
 readonly string path;
 Dictionary<MessageCenterKey,MessageCenterRecord> durable=[],pending=[];
 bool loadBlocked;
 public string? Error { get; private set; }
 public bool HasUnpersistedMessages=>pending.Count>0;
 public IReadOnlyList<MessageCenterRecord> Records=>Combined().Values.OrderByDescending(r=>r.CreatedAtMilliseconds).ThenBy(r=>r.Key.Id,StringComparer.Ordinal).ThenBy(r=>r.Key.Generation,StringComparer.Ordinal).ThenBy(r=>r.Key.Epoch??"",StringComparer.Ordinal).Select(Clone).ToArray();
 public int UnreadCount=>Combined().Values.Count(r=>r.ReadAtMilliseconds is null);
 public bool IsPersisted(MessageCenterKey key)=>durable.ContainsKey(key)&&!pending.ContainsKey(key);
 public MessageCenterStore(string path) { this.path=path; Reload(); }
 static MessageCenterRecord Clone(MessageCenterRecord r)=>r with { Channels=new(r.Channels) };
 static MessageCenterRecord Merge(MessageCenterRecord first,MessageCenterRecord other)=>first with { Channels=first.Channels.Union(other.Channels).ToHashSet(),ReadAtMilliseconds=first.ReadAtMilliseconds is {} a&&other.ReadAtMilliseconds is {} b?Math.Min(a,b):first.ReadAtMilliseconds??other.ReadAtMilliseconds };
 static bool Equivalent(MessageCenterRecord a,MessageCenterRecord b)=>a.Key==b.Key&&a.Category==b.Category&&a.Title==b.Title&&a.Body==b.Body&&a.CreatedAtMilliseconds==b.CreatedAtMilliseconds&&a.ReadAtMilliseconds==b.ReadAtMilliseconds&&a.Channels.SetEquals(b.Channels);
 Dictionary<MessageCenterKey,MessageCenterRecord> Combined() {
  var result=new Dictionary<MessageCenterKey,MessageCenterRecord>(durable);
  foreach(var (key,row) in pending) result[key]=result.TryGetValue(key,out var old)?Merge(old,row):row;
  return result;
 }
 static bool Valid(MessageCenterRecord? r)=>r is { Key:{} key,Title:{} title,Body:{} body,Channels:{} channels }&&!string.IsNullOrEmpty(key.Id)&&key.Id.Length<=4096&&!string.IsNullOrEmpty(key.Generation)&&key.Generation.Length<=4096&&(key.Epoch is null||key.Epoch.Length is >0 and <=4096)&&title.Length<=4096&&body.Length<=65536&&r.CreatedAtMilliseconds is >=0 and <=253402300799999&&(r.ReadAtMilliseconds is null||r.ReadAtMilliseconds is >=0 and <=253402300799999)&&Enum.IsDefined(r.Category)&&channels.Count>0&&channels.All(Enum.IsDefined);
 public bool Reload() {
  try {
   string json;
   try { json=File.ReadAllText(path); }
   catch(Exception e) when(e is FileNotFoundException or DirectoryNotFoundException) {
    var known=Combined();durable=[];pending=known;loadBlocked=false;
    if(known.Count==0) { Error=null;return true; }
    return Persist(known,true);
   }
   var doc=JsonSerializer.Deserialize<Document>(json,options);
   if(doc is null||doc.Schema!=1||doc.Messages is null||doc.Messages.Any(r=>!Valid(r))||doc.Messages.Select(r=>r.Key).Distinct().Count()!=doc.Messages.Length) throw new JsonException("Invalid message history document.");
   durable=doc.Messages.ToDictionary(r=>r.Key,Clone);loadBlocked=false;
   if(pending.Count==0) { Error=null;return true; }
   return Persist(Combined(),true);
  } catch(Exception e) when(e is JsonException or IOException or UnauthorizedAccessException) { loadBlocked=true;Error=e.Message;return false; }
 }
 public bool Append(MessageCenterRecord row)=>Append([row]);
 public bool Append(IEnumerable<MessageCenterRecord> rows) {
  var added=rows.ToArray(); if(added.Any(r=>!Valid(r))) { Error="Invalid message record.";return false; }
  var next=Combined(); foreach(var row in added) next[row.Key]=next.TryGetValue(row.Key,out var old)?Merge(old,row):Clone(row);
  if(loadBlocked) { Stage(next);return false; }
  if(pending.Count==0&&next.Count==durable.Count&&next.All(r=>durable.TryGetValue(r.Key,out var old)&&Equivalent(old,r.Value))) return true;
  return Persist(next,true);
 }
 public bool MarkRead(MessageCenterKey key,long atMilliseconds) {
  if(loadBlocked||atMilliseconds is <0 or >253402300799999) return false;
  var next=Combined();if(!next.TryGetValue(key,out var row)) return false;if(row.ReadAtMilliseconds!=null) return true;
  next[key]=row with { ReadAtMilliseconds=Math.Max(atMilliseconds,row.CreatedAtMilliseconds) };return Persist(next,false);
 }
 public bool MarkAllRead(long atMilliseconds) {
  if(loadBlocked||atMilliseconds is <0 or >253402300799999) return false;
  var next=Combined();if(next.Values.All(r=>r.ReadAtMilliseconds!=null)) return true;
  foreach(var (key,row) in next.ToArray()) if(row.ReadAtMilliseconds is null) next[key]=row with { ReadAtMilliseconds=Math.Max(atMilliseconds,row.CreatedAtMilliseconds) };
  return Persist(next,false);
 }
 void Stage(Dictionary<MessageCenterKey,MessageCenterRecord> next)=>pending=next.Where(r=>!durable.TryGetValue(r.Key,out var old)||!Equivalent(old,r.Value)).ToDictionary(r=>r.Key,r=>Clone(r.Value));
 bool Persist(Dictionary<MessageCenterKey,MessageCenterRecord> next,bool stageOnFailure) {
  var temp=path+"."+Guid.NewGuid()+".tmp";
  try {
   Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
   using(var output=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { JsonSerializer.Serialize(output,new Document(1,next.Values.ToArray()),options);output.Flush(true); }
   File.Move(temp,path,true);durable=next;pending=[];loadBlocked=false;Error=null;return true;
  } catch(Exception e) when(e is IOException or UnauthorizedAccessException) { Error=e.Message;if(stageOnFailure) Stage(next);return false; }
  finally { try { File.Delete(temp); } catch(IOException) { } catch(UnauthorizedAccessException) { } }
 }
}
