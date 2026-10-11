import AppKit
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaFooterSettingsButtonTests: XCTestCase {
    func testActivatingSettingsButtonInvokesThePopoverCallback() {
        var activations = 0
        let button = QuotaFooterSettingsButton(
            frame: CGRect(x: 0, y: 0, width: 30, height: 30),
            accessibilityLabel: "Settings"
        ) { _ in
            activations += 1
        }

        button.performClick(nil)

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(button.accessibilityLabel(), "Settings")
    }
}
