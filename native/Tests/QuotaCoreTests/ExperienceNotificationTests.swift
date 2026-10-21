import Foundation
import XCTest
@testable import QuotaCore
final class ExperienceNotificationTests: XCTestCase {
    func testQueuePrioritiesExpiryAndAccountCancellation() {
        let now = Date()
        var queue = ExperienceNotificationQueue()
        queue.enqueue(ExperienceNotification(id: "update", kind: .update, epoch: nil, title: "", body: "", createdAt: now))
        queue.enqueue(ExperienceNotification(id: "old", kind: .recovery, epoch: "old", title: "", body: "", createdAt: now))
        queue.cancel(epoch: "old")
        queue.enqueue(ExperienceNotification(id: "bank", kind: .bank, epoch: "new", title: "", body: "", createdAt: now))
        XCTAssertEqual(queue.next(now: now)?.id, "bank")
        XCTAssertEqual(queue.next(now: now)?.id, "update")
        queue.enqueue(ExperienceNotification(id: "expired", kind: .recovery, epoch: "new", title: "", body: "", createdAt: now.addingTimeInterval(-301)))
        XCTAssertNil(queue.next(now: now))
    }
    func testStoreRoundTripCorruptionAndFailure() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let store = QuotaExperienceStore(url: url)
        var state = store.load(); state.receipts["test"] = BankReceipt(stage: 24, expiresAt: Date())
        try store.save(state)
        XCTAssertEqual(store.load().epoch, state.epoch)
        XCTAssertEqual(store.load().receipts["test"]?.stage, 24)
        try Data("bad".utf8).write(to: url)
        _ = store.load(); XCTAssertTrue(store.corrupted)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".corrupt") })
        let invalid = QuotaExperienceStore(url: url.appendingPathComponent("child"))
        try Data().write(to: url)
        XCTAssertThrowsError(try invalid.save(state))
    }
}
