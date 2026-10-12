import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor
final class FloatingQuotaTypographyTests: XCTestCase {
    func testKeepsCenteredDotBetweenPercentageAndResetTimeInBothQuotaRows() throws {
        let text = FloatingQuotaTypography.string(
            summary: ResetIndicatorSummary(
                primary: "5 hours 85% · Aug 26, 14:55",
                secondary: "7 days 98% · Sep 1, 08:00",
                primaryRemainingPercent: 85,
                secondaryRemainingPercent: 98
            ),
            alignment: .left
        )

        XCTAssertEqual(
            text.string,
            "5 hours\t85%\t· Aug 26, 14:55\n7 days\t98%\t· Sep 1, 08:00"
        )
        let paragraph = try XCTUnwrap(
            text.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        )
        XCTAssertEqual(paragraph.tabStops.map(\.location), [46, 78])
        let labelFont = try XCTUnwrap(
            text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        let percentFont = try XCTUnwrap(
            text.attribute(.font, at: 8, effectiveRange: nil) as? NSFont
        )
        XCTAssertEqual(labelFont.pointSize, 11)
        XCTAssertEqual(percentFont.pointSize, 12)
    }
}
