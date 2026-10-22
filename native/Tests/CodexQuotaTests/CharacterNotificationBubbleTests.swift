import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class CharacterNotificationBubbleTests: XCTestCase {
    func testPassivePanelAndContentActionsInBothThemes() throws {
        let bubble = CharacterNotificationBubble()
        defer { bubble.dismiss() }
        XCTAssertFalse(bubble.panel.canBecomeKey)
        XCTAssertFalse(bubble.panel.canBecomeMain)
        let message = ExperienceNotification(id: "test", kind: .bank, epoch: "a", title: "Bank 权益即将到期", body: String(repeating: "已知权益将在24小时内到期。", count: 4), createdAt: Date())
        for dark in [false, true] {
            let view = bubble.content(message: message, dark: dark, language: .simplifiedChinese, width: 368)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.frame.width, 368)
            let all = tree(view)
            let actions = all.compactMap { $0 as? NSButton }
            XCTAssertEqual(actions.count, 2)
            XCTAssertTrue(actions.contains { $0.title == "查看 Bank" })
            XCTAssertTrue(actions.contains { $0.title == "知道了" })
            XCTAssertNil(all.compactMap { $0 as? QuotaMoodView }.first?.hitTest(.zero))
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: rep)
            XCTAssertNotNil(rep.representation(using: .png, properties: [:]))
        }
    }
    func testAcknowledgeAndViewAreDistinct() {
        let b = CharacterNotificationBubble(); var actions = 0, acknowledged = 0
        b.onAction = { _, _ in actions += 1 }; b.onAcknowledge = { _, _ in acknowledged += 1 }
        let m = ExperienceNotification(id: "t", kind: .recovery, epoch: "a", title: "Restored", body: "100%", createdAt: Date())
        let view = b.content(message: m, dark: false, language: .english, width: 368)
        let buttons = tree(view).compactMap { $0 as? NSButton }
        buttons.first { $0.title == "Got it" }?.performClick(nil)
        XCTAssertEqual(acknowledged, 1); XCTAssertEqual(actions, 0)
        buttons.first { $0.title == "View details" }?.performClick(nil)
        XCTAssertEqual(actions, 1)
    }
    func testRenderAllNotificationKindsAndLanguages() throws {
        guard let output = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        let bubble = CharacterNotificationBubble()
        for language in [CodexDisplayLanguage.english, .simplifiedChinese, .traditionalChinese] {
            let copy = ExperienceCopy(language)
            for dark in [false, true] {
                for kind in [ExperienceNotificationKind.recovery, .bank, .update, .test] {
                    let title = kind == .bank ? copy.text("Bank credits expiring", "Bank 权益即将到期", "Bank 權益即將到期") : copy.text("QuotaBar reminder", "QuotaBar 提醒", "QuotaBar 提醒")
                    let body = kind == .bank ? copy.text("2 known reset credits expire within 24 hours; earliest: 2026/10/23 14:00", "已知 2 次重置权益将在 24 小时内到期，最近：2026/10/23 14:00", "已知 2 次重置權益將在 24 小時內到期，最近：2026/10/23 14:00") : copy.text("5 hours remaining 100%; 7 days remaining 36%", "5 小时额度剩余 100%；7 天额度剩余 36%", "5 小時額度剩餘 100%；7 天額度剩餘 36%")
                    let message = ExperienceNotification(id: "render", kind: kind, epoch: nil, title: title, body: body, createdAt: Date())
                    let view = bubble.content(message: message, dark: dark, language: language, width: 368)
                    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: rep)
                    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("bubble-\(language.rawValue)-\(dark)-\(kind.rawValue).png"))
                }
            }
        }
    }
    func testRealPassiveWindowKeepsFocusAndFitsWorkArea() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let work = screen.visibleFrame
        let b = CharacterNotificationBubble(); defer { b.dismiss() }
        let before = NSApp.keyWindow
        let m = ExperienceNotification(id: "passive", kind: .recovery, epoch: nil, title: "Quota restored", body: "5 hours remaining 100%", createdAt: Date())
        XCTAssertTrue(b.show(message: m, anchor: CGRect(x: work.midX, y: work.midY, width: 180, height: 30), dark: false, language: .english))
        XCTAssertEqual(NSApp.keyWindow, before)
        XCTAssertTrue(work.insetBy(dx: 8, dy: 8).contains(b.panel.frame))
        b.dismiss(); XCTAssertFalse(b.panel.isVisible)
    }
    func testLateButtonRetainsItsOriginalMessageID() {
        let b = CharacterNotificationBubble(); var ids: [String] = []; b.onAction = { id, _ in ids.append(id) }
        let old = ExperienceNotification(id: "old", kind: .recovery, epoch: nil, title: "Old", body: "", createdAt: Date())
        let first = b.content(message: old, dark: false, language: .english, width: 368)
        _ = b.content(message: ExperienceNotification(id: "new", kind: .recovery, epoch: nil, title: "New", body: "", createdAt: Date()), dark: false, language: .english, width: 368)
        tree(first).compactMap { $0 as? NSButton }.first { $0.title == "View details" }?.performClick(nil)
        XCTAssertEqual(ids, ["old"])
    }
    private func tree(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(tree) }
}
