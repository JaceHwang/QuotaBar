import Foundation
import CoreFoundation
public struct BarkPreferences: Codable, Equatable, Sendable {
 public var schema = 1
 public var enabled: Bool
 public var configurationGeneration: String
 public init(enabled: Bool = false, configurationGeneration: String = UUID().uuidString) { self.enabled=enabled; self.configurationGeneration=configurationGeneration }
 public func validated() -> Self { schema == 1 && !configurationGeneration.isEmpty ? self : Self() }
 public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); if c.contains(.schema), (try? c.decode(Int.self,forKey:.schema)) != 1 { self=Self(); return }; schema=(try? c.decode(Int.self,forKey:.schema)) ?? 1; enabled=(try? c.decode(Bool.self,forKey:.enabled)) ?? false; configurationGeneration=(try? c.decode(String.self,forKey:.configurationGeneration)) ?? UUID().uuidString; self=validated() }
}
public struct BarkEventIdentity: Codable, Hashable, Sendable {
 public let id: String; public let generation: String
 public init(id: String, generation: String = "initial") { self.id=id; self.generation=generation }
}
public enum BarkPayload {
 public enum Failure: Error { case invalidKey, payloadTooLarge }
 public static func isValidDeviceKey(_ key: String) -> Bool {
  let k=key.trimmingCharacters(in:.whitespacesAndNewlines)
  return !k.isEmpty && k.utf8.count<=512 && !k.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) } && !k.contains(where:{ "/\\?#".contains($0) }) && !k.contains("://")
 }
 public static func encode(deviceKey: String,title: String,body: String) throws -> Data {
  guard isValidDeviceKey(deviceKey) else { throw Failure.invalidKey }
  let key=deviceKey.trimmingCharacters(in:.whitespacesAndNewlines)
  func encoded(_ t:String,_ b:String) throws -> Data { try JSONSerialization.data(withJSONObject:["device_key":key,"title":t,"body":b,"group":"QuotaBar","level":"active"],options:[.sortedKeys,.withoutEscapingSlashes]) }
  var t=title, b=body
  while try encoded(t,"").count>3000 && !t.isEmpty { t.removeLast() }
  let chars=Array(b); var lo=0,hi=chars.count
  while lo<hi { let mid=(lo+hi+1)/2; if try encoded(t,String(chars.prefix(mid))).count<=3000 { lo=mid } else { hi=mid-1 } }
  b=String(chars.prefix(lo)); let data=try encoded(t,b); guard data.count<=3000 else { throw Failure.payloadTooLarge }; return data
 }
}
public enum BarkResponse: Sendable { case accepted,rejected,unknown
 public static func classify(statusCode:Int,body:Data) -> Self {
  guard body.count<=65536 else { return .unknown }
  guard (200..<300).contains(statusCode) else { return .rejected }
  guard let json=(try? JSONSerialization.jsonObject(with:body)) as? [String:Any], let code=json["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID() else { return .unknown }
  return code.doubleValue == 200 ? .accepted : .rejected
 }
}
