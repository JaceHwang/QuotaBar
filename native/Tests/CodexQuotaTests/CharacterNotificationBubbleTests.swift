import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class CharacterNotificationBubbleTests: XCTestCase {
    func testCompactReferenceUsesMeasuredBodyHeight() throws {
        let bubble = CharacterNotificationBubble()
        let short = ExperienceNotification(id: "compact", kind: .recovery, epoch: nil, title: "额度已恢复", body: "5 小时剩余 100% · 7 天剩余 36%", createdAt: Date())
        let view = bubble.content(message: short, dark: false, language: .simplifiedChinese, width: 420)
        XCTAssertEqual(view.frame.height, 142)
        let primary = try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(primary.frame.height, 32)
        XCTAssertEqual(primary.superview!.frame.minX, 104)
        let long = ExperienceNotification(id: "long", kind: .bank, epoch: nil, title: "Bank credits expiring", body: "First line\nSecond line\nThird line\nFourth line", createdAt: Date())
        let expanded = bubble.content(message: long, dark: false, language: .english, width: 340)
        XCTAssertGreaterThan(expanded.frame.height, view.frame.height)
    }
    func testRealPreviewBodyFitsItsNativeWrappingCell() throws {
        let raw = "5 小时剩余 100% · 7 天剩余 36%。仅为示例。"
        let bubble = CharacterNotificationBubble()
        let message = ExperienceNotification(id: "preview-wrap", kind: .test, epoch: nil, title: "示例通知", body: raw, createdAt: Date())
        for width: CGFloat in [340, 420] {
            let view = bubble.content(message: message, dark: false, language: .simplifiedChinese, width: width)
            let body = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.toolTip == raw })
            let cell = try XCTUnwrap(body.cell)
            let needed = ceil(cell.cellSize(forBounds: CGRect(x: 0, y: 0, width: body.frame.width, height: 1000)).height)
            XCTAssertGreaterThanOrEqual(body.frame.height, needed, "Full preview must fit native text-cell wrapping at width \(width)")
            if let output = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("preview-wrap-\(Int(width)).png"))
            }
        }
    }
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
            let primary = try XCTUnwrap(actions.first { $0.identifier?.rawValue == "notification.primary" })
            XCTAssertEqual(primary.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .white)
            let artwork = try XCTUnwrap(all.first { $0.identifier?.rawValue == "notification.character" })
            XCTAssertNil(artwork.hitTest(.zero))
            XCTAssertGreaterThanOrEqual(artwork.frame.width, 94)
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: rep)
            XCTAssertNotNil(rep.representation(using: .png, properties: [:]))
        }
    }
    func testFourLineBankBodyFitsBeforeActions() throws {
        let body = "72 hours: 2 credits\n24 hours: 1 credit\nEarliest expiry:\n2026/10/23 14:00"
        let bubble = CharacterNotificationBubble()
        let message = ExperienceNotification(id: "four-lines", kind: .bank, epoch: nil, title: "Bank credits expiring", body: body, createdAt: Date())
        for width: CGFloat in [340, 420] {
            let view = bubble.content(message: message, dark: false, language: .english, width: width)
            let label = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.stringValue == body })
            let needed = (body as NSString).boundingRect(with: CGSize(width: label.frame.width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: try XCTUnwrap(label.font)]).height
            XCTAssertGreaterThanOrEqual(label.frame.height, ceil(needed))
            XCTAssertLessThanOrEqual(label.frame.maxY + 10, tree(view).compactMap { $0 as? NSButton }.first!.frame.minY)
            let buttons = tree(view).compactMap { $0 as? NSButton }.sorted { $0.frame.minX < $1.frame.minX }
            XCTAssertLessThanOrEqual(buttons[0].frame.maxX + 8, buttons[1].frame.minX)
            XCTAssertTrue(buttons.allSatisfy { $0.frame.maxX <= label.superview!.bounds.maxX - 12 })
        }
    }
    func testLongTextRetainsRawAccessibilityAndFitsActions() throws {
        let bubble = CharacterNotificationBubble()
        let raw = String(repeating: "5 小时额度剩余 100%；7 天额度剩余 36%。", count: 10)
        for width: CGFloat in [340, 420] {
            for language in [CodexDisplayLanguage.english, .simplifiedChinese, .traditionalChinese] {
                for dark in [false, true] {
                    let message = ExperienceNotification(id: "overflow", kind: .recovery, epoch: nil, title: "Quota has recovered and this title wraps across multiple lines", body: raw, createdAt: Date())
                    let view = bubble.content(message: message, dark: dark, language: language, width: width)
                    let body = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.toolTip == raw })
                    XCTAssertEqual(body.accessibilityLabel(), raw)
                    XCTAssertEqual(body.maximumNumberOfLines, 4)
                    let actions = tree(view).compactMap { $0 as? NSButton }
                    XCTAssertTrue(actions.allSatisfy { $0.frame.minY >= body.frame.maxY + 10 && $0.frame.maxY <= view.frame.height - 12 })
                    XCTAssertTrue(actions.allSatisfy { $0.attributedTitle.size().width <= $0.frame.width })
                }
            }
        }
    }
    func testCustomButtonsRenderKeyboardFocus() throws {
        let bubble = CharacterNotificationBubble()
        let message = ExperienceNotification(id: "focus", kind: .recovery, epoch: nil, title: "Restored", body: "100%", createdAt: Date())
        let view = bubble.content(message: message, dark: false, language: .english, width: 420)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        for button in tree(view).compactMap({ $0 as? NSButton }) {
            window.makeFirstResponder(nil)
            func snapshot() throws -> Data {
                let rep = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
                button.cacheDisplay(in: button.bounds, to: rep)
                return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            }
            let unfocused = try snapshot()
            XCTAssertTrue(window.makeFirstResponder(button))
            XCTAssertNotEqual(try snapshot(), unfocused, "Keyboard focus must be visible on custom-drawn buttons")
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
                    let title = kind == .bank ? copy.text("Bank credits expiring", "Bank 权益即将到期", "Bank 權益即將到期") : copy.text("Quota restored", "额度已恢复", "額度已恢復")
                    let body = kind == .bank ? copy.text("72 hours: 2 credits; 24 hours: 1 credit. Earliest expiry: 2026/10/23 14:00", "72 小时内 2 次；24 小时内 1 次。最近到期：2026/10/23 14:00", "72 小時內 2 次；24 小時內 1 次。最近到期：2026/10/23 14:00") : copy.text("5 hours remaining 100%; 7 days remaining 36%", "5 小时额度剩余 100%；7 天额度剩余 36%", "5 小時額度剩餘 100%；7 天額度剩餘 36%")
                    let message = ExperienceNotification(id: "render", kind: kind, epoch: nil, title: title, body: body, createdAt: Date())
                    let view = bubble.content(message: message, dark: dark, language: language, width: 420)
                    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: rep)
                    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("bubble-\(language.rawValue)-\(dark)-\(kind.rawValue).png"))
                }
            }
        }
    }
    func testArtworkUsesVisibleFootprintRatherThanPaddedCanvas() throws {
        let bubble = CharacterNotificationBubble()
        let message = ExperienceNotification(id: "artwork", kind: .test, epoch: nil, title: "Example", body: "100%", createdAt: Date())
        let expected: [(NotificationCharacterArtwork, CGSize)] = [
            (.attention, CGSize(width: 906, height: 970)),
            (.recovery, CGSize(width: 957, height: 882)),
            (.bank, CGSize(width: 1040, height: 980)),
            (.neutral, CGSize(width: 710, height: 890))
        ]
        for (artwork, footprint) in expected {
            let view = bubble.content(message: message, dark: false, language: .english, width: 420, artwork: artwork)
            let image = try XCTUnwrap(tree(view).compactMap { $0 as? NSImageView }.first?.image)
            XCTAssertEqual(image.size, footprint, "Transparent export margins must not shrink the visible character")
        }
    }
    func testRenderReferenceScenes() throws {
        guard let output = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        let bubble = CharacterNotificationBubble()
        let scenes: [(NotificationCharacterArtwork, ExperienceNotificationKind, String, String)] = [
            (.attention, .test, "7 天额度偏低", "剩余 10%，距离重置还有 2 天。"),
            (.recovery, .recovery, "额度已恢复", "5 小时额度剩余 100%；7 天额度剩余 36%"),
            (.bank, .bank, "Bank 权益即将到期", "已知 2 次权益将在 24 小时内到期。")
        ]
        for (artwork, kind, title, body) in scenes {
            let message = ExperienceNotification(id: "reference", kind: kind, epoch: nil, title: title, body: body, createdAt: Date())
            let view = bubble.content(message: message, dark: false, language: .simplifiedChinese, width: 420, artwork: artwork)
            let imageView = try XCTUnwrap(tree(view).compactMap { $0 as? NSImageView }.first)
            XCTAssertNotNil(imageView.image, "Bundled standalone character must load")
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("reference-\(artwork.rawValue).png"))
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
        let b = CharacterNotificationBubble(); var ids: [String] = []; var tokens: [String?] = []; b.onAction = { id, token in ids.append(id); tokens.append(token) }
        var old = ExperienceNotification(id: "old", kind: .recovery, epoch: nil, title: "Old", body: "", createdAt: Date())
        old.deliveryToken = "original-token"
        let first = b.content(message: old, dark: false, language: .english, width: 368)
        _ = b.content(message: ExperienceNotification(id: "new", kind: .recovery, epoch: nil, title: "New", body: "", createdAt: Date()), dark: false, language: .english, width: 368)
        tree(first).compactMap { $0 as? NSButton }.first { $0.title == "View details" }?.performClick(nil)
        XCTAssertEqual(ids, ["old"])
        XCTAssertEqual(tokens, ["original-token"])
    }
    private func tree(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(tree) }
}
