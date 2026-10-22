import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class NotificationRoutingTests: XCTestCase {
    func testBubbleDoesNotRequestSystemPermissionAndHiddenDoesNotMarkShown() {
        let defaults = UserDefaults(suiteName: "BubbleRouting.\(UUID())")!
        let router = AppNotificationRouter(defaults: defaults)
        var displayed = 0, shown = 0
        router.presentBubble = { _ in displayed += 1; return true }
        let m = ExperienceNotification(id: "hidden", kind: .recovery, epoch: "a", title: "Restored", body: "100%", createdAt: Date())
        router.enqueue(m, valid: { true }, failed: { XCTFail() }, shown: { shown += 1 })
        XCTAssertEqual(shown, 0); XCTAssertEqual(displayed, 0)
        router.updateEnvironment(canPresent: true)
        XCTAssertEqual(displayed, 0, "Hidden arrival remains unread, no automatic replay")
        XCTAssertEqual(router.unread.count, 1)
        router.enqueue(ExperienceNotification(id: "visible", kind: .recovery, epoch: "a", title: "Restored", body: "100%", createdAt: Date()), valid: { true }, failed: { XCTFail() }, shown: { shown += 1 })
        XCTAssertEqual(displayed, 1); XCTAssertEqual(shown, 1)
        router.cancelAuthenticationEpoch("a"); XCTAssertTrue(router.unread.isEmpty)
        router.stop()
    }
    func testBothChannelsHaveOneReceiptAndStaleActionCannotOpenNewAccount() {
        let defaults = UserDefaults(suiteName: "BubbleBoth.\(UUID())")!
        let router = AppNotificationRouter(defaults: defaults)
        router.configure(NotificationPresentationPreferences(mode: .both))
        var systemCompletion: ((Bool) -> Void)?, receipt = 0, valid = true, opened = 0
        router.sendSystem = { _, done in systemCompletion = done }
        router.presentBubble = { _ in true }; router.openDetails = { opened += 1 }
        router.updateEnvironment(canPresent: true)
        let m = ExperienceNotification(id: "both", kind: .recovery, epoch: "a", title: "Restored", body: "100%", createdAt: Date())
        router.enqueue(m, valid: { valid }, failed: {}, shown: { receipt += 1 })
        systemCompletion?(true); XCTAssertEqual(receipt, 1)
        valid = false; router.activate(id: m.id); XCTAssertEqual(opened, 0)
        router.cancelAuthenticationEpoch("a"); systemCompletion?(true); XCTAssertEqual(receipt, 1)
        router.stop()
    }
}
