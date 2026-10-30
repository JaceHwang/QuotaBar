import Foundation
import XCTest
@testable import QuotaCore
final class MessageCenterTests: XCTestCase {
    private func path() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("messages-\(UUID())/message-center.json") }
    private func row(_ id: String, at: Int64 = 1_900_000_000_000, generation: String = "initial", epoch: String? = "one", channels: Set<NotificationChannel> = [.bubble]) -> MessageCenterRecord {
        MessageCenterRecord(key: MessageCenterKey(id: id, generation: generation, epoch: epoch), category: .quotaLow, title: "Quota low", body: "15% snapshot", createdAtMilliseconds: at, channels: channels)
    }
    func testSharedContractRoundTripAndImmutableSnapshots() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("contracts/notifications/message-center-cases.json")
        let data = try Data(contentsOf: fixture), url = path(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url)
        let store = MessageCenterStore(url: url)
        XCTAssertNil(store.error); XCTAssertEqual(store.records.count, 3); XCTAssertEqual(store.unreadCount, 2)
        let original = store.records.first { $0.key.id == "low" }!
        var duplicate = original; duplicate.body = "new current value must not replace snapshot"; duplicate.channels = [.mobile]
        XCTAssertTrue(store.append(duplicate)); XCTAssertEqual(store.records.count, 3)
        let kept = store.records.first { $0.key.id == "low" }!
        XCTAssertEqual(kept.body, original.body); XCTAssertEqual(kept.channels, [.bubble,.system,.mobile]); XCTAssertEqual(kept.readAtMilliseconds, original.readAtMilliseconds)
        XCTAssertTrue(store.markAllRead(atMilliseconds: 1_900_000_010_000)); XCTAssertEqual(MessageCenterStore(url: url).unreadCount, 0)
    }
    func testReadGenerationEpochAndRestartWithoutPruning() throws {
        let url = path(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MessageCenterStore(url: url)
        let a = row("one", at: 1_600_000_000_000), b = row("one", generation: "later"), c = row("one", epoch: "two")
        XCTAssertTrue(store.append([a,b,c])); XCTAssertEqual(store.unreadCount, 3)
        XCTAssertTrue(store.markRead(a.key, atMilliseconds: 1_900_000_000_001)); XCTAssertEqual(store.unreadCount, 2)
        XCTAssertTrue(store.append(a)); XCTAssertEqual(store.unreadCount, 2)
        let reopened = MessageCenterStore(url: url); XCTAssertEqual(reopened.records.count, 3); XCTAssertEqual(reopened.unreadCount, 2)
        XCTAssertEqual(reopened.records.last?.key, a.key); XCTAssertNotNil(reopened.records.last?.readAtMilliseconds)
    }
    func testCorruptFileIsNotOverwrittenAndPendingMergesAfterRetry() throws {
        let url = path(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("{broken history".utf8); try corrupt.write(to: url)
        let store = MessageCenterStore(url: url), new = row("new")
        XCTAssertNotNil(store.error); XCTAssertFalse(store.append(new)); XCTAssertTrue(store.hasUnpersistedMessages)
        XCTAssertFalse(store.markRead(new.key, atMilliseconds: 1_900_000_001_000)); XCTAssertEqual(store.unreadCount, 1)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        try Data(#"{"schema":1,"messages":[]}"#.utf8).write(to: url)
        XCTAssertTrue(store.reload()); XCTAssertNil(store.error); XCTAssertFalse(store.hasUnpersistedMessages)
        XCTAssertEqual(MessageCenterStore(url: url).unreadCount, 1)
    }
    func testSaveFailureDoesNotClaimReadAndReloadPreservesDiskRecords() throws {
        let url = path(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MessageCenterStore(url: url), old = row("old")
        XCTAssertTrue(store.append(old)); let original = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertFalse(store.markRead(old.key, atMilliseconds: 1_900_000_001_000)); XCTAssertEqual(store.unreadCount, 1)
        XCTAssertFalse(store.append(row("new"))); XCTAssertEqual(store.records.count, 2); XCTAssertTrue(store.hasUnpersistedMessages)
        try FileManager.default.removeItem(at: url); try original.write(to: url)
        XCTAssertTrue(store.reload()); XCTAssertEqual(store.unreadCount, 2)
        XCTAssertTrue(store.markAllRead(atMilliseconds: 1_900_000_001_000)); XCTAssertEqual(MessageCenterStore(url: url).unreadCount, 0)
    }
    func testTenThousandRecordsSurviveAndFutureSchemaRemainsUntouched() throws {
        let url = path(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MessageCenterStore(url: url)
        XCTAssertTrue(store.append((0..<10_000).map { row(String($0), at: 1_600_000_000_000 + Int64($0)) }))
        XCTAssertEqual(MessageCenterStore(url: url).records.count, 10_000)
        XCTAssertTrue(store.markAllRead(atMilliseconds: 1_900_000_000_000)); XCTAssertEqual(MessageCenterStore(url: url).unreadCount, 0)
        let future = Data(#"{"schema":999,"messages":[]}"#.utf8); try future.write(to: url)
        let blocked = MessageCenterStore(url: url); XCTAssertNotNil(blocked.error); XCTAssertFalse(blocked.append(row("held")))
        XCTAssertEqual(try Data(contentsOf: url), future)
    }
}
