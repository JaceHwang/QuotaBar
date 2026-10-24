import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class NotificationRoutingTests: XCTestCase {
    func testRealPreviewSurvivesFormerTimeoutUntilQuotaChanges() throws {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "HeldWindow.\(UUID())")!)
        let bubble = CharacterNotificationBubble(); defer { router.stop(); bubble.dismiss() }
        let work = try XCTUnwrap(NSScreen.main).visibleFrame
        router.presentBubble = { bubble.show(message: $0, anchor: CGRect(x: work.midX, y: work.midY, width: 180, height: 30), dark: false, language: .english) }
        router.hideBubble = { bubble.dismiss() }; router.updateEnvironment(canPresent: true)
        func observation(_ used: Double, _ sequence: Int) -> QuotaObservation {
            let date = Date()
            return QuotaObservation(epoch: "a", sequence: sequence, receivedAt: date, quota: AllowanceSnapshot(usedPercent: used, remainingPercent: 80, resetsAt: date.addingTimeInterval(3600), receivedAt: date))
        }
        router.observeQuota(observation(20, 1))
        XCTAssertTrue(router.preview(ExperienceNotification(id: "preview-held", kind: .test, epoch: nil, title: "Example", body: "Held until quota changes", createdAt: Date())))
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        XCTAssertTrue(bubble.panel.isVisible)
        router.observeQuota(observation(20, 2)); XCTAssertTrue(bubble.panel.isVisible)
        router.observeQuota(observation(21, 3)); XCTAssertFalse(bubble.panel.isVisible)
    }
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
        XCTAssertEqual(shown, 1, "Ordinary cancellation does not create a new semantic generation")
        router.cancelMessage(id: m.id)
        let rearmed = ExperienceNotification(id: m.id, kind: .update, epoch: nil, title: m.title, body: m.body, createdAt: Date(), reminderGeneration: "snooze:1234")
        router.enqueue(rearmed, valid: { true }, failed: {}, shown: { shown += 1 })
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

    func testCategoryPolicyOverridesLegacyModeAndNeverAddsChannelsToOldEvents() {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixRouting.\(UUID())")!); defer { router.stop() }
        router.configure(NotificationPresentationPreferences(mode: .off))
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.system]; p.rules[.quotaRecovered] = [.system]
        XCTAssertTrue(router.configurePolicy(p))
        var system = 0, bubbles = 0, callbacks: [(Bool) -> Void] = [], receipts = 0
        router.sendSystem = { _, done in system += 1; callbacks.append(done) }
        router.presentBubble = { _ in bubbles += 1; return true }; router.updateEnvironment(canPresent: true)
        let m = ExperienceNotification(id: "matrix", kind: .recovery, epoch: "a", title: "r", body: "", createdAt: Date(), category: .quotaRecovered)
        router.enqueue(m, valid: { true }, failed: {}, shown: { receipts += 1 })
        XCTAssertEqual(system, 1); XCTAssertEqual(bubbles, 0)
        p.enabledChannels = [.bubble]; p.rules[.quotaRecovered] = [.bubble]
        XCTAssertTrue(router.configurePolicy(p)); callbacks[0](true)
        XCTAssertEqual(receipts, 0, "Late disabled channel cannot receipt")
        router.enqueue(m, valid: { true }, failed: {})
        XCTAssertEqual(bubbles, 0, "No adding a channel to an old event")
        router.enqueue(ExperienceNotification(id: "new", kind: .recovery, epoch: "a", title: "r", body: "", createdAt: Date(), category: .quotaRecovered), valid: { true }, failed: {})
        XCTAssertEqual(bubbles, 1)
        p.enabledChannels = []; XCTAssertTrue(router.configurePolicy(p))
        p.enabledChannels = [.bubble]; XCTAssertTrue(router.configurePolicy(p))
        XCTAssertEqual(bubbles, 1, "Reopen cannot replay suspended bubble")
    }

    func testMatrixMobileAndBubbleBothCompleteWithIndependentPolicy() async throws {
        let defaults = UserDefaults(suiteName: "MatrixMobile.\(UUID())")!
        let secrets = BarkNotificationTests.Secrets(), transport = BarkNotificationTests.Transport()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mobile = BarkNotificationController(defaults: defaults, secrets: secrets, transport: transport, deliveries: BarkDeliveryStore(url: root.appendingPathComponent("mobile.json")))
        XCTAssertTrue(mobile.saveKey("fake-key")); XCTAssertTrue(mobile.setEnabled(true))
        let router = AppNotificationRouter(defaults: defaults); router.bark = mobile; defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.bubble, .mobile]; p.rules[.quotaRecovered] = [.bubble, .mobile]
        XCTAssertTrue(router.configurePolicy(p))
        var bubbles = 0, receipts = 0
        router.presentBubble = { _ in bubbles += 1; return true }; router.updateEnvironment(canPresent: true)
        router.enqueue(ExperienceNotification(id: "both-matrix", kind: .recovery, epoch: "a", title: "x", body: "", createdAt: Date(), category: .quotaRecovered), valid: { true }, failed: {}, shown: { receipts += 1 })
        await mobile.waitUntilIdle()
        XCTAssertEqual(bubbles, 1); XCTAssertEqual(transport.sends, 1); XCTAssertEqual(receipts, 1)
    }

    func testPolicyLoadAndSaveFailurePreserveAuthority() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixStore.\(UUID())")!); defer { router.stop() }
        let legacy = LegacyNotificationPreferences(mode: .both, recovery: false, celebration: true, bank: true, updatesReminders: false, barkEnabled: true)
        XCTAssertTrue(router.loadPolicy(store: NotificationPolicyStore(url: root.appendingPathComponent("policy.json")), legacy: legacy))
        XCTAssertTrue(router.policyPreferences.rules[.quotaRecovered]?.contains(.mobile) == true)
        let before = router.policyPreferences
        try FileManager.default.removeItem(at: root); try Data().write(to: root)
        var changed = before; changed.enabledChannels = []
        XCTAssertFalse(router.configurePolicy(changed))
        XCTAssertEqual(router.policyPreferences, before)
        XCTAssertTrue(router.policyError)
    }

    func testMatrixQuotaWarningsAndInternalRecoveryIgnoreLegacyNotificationSwitches() throws {
        let defaults = UserDefaults(suiteName: "MatrixEvents.\(UUID())")!
        defaults.set(try JSONEncoder().encode(QuotaExperiencePreferences(moods: true, recovery: false, celebration: false, bank: false)), forKey: "experience.preferences")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let router = AppNotificationRouter(defaults: defaults); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.system]; p.rules = [.quotaLow: [.system], .quotaExhausted: [.system]]
        XCTAssertTrue(router.configurePolicy(p))
        var categories: [NotificationCategory] = []
        router.sendSystem = { m, done in if let c = m.category { categories.append(c) }; done(true) }
        let controller = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, router: router)
        let now = Date()
        for (i, remaining) in [30, 20, 0, 100, 100, 0].enumerated() {
            let date = now.addingTimeInterval(Double(i-5)*20)
            controller.receive(AllowanceSnapshot(usedPercent: Double(100-remaining), remainingPercent: remaining, resetsAt: now.addingTimeInterval(3600), receivedAt: date, windowDurationMins: 300, planType: "plus"), bank: .omitted)
        }
        XCTAssertEqual(categories, [.quotaLow, .quotaExhausted, .quotaExhausted])
    }

    func testClosingReopeningCategoryBetweenReadsRebaselinesImmediately() throws {
        let defaults = UserDefaults(suiteName: "MatrixReopen.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let router = AppNotificationRouter(defaults: defaults); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.system]; p.rules = [.quotaLow: [.system]]
        XCTAssertTrue(router.configurePolicy(p))
        let controller = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, router: router)
        var sends = 0; router.sendSystem = { _, done in sends += 1; done(true) }
        let now = Date()
        func q(_ remaining: Int) -> AllowanceSnapshot { AllowanceSnapshot(usedPercent: Double(100-remaining), remainingPercent: remaining, resetsAt: now.addingTimeInterval(3600), receivedAt: Date(), windowDurationMins: 300, planType: "plus") }
        controller.receive(q(30), bank: .omitted)
        p.rules[.quotaLow] = []; XCTAssertTrue(router.configurePolicy(p))
        p.rules[.quotaLow] = [.system]; XCTAssertTrue(router.configurePolicy(p))
        controller.receive(q(10), bank: .omitted)
        XCTAssertEqual(sends, 0)
    }
    func testEnablingBankAfterKnownInventoryDoesNotReplay() throws {
        for observeBefore in [true, false] {
        let defaults = UserDefaults(suiteName: "MatrixBankReopen.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let router = AppNotificationRouter(defaults: defaults); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.system]; p.rules = [:]
        XCTAssertTrue(router.configurePolicy(p))
        let controller = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, router: router)
        var sends = 0; router.sendSystem = { _, done in sends += 1; done(true) }
        let now = Date()
        let bank = BankResetSummary(availableCount: 1, credits: [BankResetCredit(status: "available", grantedAt: nil, expiresAt: now.addingTimeInterval(3600), title: nil, description: nil, id: "known")])
        func q() -> AllowanceSnapshot { AllowanceSnapshot(usedPercent: 20, remainingPercent: 80, resetsAt: now.addingTimeInterval(3600), receivedAt: Date(), windowDurationMins: 300, planType: "plus", bank: bank) }
        if observeBefore { controller.receive(q(), bank: .value) }
        p.rules[.bankExpiring24h] = [.system]; XCTAssertTrue(router.configurePolicy(p))
        controller.receive(q(), bank: .value)
        XCTAssertEqual(sends, 0)
        }
    }

    func testAcceptedCategoryCannotResendWithoutNewGeneration() {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixReceipt.\(UUID())")!); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.system]; p.rules = [.updateAvailable: [.system]]
        XCTAssertTrue(router.configurePolicy(p))
        var attempts = 0; router.sendSystem = { _, done in attempts += 1; done(true) }
        let m = ExperienceNotification(id: "update", kind: .update, epoch: nil, title: "x", body: "", createdAt: Date(), category: .updateAvailable)
        router.enqueue(m, valid: { true }, failed: {})
        router.cancelMessage(id: m.id)
        router.enqueue(m, valid: { true }, failed: {})
        XCTAssertEqual(attempts, 1)
        router.cancelMessage(id: m.id)
        router.enqueue(ExperienceNotification(id: m.id, kind: .update, epoch: nil, title: "x", body: "", createdAt: Date(), reminderGeneration: "later", category: .updateAvailable), valid: { true }, failed: {})
        XCTAssertEqual(attempts, 2)
    }

}
