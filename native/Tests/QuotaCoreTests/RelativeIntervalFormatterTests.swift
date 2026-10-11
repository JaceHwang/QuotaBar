import Foundation
import XCTest
@testable import QuotaCore

final class RelativeIntervalFormatterTests: XCTestCase {
    private let formatter = RelativeIntervalFormatter()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testFormatsFutureIntervalsAtUsefulPrecision() {
        XCTAssertEqual(format(after: 6 * 86_400), "6d0h")
        XCTAssertEqual(
            format(after: 3 * 86_400 + 8 * 3_600 + 59 * 60),
            "3d8h"
        )
        XCTAssertEqual(format(after: 8 * 3_600 + 15 * 60), "8h15m")
        XCTAssertEqual(format(after: 42 * 60), "42m")
        XCTAssertEqual(format(after: 42), "<1m")
    }

    func testFormatsPastIntervalsWithoutNegativeValues() {
        XCTAssertEqual(format(after: -6 * 86_400), "6d0h前")
        XCTAssertEqual(
            format(after: -8 * 3_600 - 15 * 60),
            "8h15m前"
        )
        XCTAssertEqual(format(after: -42 * 60), "42m前")
        XCTAssertEqual(format(after: -42), "<1m前")
    }

    func testLocalizesPastSuffixWithoutChangingCompactUnits() {
        XCTAssertEqual(
            format(after: -42 * 60, language: .traditionalChinese),
            "42m前"
        )
        XCTAssertEqual(
            format(after: -42 * 60, language: .english),
            "42m ago"
        )
        XCTAssertEqual(
            format(after: -42, language: .english),
            "<1m ago"
        )
    }

    private func format(
        after interval: TimeInterval,
        language: CodexDisplayLanguage = .simplifiedChinese
    ) -> String {
        formatter.string(
            from: now,
            to: now.addingTimeInterval(interval),
            language: language
        )
    }
}
