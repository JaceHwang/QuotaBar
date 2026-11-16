import AppKit
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaFooterGitHubButtonTests: XCTestCase {
    func testExposesProjectLinkAccessibilityAndOpensExactURL() {
        let destination = URL(string: "https://github.com/JaceHwang/codex-usage-sidebar")!
        var opened: URL?
        let button = QuotaFooterLinkButton(
            frame: CGRect(x: 0, y: 0, width: 22, height: 22),
            destination: destination,
            onActivate: { opened = $0 }
        )

        XCTAssertEqual(button.accessibilityRole(), .link)
        XCTAssertEqual(button.accessibilityLabel(), "GitHub")
        XCTAssertEqual(button.accessibilityHelp(), destination.absoluteString)

        button.activateLink()

        XCTAssertEqual(opened, destination)
    }

    func testFooterLinkUsesUnderlinedTactileText() throws {
        let button = QuotaFooterLinkButton(frame: CGRect(x: 0, y: 0, width: 88, height: 30), destination: URL(string: "https://github.com/JaceHwang/QuotaBar")!, onActivate: { _ in })
        let base: NSButton = button
        XCTAssertTrue(base is SettingsAccentButton)
        let label = try XCTUnwrap(button.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(label.attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
    }
    func testUsesCompactBorderlessRoundedSurface() {
        let button = QuotaFooterLinkButton(
            frame: CGRect(x: 0, y: 0, width: 88, height: 30),
            destination: URL(string: "https://github.com/JaceHwang/codex-usage-sidebar")!,
            onActivate: { _ in }
        )

        XCTAssertEqual(button.layer?.cornerRadius, 15)
        XCTAssertEqual(button.layer?.borderWidth ?? 0, 0)
        XCTAssertEqual(button.subviews.count, 2)
    }
}
