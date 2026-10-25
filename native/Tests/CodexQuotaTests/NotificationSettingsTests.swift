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
    func testMatrixHasFifteenCellsAndPreservesIndependentChannelBehavior() throws {
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
        XCTAssertEqual(buttons.filter { $0.identifier?.rawValue.hasPrefix("notification.rule.") == true }.count, 15)
        XCTAssertEqual(buttons.filter { $0.identifier?.rawValue.hasPrefix("notification.selectAll.") == true }.count, 3)
        let low = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.rule.quotaLow.bubble" }); low.performClick(nil)
        XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        XCTAssertFalse(router.policyPreferences.rules[.quotaLow]?.contains(.mobile) == true)
        let master = try XCTUnwrap(tree(view).compactMap { $0 as? NSSwitch }.first { $0.identifier?.rawValue == "notification.master.bubble" })
        XCTAssertEqual(master.accessibilityLabel(), "气泡通知")
        master.state = .off; NSApp.sendAction(master.action!, to: master.target, from: master)
        XCTAssertFalse(low.isEnabled); low.performClick(nil); XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        let select = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.selectAll.bubble" }); XCTAssertFalse(select.isEnabled)
        master.state = .on; NSApp.sendAction(master.action!, to: master.target, from: master)
        XCTAssertTrue(low.isEnabled); XCTAssertEqual(low.state, .on); XCTAssertTrue(select.isEnabled)
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
    func testThresholdChipsEditAddDeleteAndInvalidPreserveSettings() throws {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "ChipUI.\(UUID())")!); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.setLowThresholds([20]); p.setBankHours([72,24]); XCTAssertTrue(router.configurePolicy(p))
        let view = NotificationMatrixSettingsView(router: router, language: .english, preview: {}, unread: {})
        func field(_ id: String) throws -> NSTextField { try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == id }) }
        func button(_ id: String) throws -> NSButton { try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id }) }
        func commit(_ field: NSTextField, _ value: String) { field.stringValue = value; NSApp.sendAction(field.action!, to: field.target, from: field) }
        commit(try field("notification.threshold.low.20"), "15"); XCTAssertEqual(router.policyPreferences.configuredLowThresholds, [15])
        try button("notification.threshold.low.add").performClick(nil)
        commit(try field("notification.threshold.low.draft"), "10"); XCTAssertEqual(router.policyPreferences.configuredLowThresholds, [15,10])
        commit(try field("notification.threshold.low.15"), "10"); XCTAssertEqual(router.policyPreferences.configuredLowThresholds, [15,10])
        commit(try field("notification.threshold.low.15"), "100"); XCTAssertEqual(router.policyPreferences.configuredLowThresholds, [15,10])
        try button("notification.threshold.low.remove.15").performClick(nil); try button("notification.threshold.low.remove.10").performClick(nil)
        XCTAssertEqual(router.policyPreferences.configuredLowThresholds, []); XCTAssertNotNil(try button("notification.threshold.low.add"))
        commit(try field("notification.threshold.bank.72"), "48"); XCTAssertEqual(router.policyPreferences.configuredBankHours, [48,24])
        XCTAssertEqual(router.policyPreferences.bankChannels(for: 48), [.bubble])
    }
    func testColumnSelectAllAndMixedBankPreserveOtherChannels() throws {
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "Columns.\(UUID())")!); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.enabledChannels = [.bubble,.system]; p.lowRemainingThreshold = 15
        p.rules[.bankExpiring72h] = [.bubble]; p.rules[.bankExpiring24h] = [.mobile]; XCTAssertTrue(router.configurePolicy(p))
        let view = NotificationMatrixSettingsView(router: router, language: .english, preview: {}, unread: {})
        let buttons = tree(view).compactMap { $0 as? NSButton }
        let bank = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.rule.bankExpiring72h.bubble" }); XCTAssertEqual(bank.state, .mixed)
        bank.performClick(nil); XCTAssertTrue(router.policyPreferences.bankChannelSelected(.bubble) == true)
        let before = router.policyPreferences
        try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.selectAll.system" }).performClick(nil)
        let after = router.policyPreferences
        XCTAssertEqual(after.enabledChannels, before.enabledChannels); XCTAssertEqual(after.configuredLowThresholds, [15])
        for category in NotificationCategory.allCases { XCTAssertTrue(after.rules[category]?.contains(.system) == true); XCTAssertEqual(after.rules[category]?.contains(.mobile), before.rules[category]?.contains(.mobile)) }
        XCTAssertEqual(after.bankChannels(for: 24), [.bubble,.mobile,.system])
    }
    func testChipFocusMovesBetweenExistingInputsAfterEdits() throws {
        for input in ["20", "18", "bad"] {
            let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "ChipFocus.\(UUID())")!); defer { router.stop() }
            var p = NotificationPolicyPreferences(); p.setLowThresholds([20,10]); XCTAssertTrue(router.configurePolicy(p))
            let view = NotificationMatrixSettingsView(router: router, language: .english, preview: {}, unread: {})
            let window = NSWindow(contentRect: NSRect(x:0,y:0,width:640,height:900),styleMask:[.titled],backing:.buffered,defer:false); window.isReleasedWhenClosed = false; defer { window.close() }
            window.contentView = view; window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
            let first = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "notification.threshold.low.20" })
            let second = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "notification.threshold.low.10" })
            window.makeFirstResponder(first); first.stringValue = input; first.currentEditor()?.string = input
            NSApp.sendAction(first.action!, to:first.target, from:first)
            window.makeFirstResponder(second)
            XCTAssertTrue(second.superview != nil)
            let editor = second.currentEditor(); XCTAssertTrue(window.firstResponder === editor)
            second.stringValue = "9"; NSApp.sendAction(second.action!, to:second.target, from:second)
            XCTAssertTrue(router.policyPreferences.configuredLowThresholds.contains(9))
        }
    }
    func testChipEscapeAndFailedSaveRetainOriginalActiveValue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName:"ChipFailure.\(UUID())")!); defer { router.stop() }
        XCTAssertTrue(router.loadPolicy(store:NotificationPolicyStore(url:root.appendingPathComponent("policy.json")),legacy:nil))
        let view = NotificationMatrixSettingsView(router:router,language:.english,preview:{},unread:{})
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:900),styleMask:[.titled],backing:.buffered,defer:false); window.isReleasedWhenClosed = false; defer { window.close() }; window.contentView = view; window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
        let first = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "notification.threshold.low.20" })
        window.makeFirstResponder(first); first.stringValue="19"; first.currentEditor()?.string="19"
        _ = first.delegate?.control?(first,textView:first.currentEditor() as? NSTextView ?? NSTextView(),doCommandBy:#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(router.policyPreferences.configuredLowThresholds,[20]); XCTAssertEqual(first.stringValue,"20")
        try FileManager.default.removeItem(at:root); try Data().write(to:root)
        first.stringValue="15"; first.currentEditor()?.string="15"; NSApp.sendAction(first.action!,to:first.target,from:first)
        XCTAssertEqual(router.policyPreferences.configuredLowThresholds,[20]); XCTAssertEqual(first.stringValue,"20"); XCTAssertEqual(first.currentEditor()?.string,"20")
    }
    func testMaximumThresholdsWrapInsideLabelColumnAndDisableAdd() throws {
        let router = AppNotificationRouter(defaults:UserDefaults(suiteName:"MaxChips.\(UUID())")!); defer { router.stop() }
        var p = NotificationPolicyPreferences(); p.setLowThresholds(Array(1...32)); p.setBankHours(Array(1...32)); XCTAssertTrue(router.configurePolicy(p))
        let view = NotificationMatrixSettingsView(router:router,language:.english,preview:{},unread:{})
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:1800),styleMask:[.titled],backing:.buffered,defer:false); window.isReleasedWhenClosed=false; defer{window.close()}; window.contentView=view; window.orderFront(nil); view.layoutSubtreeIfNeeded()
        XCTAssertEqual(tree(view).compactMap { $0 as? NSTextField }.filter { $0.identifier?.rawValue.hasPrefix("notification.threshold.") == true }.count,64)
        for button in tree(view).compactMap({$0 as?NSButton}).filter({$0.identifier?.rawValue.hasSuffix(".add")==true}) { XCTAssertFalse(button.isEnabled) }
        for chips in tree(view).compactMap({$0 as?DynamicThresholdChipsView}) {
            for child in chips.subviews { XCTAssertTrue(chips.bounds.insetBy(dx:-1,dy:-1).contains(child.frame),"\(child.frame) outside \(chips.bounds)") }
        }
    }
    func testMatrixRendersAllLanguagesAndThemesWithoutClippingControls() throws {
        for language in [CodexDisplayLanguage.simplifiedChinese, .traditionalChinese, .english] {
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MatrixRender.\(UUID())")!); defer { router.stop() }
                var p = NotificationPolicyPreferences.allSelected(); p.setLowThresholds([30,20,10]); p.setBankHours([72,24,12]); XCTAssertTrue(router.configurePolicy(p))
                let view = NotificationMatrixSettingsView(router: router, language: language, preview: {}, unread: {})
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: theme); defer { window.close() }
                let host = try XCTUnwrap(window.contentView); host.wantsLayer = true; window.appearance?.performAsCurrentDrawingAppearance { host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }; view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view)
                NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18), view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18), view.topAnchor.constraint(equalTo: host.topAnchor, constant: 18)])
                window.orderFront(nil); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                for master in tree(view).compactMap({ $0 as? NSSwitch }) {
                    let label = try XCTUnwrap(tree(master.superview!).compactMap { $0 as? NSTextField }.first { $0.stringValue == master.accessibilityLabel() })
                    let gap = master.convert(master.bounds, to: view).minX - label.convert(label.bounds, to: view).maxX
                    XCTAssertGreaterThanOrEqual(gap, 4); XCTAssertLessThanOrEqual(gap, 12)
                }
                for label in tree(view).compactMap({ $0 as? NSTextField }).filter({ $0.identifier?.rawValue.hasPrefix("notification.title.") == true }) {
                    XCTAssertGreaterThanOrEqual(label.bounds.width + 1, label.cell?.cellSize.width ?? 0, label.stringValue)
                }
                let lowName = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { ["Quota low", "额度偏低", "額度偏低"].contains($0.stringValue) })
                let numeric = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "notification.threshold.low.30" })
                XCTAssertLessThan(abs(lowName.convert(lowName.bounds, to: view).midY - numeric.convert(numeric.bounds, to: view).midY), 2)
                for field in tree(view).compactMap({ $0 as? NSTextField }).filter({ $0.identifier?.rawValue.hasPrefix("notification.threshold.") == true }) {
                    XCTAssertTrue(view.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: view)))
                }
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
