import Foundation
import XCTest
@testable import QuotaCore

final class ResetFormatterTests: XCTestCase {
    private let formatter = ResetFormatter()
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private let now = Date(timeIntervalSince1970: 1_785_456_000)
    private let snapshot = AllowanceSnapshot(
        usedPercent: 24,
        remainingPercent: 76,
        resetsAt: Date(timeIntervalSince1970: 1_785_628_824),
        receivedAt: Date(timeIntervalSince1970: 1_785_456_000)
    )

    func testUsesMonthAndDayWhenThereIsRoom() {
        let label = formatter.label(
            snapshot: snapshot,
            now: now,
            language: .simplifiedChinese,
            timeZone: timeZone,
            maxWidth: 200
        )

        XCTAssertEqual(label, "76% · 8月2日 08:00")
    }

    func testUsesWeekdayAtMediumWidth() {
        let label = formatter.label(
            snapshot: snapshot,
            now: now,
            language: .simplifiedChinese,
            timeZone: timeZone,
            maxWidth: 110
        )

        XCTAssertEqual(label, "76% · 周日 08:00")
    }

    func testUsesOnlyTimeAtNarrowWidth() {
        let label = formatter.label(
            snapshot: snapshot,
            now: now,
            language: .simplifiedChinese,
            timeZone: timeZone,
            maxWidth: 75
        )

        XCTAssertEqual(label, "76% · 08:00")
    }

    func testAlwaysPreservesPercentageAndTime() {
        for maxWidth in [200.0, 110.0, 75.0, 1.0] {
            let label = formatter.label(
                snapshot: snapshot,
                now: now,
                language: .simplifiedChinese,
                timeZone: timeZone,
                maxWidth: maxWidth
            )

            XCTAssertTrue(label.contains("%"))
            XCTAssertNotNil(label.range(of: #"\d{2}:\d{2}"#, options: .regularExpression))
        }
    }

    func testUsesTraditionalChineseAndEnglishDates() {
        XCTAssertEqual(
            formatter.label(
                snapshot: snapshot,
                now: now,
                language: .traditionalChinese,
                timeZone: timeZone,
                maxWidth: 200
            ),
            "76% · 8月2日 08:00"
        )
        XCTAssertEqual(
            formatter.label(
                snapshot: snapshot,
                now: now,
                language: .english,
                timeZone: timeZone,
                maxWidth: 200
            ),
            "76% · Aug 2, 08:00"
        )
    }

    func testFormatsTwoLineIndicatorSummaryForPrimaryAndWeeklyWindows() {
        let summary = formatter.indicatorSummary(
            snapshot: AllowanceSnapshot(
                usedPercent: 15,
                remainingPercent: 85,
                resetsAt: Date(timeIntervalSince1970: 1_787_727_330),
                receivedAt: now,
                windowDurationMins: 300,
                secondary: QuotaWindowSnapshot(
                    usedPercent: 2,
                    remainingPercent: 98,
                    resetsAt: Date(timeIntervalSince1970: 1_788_220_800),
                    windowDurationMins: 10_080
                )
            ),
            language: .simplifiedChinese,
            timeZone: timeZone,
            maxWidth: 200
        )

        XCTAssertEqual(summary.primary, "5 小时 85% · 8月26日 14:55")
        XCTAssertEqual(summary.secondary, "7 天 98% · 9月1日 08:00")
        XCTAssertEqual(summary.primaryRemainingPercent, 85)
        XCTAssertEqual(summary.secondaryRemainingPercent, 98)
    }
}
