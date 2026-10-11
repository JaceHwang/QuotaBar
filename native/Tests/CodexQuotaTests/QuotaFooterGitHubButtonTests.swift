import AppKit
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaFooterGitHubButtonTests: XCTestCase {
    func testExposesProjectLinkAccessibilityAndOpensExactURL() {
        let destination = URL(string: "https://github.com/JaceHwang/codex-usage-sidebar")!
        var opened: URL?
        let button = QuotaFooterGitHubButton(
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

    func testUsesCompactBorderlessRoundedSurface() {
        let button = QuotaFooterGitHubButton(
            frame: CGRect(x: 0, y: 0, width: 88, height: 30),
            destination: URL(string: "https://github.com/JaceHwang/codex-usage-sidebar")!,
            onActivate: { _ in }
        )

        XCTAssertEqual(button.layer?.cornerRadius, 15)
        XCTAssertEqual(button.layer?.borderWidth ?? 0, 0)
        XCTAssertEqual(button.subviews.count, 2)
    }
}
