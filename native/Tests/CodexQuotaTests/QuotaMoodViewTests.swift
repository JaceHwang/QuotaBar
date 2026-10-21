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
    func testSettingsStartDisabledAndMoodsPersistIndependently() throws {
        let name = "QuotaExperienceSettings.\(UUID())", defaults = UserDefaults(suiteName: "QuotaExperienceSettings.temporary")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: "QuotaExperienceSettings.temporary"); try? FileManager.default.removeItem(at: root) }
        let c = QuotaExperienceController(root: root, defaults: defaults, language: { .simplifiedChinese })
        let view = c.makeSettingsView() as! NSStackView
        let buttons = view.arrangedSubviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 4); XCTAssertTrue(buttons.allSatisfy { $0.state == .off })
        buttons[0].performClick(nil)
        XCTAssertTrue(c.preferences.moods); XCTAssertFalse(c.preferences.recovery); XCTAssertFalse(c.preferences.celebration); XCTAssertFalse(c.preferences.bank)
        let reopened = QuotaExperienceController(root: root, defaults: defaults, language: { .english })
        XCTAssertTrue(reopened.preferences.moods)
    }

}
