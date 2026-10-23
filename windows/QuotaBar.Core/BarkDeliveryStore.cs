using System.Text.Json;
namespace QuotaBar.Core;
public sealed class BarkDeliveryStore {
 sealed record Receipt([property:System.Text.Json.Serialization.JsonRequired] BarkEventIdentity Identity,[property:System.Text.Json.Serialization.JsonRequired] DateTimeOffset At,[property:System.Text.Json.Serialization.JsonRequired] bool Accepted);
 sealed record State([property:System.Text.Json.Serialization.JsonRequired] int Schema,[property:System.Text.Json.Serialization.JsonRequired] List<Receipt> Receipts,[property:System.Text.Json.Serialization.JsonRequired] bool NeedsBaseline);
 readonly object gate=new(); readonly string path;
 State state=new(1,[],false); bool error; bool preservationFailed;
 public bool NeedsBaseline { get { lock(gate) return state.NeedsBaseline; } }
 public bool HasPersistenceError { get { lock(gate) return error; } }
 public BarkDeliveryStore(string path) {
  this.path=path;
  if(!File.Exists(path)) {
   var parent=Path.GetDirectoryName(Path.GetFullPath(path))!;
   try { if(Directory.Exists(parent)&&Directory.EnumerateFiles(parent,Path.GetFileName(path)+".corrupt-*").Any()) { state=state with { NeedsBaseline=true }; Persist(state); } }
   catch(Exception e) when(e is IOException or UnauthorizedAccessException) { state=state with { NeedsBaseline=true }; error=true; }
   return;
  }
  try { if(new FileInfo(path).Length>1048576) throw new JsonException(); var loaded=JsonSerializer.Deserialize<State>(File.ReadAllText(path));
   if(loaded is null||loaded.Schema!=1||loaded.Receipts is null||loaded.Receipts.Count>256||loaded.Receipts.Any(r=>r is null||r.Identity is null||r.Identity.Id is null||r.Identity.Generation is null)||loaded.Receipts.Select(r=>r.Identity).Distinct().Count()!=loaded.Receipts.Count) throw new JsonException(); state=loaded;
  } catch(Exception e) when(e is JsonException or IOException or UnauthorizedAccessException) { state=state with { NeedsBaseline=true }; try { File.Move(path,path+".corrupt-"+Guid.NewGuid()); Persist(state); } catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) { error=true; preservationFailed=true; } }
 }
 bool Persist(State next) {
  if(preservationFailed) return false;
  var temp=path+"."+Guid.NewGuid()+".tmp";
  try { Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!); File.WriteAllBytes(temp,JsonSerializer.SerializeToUtf8Bytes(next)); File.Move(temp,path,true); state=next; error=false; return true; }
  catch(Exception e) when(e is IOException or UnauthorizedAccessException) { error=true; return false; }
  finally { try { if(File.Exists(temp)) File.Delete(temp); } catch(IOException) { } catch(UnauthorizedAccessException) { } }
 }
 public bool Reserve(BarkEventIdentity identity,DateTimeOffset now,IReadOnlySet<BarkEventIdentity>? protectedIdentities=null) {
  lock(gate) {
   if(state.Receipts.Any(r=>r.Identity==identity)) return false;
   var rows=state.Receipts.Where(r=>now-r.At<=TimeSpan.FromDays(30)||(protectedIdentities?.Contains(r.Identity)??false)).ToList();
   if(rows.Count>=256) return false;
   rows.Add(new(identity,now,false)); var baseline=state.NeedsBaseline; return Persist(state with { Receipts=rows })&&!baseline;
  }
 }
 public void MarkAccepted(BarkEventIdentity identity,DateTimeOffset now) { lock(gate) { if(!state.Receipts.Any(r=>r.Identity==identity)) return; Persist(state with { Receipts=state.Receipts.Select(r=>r.Identity==identity?r with { Accepted=true }:r).ToList() }); } }
 public bool EstablishBaseline(IEnumerable<BarkEventIdentity> identities,DateTimeOffset now) {
  lock(gate) { var protectedIds=identities.ToHashSet(); var rows=state.Receipts.Where(r=>now-r.At<=TimeSpan.FromDays(30)||protectedIds.Contains(r.Identity)).ToList(); foreach(var id in protectedIds) if(!rows.Any(r=>r.Identity==id)) { if(rows.Count>=256) return false; rows.Add(new(id,now,false)); } return Persist(state with { Receipts=rows,NeedsBaseline=false }); }
 }
}
