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
    private func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
}
