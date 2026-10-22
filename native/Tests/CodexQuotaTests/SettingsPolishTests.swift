import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor final class SettingsPolishTests: XCTestCase {
    func testPreferencesHaveOneOwningPageAndOnePreview() throws {
        let suite = "SettingsPolish.\(UUID())", defaults = UserDefaults(suiteName: "SettingsPolish.temporary")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: "SettingsPolish.temporary"); try? FileManager.default.removeItem(at: root) }
        let experience = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: { $0("") })
        let coordinator = StandaloneCoordinator(experienceController: experience, defaults: defaults, root: root)
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
        let all = shell.pageContents.flatMap(tree)
        XCTAssertEqual(all.compactMap { $0 as? QuotaSettingsSwitch }.filter { $0.identifier?.rawValue.hasPrefix("settings.general.") == true }.count, 3)
        XCTAssertFalse(tree(shell.pageContents[2]).contains { $0.identifier?.rawValue.hasPrefix("settings.general.") == true })
        let previews = tree(shell.pageContents[2]).compactMap { $0 as? NSButton }.filter { $0.title.lowercased().contains("preview") }
        XCTAssertEqual(previews.count, 1, "The celebration has one discoverable preview action")
        XCTAssertFalse(tree(shell).compactMap { $0 as? NSButton }.contains { $0.title.contains("›") }, "No duplicate update action in sidebar")
    }
    func testReadingWidthStaysBoundedAndControlsAlignAtTrailingEdge() throws {
        let suite = "SettingsPolishLayout.\(UUID())", defaults = UserDefaults(suiteName: "SettingsPolishLayout.temporary")!
        defer { defaults.removePersistentDomain(forName: "SettingsPolishLayout.temporary") }
        let coordinator = StandaloneCoordinator(defaults: defaults, root: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
        for width in [840.0, 1400.0] {
            window.setContentSize(NSSize(width: width, height: 600)); shell.selectPage(1); shell.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(shell.subviews.compactMap { $0 as? NSScrollView }.first)
            XCTAssertLessThanOrEqual(scroll.frame.width, 640)
            let controls = tree(shell.pageContents[1]).compactMap { $0 as? QuotaSettingsSwitch }
            XCTAssertEqual(controls.count, 3)
            for control in controls {
                let rect = control.convert(control.bounds, to: shell)
                XCTAssertGreaterThan(rect.midX, scroll.frame.midX, "Switches belong to the trailing control column")
            }
        }
    }
    func testAccountActionsFollowAuthenticationState() throws {
        let suite = "SettingsAccount.\(UUID())", defaults = UserDefaults(suiteName: "SettingsAccount.temporary")!
        defaults.set("english", forKey: "standalone.language")
        defer { defaults.removePersistentDomain(forName: "SettingsAccount.temporary") }
        let coordinator = StandaloneCoordinator(defaults: defaults, root: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView); shell.selectPage(0)
        coordinator.receive(.loggedOut)
        let buttons = tree(shell.pageContents[0]).compactMap { $0 as? NSButton }
        XCTAssertFalse(try XCTUnwrap(buttons.first { $0.title == "Sign in" }).isHidden)
        XCTAssertTrue(try XCTUnwrap(buttons.first { $0.title == "Sign out" }).isHidden)
        XCTAssertTrue(try XCTUnwrap(buttons.first { $0.title == "Cancel" }).isHidden)
        coordinator.receive(.loginCompleted(true))
        coordinator.receive(.identity(AccountIdentity(displayName: "Example account")))
        XCTAssertTrue(try XCTUnwrap(buttons.first { $0.title == "Sign in" }).isHidden)
        XCTAssertFalse(try XCTUnwrap(buttons.first { $0.title == "Sign out" }).isHidden)
    }
    func testAllPagesRenderAcrossLanguagesThemesAndWindowSizes() throws {
        let suite = "SettingsPolishVisual.\(UUID())", defaults = UserDefaults(suiteName: "SettingsPolishVisual.temporary")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defaults.set(true, forKey: "updates.autoDisabled")
        defaults.set(false, forKey: "standalone.floating.enabled")
        defer { defaults.removePersistentDomain(forName: "SettingsPolishVisual.temporary"); try? FileManager.default.removeItem(at: root) }
        for language in [CodexDisplayLanguage.simplifiedChinese, .traditionalChinese, .english] {
            defaults.set(language.rawValue, forKey: "standalone.language")
            let experience = QuotaExperienceController(root: root, defaults: defaults, language: { language }, requestPermission: { $0("denied") })
            let update = QuotaUpdateController(defaults: defaults, version: "1.1.0", text: { en, zh, tw in language == .english ? en : language == .simplifiedChinese ? zh : tw })
            defer { update.stop() }
            let coordinator = StandaloneCoordinator(updateController: update, experienceController: experience, defaults: defaults, root: root)
            let window = coordinator.makeSettingsWindow(); defer { window.close() }
            coordinator.receive(.identity(AccountIdentity(displayName: "Example account")))
            coordinator.receive(.quota(AllowanceSnapshot(usedPercent: 20, remainingPercent: 80, resetsAt: Date().addingTimeInterval(3600), receivedAt: Date(), planType: "Pro")))
            let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
            for dark in [false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.makeKeyAndOrderFront(nil)
                for page in 0..<4 {
                    window.setContentSize(NSSize(width: 900, height: 650)); shell.selectPage(page); shell.layoutSubtreeIfNeeded()
                    let scroll = try XCTUnwrap(shell.subviews.compactMap { $0 as? NSScrollView }.first)
                    let document = try XCTUnwrap(scroll.documentView)
                    for control in tree(shell.pageContents[page]).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
                        let rect = control.superview!.convert(control.alignmentRect(forFrame: control.frame), to: document)
                        XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(page) \(language): control outside left edge")
                        XCTAssertLessThanOrEqual(rect.maxX, document.bounds.width + 1, "\(page) \(language): control outside right edge")
                    }
                    if let directory = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                        let bitmap = try XCTUnwrap(shell.bitmapImageRepForCachingDisplay(in: shell.bounds))
                        window.appearance?.performAsCurrentDrawingAppearance { shell.cacheDisplay(in: shell.bounds, to: bitmap) }
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("polish-\(language.rawValue)-\(dark)-page\(page).png"))
                    }
                    window.setContentSize(NSSize(width: 840, height: 560)); shell.layoutSubtreeIfNeeded()
                    for control in tree(shell.pageContents[page]).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
                        let rect = control.superview!.convert(control.alignmentRect(forFrame: control.frame), to: document)
                        XCTAssertGreaterThanOrEqual(rect.minX, -1)
                        XCTAssertLessThanOrEqual(rect.maxX, document.bounds.width + 1, "Minimum width must not clip controls")
                    }
                    document.scroll(NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentSize.height)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    let bottom = tree(shell.pageContents[page]).compactMap { $0 as? NSControl }.filter { !$0.isHiddenOrHasHiddenAncestor }.max { $0.convert($0.bounds, to: document).maxY < $1.convert($1.bounds, to: document).maxY }
                    if let bottom { XCTAssertTrue(document.visibleRect.intersects(bottom.convert(bottom.bounds, to: document)), "Last control remains reachable by scrolling") }
                }
            }
        }
    }
    func testSystemSwitchAccessibilityPressPersistsPreference() throws {
        let suite = "SettingsAccessible.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let experience = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: { $0("") })
        let content = experience.makeSettingsView()
        let toggle = try XCTUnwrap(tree(content).compactMap { $0 as? QuotaSettingsSwitch }.first)
        XCTAssertNotNil(toggle.accessibilityRole())
        XCTAssertFalse(toggle.accessibilityLabel()?.isEmpty ?? true)
        _ = toggle.accessibilityPerformPress()
        XCTAssertFalse(experience.preferences.moods)
        _ = toggle.accessibilityPerformPress()
        XCTAssertTrue(experience.preferences.moods)
    }
    func testPermissionGuidanceUsesCurrentLanguageAfterRebuilding() throws {
        let suite = "SettingsPermissionLanguage.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        var language = CodexDisplayLanguage.english
        let experience = QuotaExperienceController(root: root, defaults: defaults, language: { language }, requestPermission: { $0("denied") })
        _ = experience.makeSettingsView()
        language = .traditionalChinese
        let rebuilt = experience.makeSettingsView()
        XCTAssertTrue(tree(rebuilt).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("系統提醒不可用") })
        XCTAssertFalse(tree(rebuilt).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Notifications unavailable") })
    }
    private func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
}
