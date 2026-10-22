import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class NotificationRoutingTests: XCTestCase {
    func testQuotaChangeHidesAllBubbleKindsButSameReadKeepsThem() {
        for kind in [ExperienceNotificationKind.recovery, .bank, .update, .test] {
            let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "Held.\(UUID())")!); defer { router.stop() }
            var hidden = 0
            router.presentBubble = { _ in true }; router.hideBubble = { hidden += 1 }
            router.updateEnvironment(canPresent: true)
            func observation(_ used: Double, _ sequence: Int) -> QuotaObservation {
                let date = Date()
                return QuotaObservation(epoch: "a", sequence: sequence, receivedAt: date, quota: AllowanceSnapshot(usedPercent: used, remainingPercent: 80, resetsAt: date.addingTimeInterval(3600), receivedAt: date))
            }
            router.observeQuota(observation(20, 1))
            router.enqueue(ExperienceNotification(id: "held", kind: kind, epoch: "a", title: "Held", body: "", createdAt: Date()), valid: { true }, failed: {})
            router.observeQuota(observation(20, 2)); router.tick(); XCTAssertEqual(hidden, 0)
            router.observeQuota(observation(21, 3)); XCTAssertEqual(hidden, 1)
        }
    }
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
    func testBothPreviewStillUsesBubbleWhenSystemPermissionDenied() throws {
        let suite = "BubbleDenied.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = AppNotificationRouter(defaults: defaults); router.configure(NotificationPresentationPreferences(mode: .both))
        var displayed = 0
        router.updateEnvironment(canPresent: true); router.presentBubble = { _ in displayed += 1; return true }; router.sendSystem = { _, done in done(false) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root); router.stop() }
        let controller = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: { $0("denied") }, router: router)
        func tree(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(tree) }
        let button = try XCTUnwrap(tree(controller.makeSettingsView()).compactMap { $0 as? NSButton }.first { $0.title == "Send test notification" })
        button.performClick(nil)
        XCTAssertEqual(displayed, 1)
        XCTAssertNil(defaults.data(forKey: "updates.policy"))
    }

    func testUpdateCanRearmAfterExplicitSnoozeCancellation() {
        let defaults = UserDefaults(suiteName: "BubbleRearm.\(UUID())")!
        let router = AppNotificationRouter(defaults: defaults); defer { router.stop() }
        var shown = 0
        router.presentBubble = { _ in true }; router.updateEnvironment(canPresent: true)
        let m = ExperienceNotification(id: "quotabar-update-9.0.0", kind: .update, epoch: nil, title: "Update", body: "notes", createdAt: Date())
        router.enqueue(m, valid: { true }, failed: {}, shown: { shown += 1 })
        router.cancelMessage(id: m.id)
        router.enqueue(m, valid: { true }, failed: {}, shown: { shown += 1 })
        XCTAssertEqual(shown, 2)
    }

    func testBothClicksConsumeActionOnlyOnce() {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "ActionOnce.\(UUID())")!); defer { router.stop() }
        var opens = 0; router.openDetails = { opens += 1 }
        let m = ExperienceNotification(id: "once", kind: .recovery, epoch: "a", title: "Restored", body: "", createdAt: Date())
        router.enqueue(m, valid: { true }, failed: {})
        router.activate(id: m.id); router.activate(id: m.id)
        XCTAssertEqual(opens, 1)
    }
    func testOldSystemCompletionCannotReceiptReusedID() {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "Generation.\(UUID())")!); defer { router.stop() }
        router.configure(NotificationPresentationPreferences(mode: .system))
        var completions: [(Bool) -> Void] = [], oldReceipts = 0, newReceipts = 0
        router.sendSystem = { _, done in completions.append(done) }
        let m = ExperienceNotification(id: "update-reused", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date())
        router.enqueue(m, valid: { true }, failed: {}, shown: { oldReceipts += 1 })
        router.cancelMessage(id: m.id)
        router.enqueue(m, valid: { true }, failed: {}, shown: { newReceipts += 1 })
        completions[0](true)
        XCTAssertEqual(oldReceipts, 0); XCTAssertEqual(newReceipts, 0)
        completions[1](true); XCTAssertEqual(newReceipts, 1)
    }

    func testFailedSystemDeliveryRearmsOnlyOnExplicitChannelChange() {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "FailureRecovery.\(UUID())")!); defer { router.stop() }
        router.configure(NotificationPresentationPreferences(mode: .system))
        var attempts = 0, bubbles = 0
        router.sendSystem = { _, done in attempts += 1; done(false) }
        router.presentBubble = { _ in bubbles += 1; return true }; router.updateEnvironment(canPresent: true)
        let m = ExperienceNotification(id: "retry-update", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date())
        router.enqueue(m, valid: { true }, failed: {})
        router.enqueue(m, valid: { true }, failed: {})
        XCTAssertEqual(attempts, 1, "No automatic failure loop")
        router.configure(NotificationPresentationPreferences(mode: .bubble))
        XCTAssertEqual(bubbles, 1, "Explicit channel change retries an undelivered event")
    }

}
