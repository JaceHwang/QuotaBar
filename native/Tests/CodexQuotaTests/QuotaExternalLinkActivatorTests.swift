import Foundation
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaExternalLinkActivatorTests: XCTestCase {
    func testDismissesBeforeOpeningTheExactDestination() {
        var events: [String] = []
        let activator = QuotaExternalLinkActivator(
            dismiss: {
                events.append("dismiss")
            },
            open: { url in
                events.append("open:\(url.absoluteString)")
                return true
            }
        )

        activator.activate(URL(string: "https://x.com/thsottiaux")!)

        XCTAssertEqual(
            events,
            ["dismiss", "open:https://x.com/thsottiaux"]
        )
    }

    func testStillDismissesWhenTheWorkspaceRejectsTheURL() {
        var dismissCount = 0
        let activator = QuotaExternalLinkActivator(
            dismiss: {
                dismissCount += 1
            },
            open: { _ in false }
        )

        activator.activate(URL(string: "https://x.com/thsottiaux")!)

        XCTAssertEqual(dismissCount, 1)
    }
}
