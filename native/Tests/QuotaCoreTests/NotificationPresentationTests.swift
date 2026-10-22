import Foundation
import XCTest
@testable import QuotaCore

final class NotificationPresentationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func message(_ id: String, _ kind: ExperienceNotificationKind = .recovery) -> ExperienceNotification {
        ExperienceNotification(id: id, kind: kind, epoch: kind == .update ? nil : "a", title: id, body: "body", createdAt: now)
    }
    func testPreferencesMigrationAndInvalidMode() throws {
        let p = try JSONDecoder().decode(NotificationPresentationPreferences.self, from: Data("{\"mode\":\"invalid\"}".utf8))
        XCTAssertEqual(p.mode, .bubble)
        let paused = NotificationPresentationPreferences(mode: .both, pausedUntil: now)
        XCTAssertEqual(try JSONDecoder().decode(NotificationPresentationPreferences.self, from: JSONEncoder().encode(paused)), paused)
    }
    func testPriorityFIFOAndNoDuplicateOrHiddenReplay() {
        var state = NotificationPresentationState()
        state.enqueue(message("update", .update), canPresent: true, now: now)
        state.enqueue(message("r1"), canPresent: true, now: now)
        state.enqueue(message("r2"), canPresent: true, now: now)
        state.enqueue(message("r1"), canPresent: true, now: now)
        XCTAssertEqual(state.next(canPresent: true, now: now)?.id, "r1")
        state.shown(id: "r1", now: now)
        state.dismiss(id: "r1", read: true)
        XCTAssertEqual(state.next(canPresent: true, now: now)?.id, "r2")
        state.suspend()
        state.enqueue(message("hidden"), canPresent: false, now: now)
        XCTAssertEqual(state.next(canPresent: true, now: now)?.id, "update")
        state.dismiss(id: "update", read: true)
        XCTAssertNil(state.next(canPresent: true, now: now))
        XCTAssertEqual(Set(state.unread(now: now).map(\.message.id)), Set(["r2", "hidden"]))
    }
    func testTimerPauseCancelAndExpiry() {
        var state = NotificationPresentationState()
        state.enqueue(message("r"), canPresent: true, now: now)
        _ = state.next(canPresent: true, now: now); state.shown(id: "r", now: now)
        state.setInteracting(true, now: now.addingTimeInterval(2))
        XCTAssertFalse(state.tick(now: now.addingTimeInterval(30)))
        state.setInteracting(false, now: now.addingTimeInterval(30))
        XCTAssertFalse(state.tick(now: now.addingTimeInterval(33)))
        XCTAssertTrue(state.tick(now: now.addingTimeInterval(34)))
        XCTAssertNil(state.next(canPresent: true, now: now.addingTimeInterval(34)))
        XCTAssertEqual(state.unread(now: now).count, 1)
        state.cancel(epoch: "a"); XCTAssertTrue(state.unread(now: now).isEmpty)
        state.enqueue(message("old"), canPresent: true, now: now)
        XCTAssertNil(state.next(canPresent: true, now: now.addingTimeInterval(301)))
        XCTAssertTrue(state.unread(now: now.addingTimeInterval(86401)).isEmpty)
        state.stop(); state.enqueue(message("stopped"), canPresent: true, now: now)
        XCTAssertTrue(state.unread(now: now).isEmpty)
    }
    func testCapacityAndLayout() {
        var state = NotificationPresentationState()
        for n in 0..<33 { state.enqueue(message("\(n)", .update), canPresent: false, now: now) }
        XCTAssertEqual(state.unread(now: now).count, 32)
        XCTAssertFalse(state.unread(now: now).contains { $0.message.id == "0" })
        let work = CGRect(x: -800, y: 0, width: 800, height: 600)
        let rect = NotificationBubbleLayout.place(anchor: CGRect(x: -100, y: 550, width: 90, height: 30), workArea: work, size: CGSize(width: 368, height: 150))!
        XCTAssertGreaterThanOrEqual(rect.minX, work.minX + 8)
        XCTAssertLessThanOrEqual(rect.maxX, work.maxX - 8)
        XCTAssertEqual(rect.maxY, 542)
        XCTAssertNil(NotificationBubbleLayout.place(anchor: .zero, workArea: CGRect(x: 0, y: 0, width: 200, height: 100), size: CGSize(width: 368, height: 150)))
    }
    func testSharedSequences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contracts/notifications/presentation-sequences.json"))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for row in rows {
            var state = NotificationPresentationState()
            let id = try XCTUnwrap(row["id"] as? String)
            state.enqueue(message(id), canPresent: row["visible"] as? Bool == true, now: now)
            XCTAssertEqual(state.next(canPresent: true, now: now)?.id, row["expected"] as? String)
        }
    }

}
