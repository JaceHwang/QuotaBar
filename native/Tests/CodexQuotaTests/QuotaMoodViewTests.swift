import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota
@MainActor final class QuotaMoodViewTests: XCTestCase {
    func testCelebrationVisibilityCancellationAndIndependentMood() {
        let button = FloatingQuotaButton()
        defer { button.hide() }
        button.celebrate()
        XCTAssertFalse(button.isCelebrating)
        button.show(summary: nil, theme: .light, tooltip: "", fallback: "example", dimmed: false)
        button.setExperience(mood: .low, enabled: false)
        button.celebrate()
        XCTAssertTrue(button.isCelebrating)
        XCTAssertFalse(button.moodEnabled)
        let frame = button.frame
        button.interaction.onDragBegan?()
        XCTAssertFalse(button.isCelebrating)
        XCTAssertEqual(frame, button.frame)
        button.celebrate(); button.hide()
        XCTAssertFalse(button.isCelebrating)
    }
    func testMoodStatesRenderInBothThemesWithoutTakingMouseHits() throws {
        let view = QuotaMoodView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)))
        let directory = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"]
        for dark in [false,true] {
            for mood in [QuotaMood.good,.low,.exhausted,.unavailable,.recovered] {
                view.mood = mood; view.dark = dark
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                XCTAssertGreaterThan(rep.pixelsWide, 0)
                if let directory {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("mood-\(dark)-\(mood.rawValue).png"))
                }
            }
        }
    }
    func testDefaultRemindersRequestPermissionButSavedOptOutDoesNot() throws {
        let name = "QuotaExperiencePermission.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        var requests = 0
        let request: (@escaping (String) -> Void) -> Void = { completion in requests += 1; completion("denied") }
        let fresh = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: request)
        XCTAssertEqual(requests, 1)
        let view = fresh.makeSettingsView() as! NSStackView
        XCTAssertTrue(view.arrangedSubviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Notifications unavailable") })
        defaults.set(try JSONEncoder().encode(QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: false)), forKey: "experience.preferences")
        let saved = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: request)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(saved.preferences, QuotaExperiencePreferences(moods: false, recovery: false, celebration: false, bank: false))
    }
    func testSettingsStartEnabledAndOptOutPersistsIndependently() throws {
        let name = "QuotaExperienceSettings.\(UUID())", defaults = UserDefaults(suiteName: "QuotaExperienceSettings.temporary")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: "QuotaExperienceSettings.temporary"); try? FileManager.default.removeItem(at: root) }
        let c = QuotaExperienceController(root: root, defaults: defaults, language: { .simplifiedChinese })
        let view = c.makeSettingsView() as! NSStackView
        let buttons = descendants(view).compactMap { $0 as? QuotaSettingsSwitch }
        XCTAssertEqual(buttons.count, 4); XCTAssertTrue(buttons.allSatisfy { $0.state == .on })
        buttons[0].state = .off; NSApp.sendAction(buttons[0].action!, to: buttons[0].target, from: buttons[0])
        XCTAssertFalse(c.preferences.moods); XCTAssertTrue(c.preferences.recovery); XCTAssertTrue(c.preferences.celebration); XCTAssertTrue(c.preferences.bank)
        let reopened = QuotaExperienceController(root: root, defaults: defaults, language: { .english })
        XCTAssertFalse(reopened.preferences.moods)
    }

    func testMoodIconLargerWithoutOverlappingText() throws {
        let button = FloatingQuotaButton(); defer { button.hide() }
        button.setExperience(mood: .good, enabled: true)
        button.show(summary: nil, theme: .light, tooltip: "", fallback: "5h 80%", dimmed: false)
        let mood = try XCTUnwrap(button.interaction.subviews.compactMap { $0 as? QuotaMoodView }.first)
        let label = try XCTUnwrap(button.interaction.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(mood.frame.height, 28)
        XCTAssertLessThanOrEqual(mood.frame.maxX + 3, label.frame.minX)
        XCTAssertEqual(button.frame?.height, 30)
    }
    func testRecoveredCharacterDiffersFromGoodWithoutSparkles() throws {
        let view = QuotaMoodView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        func pixels(_ mood: QuotaMood) throws -> Data {
            view.mood = mood; view.stars = false
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        XCTAssertNotEqual(try pixels(.good), try pixels(.recovered))
    }
    func testSidebarSwitchesPagesAndPreservesControls() throws {
        let pages = (0..<4).map { index in QuotaSettingsPage(title: "Page \(index)", symbol: "gearshape", content: NSTextField(labelWithString: "content \(index)")) }
        let shell = QuotaSettingsShellView(pages: pages, version: "1.0.1")
        XCTAssertEqual(shell.selectedPage, 2)
        shell.selectPage(0); XCTAssertEqual(shell.selectedPage, 0)
        shell.selectPage(2); XCTAssertEqual(shell.selectedPage, 2)
        XCTAssertEqual(descendants(shell).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.hasPrefix("settings.nav.") == true }.count, 4)
    }
    func testApprovedBSettingsRenderAndKeepFiveLegendStatesVisible() throws {
        let name = "QuotaSettingsB.\(UUID())", defaults = UserDefaults(suiteName: "QuotaSettingsB.temporary")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: "QuotaSettingsB.temporary"); try? FileManager.default.removeItem(at: root) }
        for language in [CodexDisplayLanguage.simplifiedChinese, .traditionalChinese, .english] {
        defaults.set(language.rawValue, forKey: "standalone.language")
        let experience = QuotaExperienceController(root: root, defaults: defaults, language: { language }, requestPermission: { $0("") })
        let coordinator = StandaloneCoordinator(experienceController: experience, defaults: defaults, root: root)
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        window.orderFront(nil); window.contentView?.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(window.contentView)
        XCTAssertEqual(descendants(content).compactMap { $0 as? QuotaSettingsSwitch }.filter { $0.identifier == nil }.count, 4)
        let moods = descendants(content).compactMap { $0 as? QuotaMoodView }
        XCTAssertEqual(moods.filter { $0.identifier?.rawValue.hasPrefix("settings.mood.") == true }.count, 5)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance); content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
            if let directory = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                window.appearance?.performAsCurrentDrawingAppearance { content.cacheDisplay(in: content.bounds, to: bitmap) }
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-b-\(language.rawValue)-\(name).png"))
            }
        }
        }
    }
    func testDuplicatePreferencesStayInSyncAcrossSidebarPages() throws {
        let name = "QuotaSettingsSync.\(UUID())", defaults = UserDefaults(suiteName: "QuotaSettingsSync.temporary")!
        defaults.set(false, forKey: "standalone.floating.enabled")
        defer { defaults.removePersistentDomain(forName: "QuotaSettingsSync.temporary") }
        let coordinator = StandaloneCoordinator(defaults: defaults, root: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
        let summaryToggle = try XCTUnwrap(descendants(shell).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.identifier?.rawValue == "settings.general.1" })
        summaryToggle.performClick(nil)
        shell.selectPage(1)
        let displayToggle = try XCTUnwrap(descendants(shell).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.identifier?.rawValue == "settings.general.1" })
        XCTAssertEqual(displayToggle.state, .off)
        displayToggle.performClick(nil)
        shell.selectPage(2); XCTAssertEqual(summaryToggle.state, .on)
    }
    func testAccountSummaryUpdatesWithoutReopeningSettings() throws {
        let suite = "QuotaAccountSummary.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "standalone.floating.enabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = StandaloneCoordinator(defaults: defaults, root: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        coordinator.receive(.identity(AccountIdentity(displayName: "Example account")))
        XCTAssertTrue(descendants(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Example account") })
        coordinator.receive(.loggedOut)
        XCTAssertFalse(descendants(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Example account") })
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
}
