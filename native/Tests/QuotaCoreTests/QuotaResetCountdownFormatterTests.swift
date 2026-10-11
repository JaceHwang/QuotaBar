import Foundation
import XCTest
@testable import QuotaCore

final class QuotaResetCountdownFormatterTests: XCTestCase {
    private let formatter = QuotaResetCountdownFormatter()

    func testFormatsLocalizedDayAndHourCountdowns() {
        let now = Date(timeIntervalSince1970: 0)
        let reset = now.addingTimeInterval(4 * 86_400 + 23 * 3_600 + 59)

        XCTAssertEqual(
            formatter.string(from: now, to: reset, language: .simplifiedChinese),
            "4天23小时"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: reset, language: .traditionalChinese),
            "4天23小時"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: reset, language: .english),
            "4d 23h"
        )
    }

    func testUsesCompactFallbackForSubHourCountdown() {
        let now = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            formatter.string(
                from: now,
                to: now.addingTimeInterval(59),
                language: .english
            ),
            "<1m"
        )
    }

    func testFormatsMinuteCountdownsAtSubHourBoundariesInEveryLanguage() {
        let now = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            formatter.string(from: now, to: now.addingTimeInterval(59), language: .english),
            "<1m"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: now.addingTimeInterval(60), language: .english),
            "1m"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: now.addingTimeInterval(45 * 60), language: .english),
            "45m"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: now.addingTimeInterval(3_599), language: .english),
            "59m"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: now.addingTimeInterval(45 * 60), language: .simplifiedChinese),
            "45分钟"
        )
        XCTAssertEqual(
            formatter.string(from: now, to: now.addingTimeInterval(45 * 60), language: .traditionalChinese),
            "45分鐘"
        )
    }
}
