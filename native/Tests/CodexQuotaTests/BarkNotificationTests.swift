import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class BarkNotificationTests: XCTestCase {
    final class Secrets: BarkSecretStore {
        var key: String?; var fails = false; var reads = 0
        func read() throws -> String? { reads += 1; return key }
        func save(_ key: String) throws { if fails { throw BarkSecretError.unavailable }; self.key = key }
        func clear() throws { if fails { throw BarkSecretError.unavailable }; key = nil }
    }
    final class Transport: BarkPushTransport {
        var sends = 0
        func send(_ payload: Data) async -> BarkResponse { sends += 1; return .accepted }
    }
    func controller() -> (BarkNotificationController, Secrets, Transport) {
        let secrets = Secrets(), transport = Transport()
        let defaults = UserDefaults(suiteName: "BarkTests.\(UUID())")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("receipts.json")
        return (BarkNotificationController(defaults: defaults, secrets: secrets, transport: transport, deliveries: BarkDeliveryStore(url: url)), secrets, transport)
    }

    func testCorruptReceiptsPauseAutomaticPushUntilExplicitReenable() throws {
        let defaults=UserDefaults(suiteName:"BarkCorrupt.\(UUID())")!, secrets=Secrets(), transport=Transport()
        secrets.key="fake-key"; defaults.set(try JSONEncoder().encode(BarkPreferences(enabled:true)),forKey:"bark.preferences")
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:url) }
        try Data("broken".utf8).write(to:url)
        let c=BarkNotificationController(defaults:defaults,secrets:secrets,transport:transport,deliveries:BarkDeliveryStore(url:url)); defer { c.stop() }
        XCTAssertFalse(c.preferences.enabled)
    }

    func testRestartDuplicateSuppressionDoesNotReportCapacityFailure() async {
        let secrets=Secrets(), transport=Transport(), defaults=UserDefaults(suiteName:"BarkDuplicate.\(UUID())")!
        secrets.key="fake-key"; defaults.set(try! JSONEncoder().encode(BarkPreferences(enabled:true)),forKey:"bark.preferences")
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:url) }
        let store=BarkDeliveryStore(url:url); XCTAssertTrue(store.reserve(identity:BarkEventIdentity(id:"attempted"),now:Date()))
        let c=BarkNotificationController(defaults:defaults,secrets:secrets,transport:transport,deliveries:BarkDeliveryStore(url:url)); defer { c.stop() }
        c.enqueue(ExperienceNotification(id:"attempted",kind:.update,epoch:nil,title:"Update",body:"",createdAt:Date()),valid:{true},accepted:{})
        await c.waitUntilIdle(); XCTAssertEqual(transport.sends,0); XCTAssertEqual(c.status,.configured)
    }
    func testUnconfiguredCannotEnableAndSaveDoesNotEnableOrSend() async {
        let (c, s, t) = controller(); defer { c.stop() }
        XCTAssertFalse(c.setEnabled(true)); XCTAssertFalse(c.preferences.enabled)
        XCTAssertTrue(c.saveKey("fake-device-key")); XCTAssertFalse(c.preferences.enabled)
        XCTAssertEqual(s.key, "fake-device-key"); XCTAssertEqual(t.sends, 0)
    }
    func testDesktopOffStillSendsAndPreviewIsExcluded() async {
        let (c, _, t) = controller(); defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-device-key")); XCTAssertTrue(c.setEnabled(true))
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "BarkRouter.\(UUID())")!); defer { router.stop() }
        router.bark = c; router.configure(NotificationPresentationPreferences(mode: .off))
        var shown = 0
        router.enqueue(ExperienceNotification(id: "real", kind: .recovery, epoch: "a", title: "Restored", body: "100%", createdAt: Date()), valid: { true }, failed: {}, shown: { shown += 1 })
        router.enqueue(ExperienceNotification(id: "preview-x", kind: .test, epoch: nil, title: "Example", body: "", createdAt: Date()), valid: { true }, failed: {})
        await c.waitUntilIdle()
        XCTAssertEqual(t.sends, 1); XCTAssertEqual(shown, 1); XCTAssertTrue(router.unread.isEmpty)
    }
    func testFailedSaveRetainsConfigurationAndClearDisables() {
        let (c, s, _) = controller(); defer { c.stop() }
        XCTAssertTrue(c.saveKey("first-key")); XCTAssertTrue(c.setEnabled(true))
        let generation = c.preferences.configurationGeneration
        s.fails = true; XCTAssertFalse(c.saveKey("second-key"))
        XCTAssertEqual(s.key, "first-key"); XCTAssertTrue(c.preferences.enabled); XCTAssertEqual(c.preferences.configurationGeneration, generation)
        s.fails = false; XCTAssertTrue(c.clearKey()); XCTAssertFalse(c.preferences.enabled); XCTAssertNil(s.key)
    }
    func testEnableDoesNotReplayKnownEventsAndExplicitTestWorksWhileOff() async {
        let (c, _, t) = controller(); defer { c.stop() }
        let message = ExperienceNotification(id: "known", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date())
        c.enqueue(message, valid: { true }, accepted: {})
        XCTAssertTrue(c.saveKey("fake-key")); XCTAssertTrue(c.setEnabled(true))
        c.enqueue(message, valid: { true }, accepted: {})
        await c.waitUntilIdle(); XCTAssertEqual(t.sends, 0)
        XCTAssertTrue(c.setEnabled(false)); c.sendTest(title: "Example", body: "Example")
        await c.waitUntilIdle(); XCTAssertEqual(t.sends, 1); XCTAssertFalse(c.preferences.enabled)
    }
    func testClearFailureStillDisablesAutomaticPush() {
        let (c, s, _) = controller(); defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-key")); XCTAssertTrue(c.setEnabled(true))
        s.fails = true; XCTAssertFalse(c.clearKey()); XCTAssertFalse(c.preferences.enabled)
    }
    final class HeldTransport: BarkPushTransport {
        var payloads: [Data] = []; var completions: [CheckedContinuation<BarkResponse, Never>] = []
        func send(_ payload: Data) async -> BarkResponse {
            payloads.append(payload)
            return await withCheckedContinuation { completions.append($0) }
        }
        func complete(_ result: BarkResponse = .accepted) { completions.removeFirst().resume(returning: result) }
    }
    func testTestRequestSharesSerialQueueWithAutomaticRequests() async {
        let s = Secrets(), t = HeldTransport()
        let c = BarkNotificationController(defaults: UserDefaults(suiteName: "BarkSerial.\(UUID())")!, secrets: s, transport: t, deliveries: BarkDeliveryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-key")); XCTAssertTrue(c.setEnabled(true))
        c.enqueue(ExperienceNotification(id: "automatic", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date()), valid: { true }, accepted: {})
        for _ in 0..<10 { await Task.yield() }
        c.sendTest(title: "Example", body: "Example")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(t.payloads.count, 1)
        t.complete(); for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(t.payloads.count, 2); t.complete(); await c.waitUntilIdle()
    }

    func testBothArrivalOrdersKeepOneSemanticReceiptAndDesktopUnread() async {
        for mobileFirst in [false, true] {
            let (c, _, t) = controller(); defer { c.stop() }
            XCTAssertTrue(c.saveKey("fake-key")); XCTAssertTrue(c.setEnabled(true))
            let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "BarkBoth.\(UUID())")!); defer { router.stop() }
            router.bark = c; router.configure(NotificationPresentationPreferences(mode: .both))
            var system: ((Bool) -> Void)?, shown = 0
            router.sendSystem = { _, done in system = done }
            router.updateEnvironment(canPresent: false)
            router.enqueue(ExperienceNotification(id: "both", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date()), valid: { true }, failed: {}, shown: { shown += 1 })
            if mobileFirst { await c.waitUntilIdle(); system?(true) } else { system?(true); await c.waitUntilIdle() }
            XCTAssertEqual(shown, 1); XCTAssertEqual(t.sends, 1); XCTAssertEqual(router.unread.count, 1)
        }
    }
    func testCancellationDoesNotStrandUnrelatedUpdateAndOldCompletionCannotAlterNewConfiguration() async {
        let s = Secrets(), t = HeldTransport()
        let c = BarkNotificationController(defaults: UserDefaults(suiteName: "BarkCancel.\(UUID())")!, secrets: s, transport: t, deliveries: BarkDeliveryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        defer { c.stop() }
        XCTAssertTrue(c.saveKey("first-key")); XCTAssertTrue(c.setEnabled(true))
        var receipts = 0
        c.enqueue(ExperienceNotification(id: "account", kind: .recovery, epoch: "old", title: "Recovery", body: "", createdAt: Date()), valid: { true }, accepted: { receipts += 1 })
        c.enqueue(ExperienceNotification(id: "update", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date()), valid: { true }, accepted: { receipts += 1 })
        for _ in 0..<10 { await Task.yield() }
        c.cancel(epoch: "old"); for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(t.payloads.count, 2)
        t.complete(); for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(receipts, 0)
        t.complete(); await c.waitUntilIdle(); XCTAssertEqual(receipts, 1)
        c.enqueue(ExperienceNotification(id: "late", kind: .update, epoch: nil, title: "Old Key", body: "", createdAt: Date()), valid: { true }, accepted: { receipts += 1 })
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(c.saveKey("second-key")); t.complete(); for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(receipts, 1); XCTAssertEqual(c.status, .configured)
    }
    func testQueueAdmissionIsBoundedAndExpiredWaitingRecoveryIsDropped() async {
        let s = Secrets(), t = HeldTransport(); var now = Date()
        let c = BarkNotificationController(defaults: UserDefaults(suiteName: "BarkQueue.\(UUID())")!, secrets: s, transport: t, deliveries: BarkDeliveryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), now: { now })
        defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-key")); XCTAssertTrue(c.setEnabled(true))
        for n in 0..<40 { c.enqueue(ExperienceNotification(id: "r\(n)", kind: .recovery, epoch: "a", title: "Recovery", body: "", createdAt: now), valid: { true }, accepted: {}) }
        for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(t.payloads.count, 1)
        now = now.addingTimeInterval(301); t.complete(); await c.waitUntilIdle(); XCTAssertEqual(t.payloads.count, 1)
        XCTAssertTrue(c.setEnabled(false)); XCTAssertTrue(c.setEnabled(true))
        for n in 0..<40 { c.enqueue(ExperienceNotification(id: "u\(n)", kind: .update, epoch: nil, title: "Update", body: "", createdAt: now), valid: { true }, accepted: {}) }
        for _ in 0..<10 { await Task.yield() }
        for _ in 0..<32 { t.complete(); for _ in 0..<10 { await Task.yield() } }
        await c.waitUntilIdle(); XCTAssertEqual(t.payloads.count, 33)
    }
    func testReminderGenerationAllowsExplicitRearmButKeyChangeDoesNotReplay() async {
        let (c, _, t) = controller(); defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-key")); XCTAssertTrue(c.setEnabled(true))
        func event(_ generation: String) -> ExperienceNotification { ExperienceNotification(id: "version", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date(), reminderGeneration: generation) }
        c.enqueue(event("initial"), valid: { true }, accepted: {}); await c.waitUntilIdle()
        XCTAssertTrue(c.saveKey("replacement-key")); c.enqueue(event("initial"), valid: { true }, accepted: {})
        c.enqueue(event("snooze:1234"), valid: { true }, accepted: {}); await c.waitUntilIdle()
        XCTAssertEqual(t.sends, 2)
    }
    func testSettingsDraftSurvivesRebuildWithoutSecretReadbackAndFifthPageAppends() throws {
        let (c, s, _) = controller(); defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-key")); let initialReads = s.reads
        let view = BarkSettingsView(controller: c, text: { en, _, _ in en })
        XCTAssertEqual(view.keyField.stringValue, "")
        view.keyField.stringValue = "unsaved-draft"; view.controlTextDidChange(Notification(name: NSText.didChangeNotification))
        let rebuilt = BarkSettingsView(controller: c, text: { en, _, _ in en })
        XCTAssertEqual(rebuilt.keyField.stringValue, "unsaved-draft"); XCTAssertEqual(s.reads, initialReads)
        let coordinator = StandaloneCoordinator(barkController: c, defaults: UserDefaults(suiteName: "BarkSettings.\(UUID())")!, root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
        XCTAssertEqual(shell.pageContents.count, 5); shell.selectPage(4); XCTAssertEqual(shell.selectedPage, 4); shell.selectPage(3); XCTAssertEqual(shell.selectedPage, 3)
    }

    func testSuppressionPersistsAcrossRestartBeforeOldEventReturns() async {
        let secrets = Secrets(), transport = Transport()
        let defaults = UserDefaults(suiteName: "BarkRestart.\(UUID())")!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let identity = BarkEventIdentity(id: "current-update")
        let first = BarkNotificationController(defaults: defaults, secrets: secrets, transport: transport, deliveries: BarkDeliveryStore(url: url))
        XCTAssertTrue(first.saveKey("fake-key")); first.suppress([identity]); XCTAssertTrue(first.setEnabled(true)); first.stop()
        let second = BarkNotificationController(defaults: defaults, secrets: secrets, transport: transport, deliveries: BarkDeliveryStore(url: url)); defer { second.stop() }
        second.enqueue(ExperienceNotification(id: "current-update", kind: .update, epoch: nil, title: "Update", body: "", createdAt: Date()), valid: { true }, accepted: {})
        await second.waitUntilIdle(); XCTAssertEqual(transport.sends, 0)
    }

    func testEnablingRechecksSecretExistence() {
        let (c, s, _) = controller(); defer { c.stop() }
        XCTAssertTrue(c.saveKey("fake-key")); s.key = nil
        XCTAssertFalse(c.setEnabled(true)); XCTAssertFalse(c.preferences.enabled)
    }

}
