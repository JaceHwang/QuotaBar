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
        let view = NotificationSettingsView(router: router, language: .simplifiedChinese, floatingVisible: true, preview: {}, showUnread: {}, enableFloating: {})
        let buttons = tree(view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.filter { $0.identifier?.rawValue.hasPrefix("notification.rule.") == true }.count, 18)
        let low = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.rule.quotaLow.bubble" })
        low.performClick(nil)
        XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        XCTAssertFalse(router.policyPreferences.rules[.quotaLow]?.contains(.mobile) == true)
        let master = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "notification.master.bubble" })
        master.performClick(nil)
        XCTAssertFalse(router.policyPreferences.enabledChannels.contains(.bubble))
        XCTAssertTrue(router.policyPreferences.rules[.quotaLow]?.contains(.bubble) == true)
        let threshold = try XCTUnwrap(tree(view).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == "notification.threshold" })
        threshold.selectItem(at: 2); NSApp.sendAction(threshold.action!, to: threshold.target, from: threshold)
        XCTAssertEqual(router.policyPreferences.lowRemainingThreshold, 30)
        XCTAssertFalse(low.accessibilityLabel()?.isEmpty ?? true)
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
