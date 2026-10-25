import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class NotificationSettingsTests: XCTestCase {
    func testChannelsPauseAndPreviewDoNotChangeEventPreferences() throws {
        let suite = "NotificationSettings.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = AppNotificationRouter(defaults: defaults)
        var previews = 0, enabled = 0
        let view = NotificationSettingsView(router: router, language: .english, floatingVisible: false, preview: { previews += 1 }, showUnread: {}, enableFloating: { enabled += 1 })
        let all = tree(view)
        let picker = try XCTUnwrap(all.compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertEqual(picker.numberOfItems, 4); XCTAssertEqual(picker.indexOfSelectedItem, 0)
        picker.selectItem(at: 3); NSApp.sendAction(picker.action!, to: picker.target, from: picker)
        XCTAssertEqual(router.preferences.mode, .off)
        let pause = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "notification.pause" })
        pause.performClick(nil); XCTAssertTrue(router.preferences.paused(now: Date()))
        pause.performClick(nil); XCTAssertFalse(router.preferences.paused(now: Date()))
        let enable = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.title == "Enable floating button" }); enable.performClick(nil)
        XCTAssertEqual(enabled, 1); XCTAssertEqual(previews, 0)
        XCTAssertNil(defaults.object(forKey: "experience.preferences")); XCTAssertNil(defaults.object(forKey: "updates.policy"))
        router.stop()
    }
    func testMatrixHasEighteenIndependentCellsAndThreshold() throws {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixUI.\(UUID())")!); defer { router.stop() }
        XCTAssertTrue(router.configurePolicy(NotificationPolicyPreferences()))
        var tests = 0
        let view = NotificationSettingsView(router: router, language: .simplifiedChinese, floatingVisible: true, preview: {}, showUnread: {}, enableFloating: {}, test: { tests += 1 })
        let buttons = tree(view).compactMap { $0 as? NSButton }
        let testButton = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.test" })
        testButton.performClick(nil); XCTAssertEqual(tests, 1)
        let matrix = try XCTUnwrap(tree(view).compactMap { $0 as? NotificationMatrixSettingsView }.first)
        let gridCard = try XCTUnwrap(matrix.arrangedSubviews.first { tree($0).contains { $0 is NSGridView } })
        XCTAssertEqual(matrix.arrangedSubviews.firstIndex(of: testButton), matrix.arrangedSubviews.firstIndex(of: gridCard).map { $0 + 1 })
        XCTAssertEqual(buttons.filter { $0.identifier?.rawValue.hasPrefix("notification.rule.") == true }.count, 18)
        let low = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.rule.quotaLow.bubble" })
        low.performClick(nil)
        XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        XCTAssertFalse(router.policyPreferences.rules[.quotaLow]?.contains(.mobile) == true)
        let master = try XCTUnwrap(tree(view).compactMap { $0 as? NSSwitch }.first { $0.identifier?.rawValue == "notification.master.bubble" })
        master.state = .off; NSApp.sendAction(master.action!, to: master.target, from: master)
        XCTAssertFalse(router.policyPreferences.enabledChannels.contains(.bubble))
        XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        XCTAssertFalse(low.isEnabled)
        low.performClick(nil)
        XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        master.state = .on; NSApp.sendAction(master.action!, to: master.target, from: master)
        XCTAssertTrue(low.isEnabled); XCTAssertEqual(low.state, .on)
        let threshold = try XCTUnwrap(tree(view).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "notification.threshold" })
        threshold.selectItem(at: 2); NSApp.sendAction(threshold.action!, to: threshold.target, from: threshold)
        XCTAssertEqual(router.policyPreferences.lowRemainingThreshold, 30)
        XCTAssertFalse(low.accessibilityLabel()?.isEmpty ?? true)
    }
    func testExampleUsesChannelMastersInsteadOfLegacyModeOrCategoryRules() {
        let defaults = UserDefaults(suiteName: "MatrixTestRoute.\(UUID())")!
        let router = AppNotificationRouter(defaults: defaults); defer { router.stop() }
        var old = router.preferences; old.mode = .off; router.configure(old)
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.system]; p.rules = [:]
        XCTAssertTrue(router.configurePolicy(p))
        var system = 0, bubbles = 0
        router.sendSystem = { _, done in system += 1; done(true) }
        router.presentBubble = { _ in bubbles += 1; return true }; router.updateEnvironment(canPresent: true)
        func send() { router.sendTestNotification(title: "Example", body: "Sample") }
        send(); XCTAssertEqual(system, 1); XCTAssertEqual(bubbles, 0)
        p.enabledChannels = [.bubble]; XCTAssertTrue(router.configurePolicy(p))
        send(); XCTAssertEqual(system, 1); XCTAssertEqual(bubbles, 1)
        p.enabledChannels = []; XCTAssertTrue(router.configurePolicy(p))
        old.mode = .both; router.configure(old)
        send(); XCTAssertEqual(system, 1); XCTAssertEqual(bubbles, 1)
    }
    func testMobileExampleUsesDedicatedTestAPIOnlyWhenMasterEnabled() async throws {
        let (mobile, _, transport) = BarkNotificationTests().controller()
        defer { mobile.stop() }
        XCTAssertTrue(mobile.saveKey("example-key"))
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixMobile.\(UUID())")!); defer { router.stop() }
        router.bark = mobile
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.mobile]; p.rules = [:]
        XCTAssertTrue(router.configurePolicy(p))
        router.sendTestNotification(title: "Example", body: "No account data")
        await mobile.waitUntilIdle(); XCTAssertEqual(transport.sends, 1)
        p.enabledChannels = []; XCTAssertTrue(router.configurePolicy(p))
        router.sendTestNotification(title: "Example", body: "No account data")
        await mobile.waitUntilIdle(); XCTAssertEqual(transport.sends, 1)
        XCTAssertTrue(router.unread.isEmpty)
    }
    func testControllerButtonTestsMastersAfterDeniedPermissionButCelebrationStaysLocal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (mobile, _, transport) = BarkNotificationTests().controller(); defer { mobile.stop() }
        XCTAssertTrue(mobile.saveKey("example-key"))
        let defaults = UserDefaults(suiteName: "MatrixWiring.\(UUID())")!
        let router = AppNotificationRouter(defaults: defaults); defer { router.stop() }; router.bark = mobile
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.bubble, .system, .mobile]; p.rules = [:]
        XCTAssertTrue(router.configurePolicy(p)); router.updateEnvironment(canPresent: true)
        var permissions = 0, bubbles = 0
        router.presentBubble = { _ in bubbles += 1; return true }; router.sendSystem = { _, done in done(false) }
        let controller = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: { permissions += 1; $0("denied") }, router: router)
        let view = controller.makeSettingsView()
        let buttons = tree(view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.filter { $0.title == "Send test notification" }.count, 1)
        try XCTUnwrap(buttons.first { $0.title == "Preview celebration" }).performClick(nil)
        await mobile.waitUntilIdle(); XCTAssertEqual(transport.sends, 0); XCTAssertEqual(permissions, 0)
        try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.test" }).performClick(nil)
        await mobile.waitUntilIdle(); XCTAssertEqual(transport.sends, 1); XCTAssertEqual(permissions, 1); XCTAssertGreaterThan(bubbles, 0)
    }
    func testMatrixRendersAllLanguagesAndThemesWithoutClippingControls() throws {
        for language in [CodexDisplayLanguage.simplifiedChinese, .traditionalChinese, .english] {
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixRender.\(UUID())")!); defer { router.stop() }
                XCTAssertTrue(router.configurePolicy(NotificationPolicyPreferences()))
                let view = NotificationMatrixSettingsView(router: router, language: language, preview: {}, unread: {})
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: theme); defer { window.close() }
                let host = try XCTUnwrap(window.contentView); host.wantsLayer = true; window.appearance?.performAsCurrentDrawingAppearance { host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }; view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view)
                NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18), view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18), view.topAnchor.constraint(equalTo: host.topAnchor, constant: 18)])
                window.orderFront(nil); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                for box in tree(view).compactMap({ $0 as? NSButton }).filter({ $0.identifier?.rawValue.hasPrefix("notification.rule.") == true }) {
                    XCTAssertGreaterThan(box.bounds.width, 8)
                    XCTAssertTrue(view.bounds.insetBy(dx: -1, dy: -1).contains(box.convert(box.bounds, to: view)))
                }
                for label in tree(view).compactMap({ $0 as? NSTextField }).filter({ $0.identifier?.rawValue.hasPrefix("notification.hint.") == true }) {
                    let required = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: 1000)).height ?? 0
                    XCTAssertGreaterThanOrEqual(label.bounds.height + 1, required, "\(label.identifier!.rawValue): width=\(label.bounds.width), height=\(label.bounds.height), needed=\(required)")
                }
                if let directory = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    window.appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
                    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("notification-matrix-\(language.rawValue)-\(theme.rawValue).png"))
                }
            }
        }
    }
    private func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
}
