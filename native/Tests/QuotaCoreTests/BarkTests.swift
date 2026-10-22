import XCTest
@testable import QuotaCore
final class BarkTests: XCTestCase {
 func testMalformedPreferencesDisableOnlyBark() throws {
  let decoded=try JSONDecoder().decode(BarkPreferences.self,from:Data("{\"schema\":\"bad\",\"enabled\":true}".utf8)); XCTAssertFalse(decoded.enabled)
 }

 func testCorruptionBaselineSurvivesImmediateRestartAndExpiredCapacityCanReenable() throws {
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:dir) }; try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  let url=dir.appendingPathComponent("state"), now=Date()
  try Data("broken".utf8).write(to:url); _ = BarkDeliveryStore(url:url)
  let restarted=BarkDeliveryStore(url:url); XCTAssertTrue(restarted.needsBaseline); XCTAssertFalse(restarted.reserve(identity:BarkEventIdentity(id:"old-update"),now:now))
  XCTAssertTrue(restarted.establishBaseline(identities:[],now:now))
  for n in 0..<255 { XCTAssertTrue(restarted.reserve(identity:BarkEventIdentity(id:"event-\(n)"),now:now)) }
  XCTAssertTrue(restarted.establishBaseline(identities:[BarkEventIdentity(id:"new-current")],now:now.addingTimeInterval(31*86400)))
  XCTAssertFalse(restarted.reserve(identity:BarkEventIdentity(id:"new-current"),now:now.addingTimeInterval(31*86400)))
 }
 func testSharedFixtures() throws {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("contracts/bark/scenarios.json"))) as? [String:Any])
  for key in json["validKeys"] as! [String] { XCTAssertTrue(BarkPayload.isValidDeviceKey(key)) }
  for key in json["invalidKeys"] as! [String] { XCTAssertFalse(BarkPayload.isValidDeviceKey(key)) }
  for row in json["responses"] as! [[String:Any]] { XCTAssertEqual(String(describing:BarkResponse.classify(statusCode:row["status"] as! Int,body:Data((row["body"] as! String).utf8))),row["result"] as! String) }
 }
 func testProtectedExpiryFailureAndBaseline() throws {
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:dir) }
  let url=dir.appendingPathComponent("state"), now=Date(), live=BarkEventIdentity(id:"live")
  let store=BarkDeliveryStore(url:url); XCTAssertTrue(store.reserve(identity:live,now:now)); store.markAccepted(identity:live,now:now)
  XCTAssertTrue(store.reserve(identity:BarkEventIdentity(id:"later"),now:now.addingTimeInterval(31*86400),protected:[live]))
  XCTAssertFalse(BarkDeliveryStore(url:url).reserve(identity:live,now:now.addingTimeInterval(31*86400)))
  let blocker=dir.appendingPathComponent("file"); try Data().write(to:blocker)
  let failing=BarkDeliveryStore(url:blocker.appendingPathComponent("state")); XCTAssertFalse(failing.reserve(identity:live,now:now)); XCTAssertTrue(failing.hasPersistenceError)
  XCTAssertTrue(store.establishBaseline(identities:[BarkEventIdentity(id:"current")],now:now)); XCTAssertFalse(store.reserve(identity:BarkEventIdentity(id:"current"),now:now))
  let raw=String(decoding:try Data(contentsOf:url),as:UTF8.self); XCTAssertFalse(raw.contains("fake-key"))
 }
 func testPayloadAndResponse() throws {
  XCTAssertFalse(BarkPreferences().enabled)
  for key in ["", "https://api.day.app/key", "a b", "a?b", String(repeating:"a",count:513)] { XCTAssertFalse(BarkPayload.isValidDeviceKey(key)) }
  let data = try BarkPayload.encode(deviceKey:" fake-key ", title:"Hello", body:String(repeating:"👨‍👩‍👧‍👦中\n\"",count:1000))
  XCTAssertLessThanOrEqual(data.count,3000)
  let json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
  let unit="e\u{301}👨‍👩‍👧‍👦"; let output=try XCTUnwrap((JSONSerialization.jsonObject(with:BarkPayload.encode(deviceKey:"fake-key",title:"title",body:String(repeating:unit,count:1000))) as? [String:String])?["body"])
  XCTAssertTrue(String(repeating:unit,count:1000).hasPrefix(output)); XCTAssertFalse(output.hasSuffix("e")); XCTAssertFalse(output.hasSuffix("‍"))
  XCTAssertEqual(json.count,5)
  XCTAssertEqual(json["device_key"],"fake-key"); XCTAssertEqual(json["group"],"QuotaBar")
  XCTAssertEqual(BarkResponse.classify(statusCode:200,body:Data("{\"code\":200}".utf8)),.accepted)
  XCTAssertEqual(BarkResponse.classify(statusCode:200,body:Data("{\"code\":400}".utf8)),.rejected)
  XCTAssertEqual(BarkResponse.classify(statusCode:200,body:Data(repeating:32,count:65537)),.unknown)
 }
 func testReceiptsRestartCorruptionCapacity() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:dir) }
  let url=dir.appendingPathComponent("receipts.json"), now=Date(), id=BarkEventIdentity(id:"event")
  let store=BarkDeliveryStore(url:url); XCTAssertTrue(store.reserve(identity:id,now:now)); XCTAssertFalse(BarkDeliveryStore(url:url).reserve(identity:id,now:now))
  for i in 1..<256 { XCTAssertTrue(store.reserve(identity:BarkEventIdentity(id:"\(i)"),now:now)) }
  XCTAssertFalse(store.reserve(identity:BarkEventIdentity(id:"full"),now:now))
  try Data("broken".utf8).write(to:url)
  let broken=BarkDeliveryStore(url:url); XCTAssertTrue(broken.needsBaseline); XCTAssertFalse(broken.reserve(identity:id,now:now)); XCTAssertTrue(broken.establishBaseline(identities:[id],now:now)); XCTAssertFalse(broken.reserve(identity:id,now:now))
 }
}
