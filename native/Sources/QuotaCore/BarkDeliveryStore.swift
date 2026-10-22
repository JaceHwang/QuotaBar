import Foundation
/// Serialized durable attempts. Failed or unknown deliveries remain reserved; no automatic retries.
public final class BarkDeliveryStore: @unchecked Sendable {
 private struct Receipt: Codable { let identity:BarkEventIdentity; var at:Date; var accepted:Bool }
 private struct State: Codable { var schema=1; var receipts:[Receipt]; var needsBaseline:Bool }
 private let url:URL; private let lock=NSRecursiveLock()
 private var state=State(receipts:[],needsBaseline:false)
 private var error=false
 private var preservationFailed=false
 public var needsBaseline:Bool { lock.lock(); defer { lock.unlock() }; return state.needsBaseline }
 public var hasPersistenceError:Bool { lock.lock(); defer { lock.unlock() }; return error }
 public init(url:URL) {
  self.url=url
  guard FileManager.default.fileExists(atPath:url.path) else {
   if (try? FileManager.default.contentsOfDirectory(atPath:url.deletingLastPathComponent().path))?.contains(where: { $0.hasPrefix(url.lastPathComponent + ".corrupt-") }) == true { state.needsBaseline=true; _=persist(state) }
   return
  }
  do { let data=try Data(contentsOf:url); guard data.count<=1048576 else { throw CocoaError(.fileReadCorruptFile) }; let decoded=try JSONDecoder().decode(State.self,from:data); guard decoded.schema==1,decoded.receipts.count<=256, Set(decoded.receipts.map(\.identity)).count==decoded.receipts.count else { throw CocoaError(.fileReadCorruptFile) }; state=decoded }
  catch { state.needsBaseline=true; do { try FileManager.default.moveItem(at:url,to:url.appendingPathExtension("corrupt-"+UUID().uuidString)); _=persist(state) } catch { self.error=true; preservationFailed=true } }
 }
 private func persist(_ next:State) -> Bool {
  guard !preservationFailed else { return false }
  do { try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); try JSONEncoder().encode(next).write(to:url,options:.atomic); state=next; error=false; return true } catch { self.error=true; return false }
 }
 public func reserve(identity:BarkEventIdentity,now:Date,protected:Set<BarkEventIdentity> = []) -> Bool {
  lock.lock(); defer { lock.unlock() }
  guard !state.receipts.contains(where:{$0.identity==identity}) else { return false }
  var next=state
  next.receipts.removeAll { now.timeIntervalSince($0.at)>30*86400 && !protected.contains($0.identity) }
  guard next.receipts.count<256 else { return false }
  next.receipts.append(Receipt(identity:identity,at:now,accepted:false))
  let baseline=next.needsBaseline
  return persist(next) && !baseline
 }
 public func markAccepted(identity:BarkEventIdentity,now:Date) {
  lock.lock(); defer { lock.unlock() }; var next=state
  guard let i=next.receipts.firstIndex(where:{$0.identity==identity}) else { return }; next.receipts[i].accepted=true; _=persist(next)
 }
 public func establishBaseline(identities:[BarkEventIdentity],now:Date) -> Bool {
  lock.lock(); defer { lock.unlock() }; var next=state
  let protected=Set(identities)
  next.receipts.removeAll { now.timeIntervalSince($0.at)>30*86400 && !protected.contains($0.identity) }
  for identity in protected where !next.receipts.contains(where:{$0.identity==identity}) { guard next.receipts.count<256 else { return false }; next.receipts.append(Receipt(identity:identity,at:now,accepted:false)) }
  next.needsBaseline=false; return persist(next)
 }
}
