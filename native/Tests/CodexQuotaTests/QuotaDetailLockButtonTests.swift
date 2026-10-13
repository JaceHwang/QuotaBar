import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaDetailLockButtonTests: XCTestCase {
    func testButtonReportsLockToggleAndExposesSelectedState() {
        var activationCount = 0
        let button = QuotaDetailLockButton(
            frame: CGRect(x: 0, y: 0, width: 26, height: 26),
            isLockedOpen: true,
            accessibilityLabel: "取消固定浮窗"
        ) {
            activationCount += 1
        }

        XCTAssertEqual(button.accessibilityLabel(), "取消固定浮窗")
        XCTAssertEqual(button.state, .on)
        XCTAssertEqual(button.layer?.cornerRadius, 13)
        XCTAssertNotEqual(button.layer?.backgroundColor, NSColor.clear.cgColor)

        button.performClick(nil)
        XCTAssertEqual(activationCount, 1)
    }

    func testCardPlacesLockButtonInHeaderAndForwardsActivation() throws {
        var activationCount = 0
        var openedURL: URL?
        let content = QuotaDetailContent(
            title: "Codex 剩余额度",
            remainingPercent: 85,
            informationEntry: QuotaInformationEntry(
                title: "Tibo 的 X 动态",
                accessibilityLabel: "在浏览器中打开 Tibo 的 X 主页",
                destination: URL(string: "https://x.com/thsottiaux")!
            ),
            rows: []
        )
        let card = QuotaDetailCardView(
            frame: CGRect(x: 0, y: 0, width: 360, height: 300),
            content: content,
            rowHeights: [],
            version: "0.4.0",
            isLockedOpen: false,
            lockAccessibilityLabel: "固定浮窗",
            onLockOpenToggle: { activationCount += 1 },
            onOpenURL: { openedURL = $0 }
        )
        card.layoutSubtreeIfNeeded()

        let tibo = try XCTUnwrap(descendants(of: card).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == content.informationEntry.accessibilityLabel
        })
        let github = try XCTUnwrap(descendants(of: card).compactMap { $0 as? QuotaFooterLinkButton }.first {
            $0.accessibilityLabel() == "GitHub"
        })
        XCTAssertTrue(tibo.superview === github.superview)
        XCTAssertLessThanOrEqual(tibo.frame.maxX, github.frame.minX)
        tibo.performClick(nil)
        XCTAssertEqual(openedURL, content.informationEntry.destination)

        let button = try XCTUnwrap(descendants(of: card).compactMap { $0 as? QuotaDetailLockButton }.first)
        XCTAssertEqual(button.frame, CGRect(x: 257, y: 256, width: 28, height: 26))
        XCTAssertEqual(button.state, .off)
        XCTAssertEqual(button.layer?.cornerRadius, 13)

        button.performClick(nil)
        XCTAssertEqual(activationCount, 1)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
