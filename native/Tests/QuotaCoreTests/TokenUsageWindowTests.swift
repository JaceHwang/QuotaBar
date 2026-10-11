import Foundation
import XCTest
@testable import QuotaCore

final class TokenUsageWindowTests: XCTestCase {
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    func testReferenceDaysAlwaysContainSevenSlotsAndZeroFillFutureDates() throws {
        let allowance = AllowanceSnapshot(
            usedPercent: 50,
            remainingPercent: 50,
            resetsAt: try date("2026-08-20 19:31"),
            receivedAt: try date("2026-08-15 20:00"),
            windowDurationMins: 10_080
        )
        let snapshot = TokenUsageSnapshot(
            receivedAt: allowance.receivedAt,
            dailyBuckets: [
                TokenUsageDay(
                    date: try date("2026-08-13 00:00"),
                    tokens: 1_200,
                    timeZone: utc
                )
            ],
            summary: nil,
            availability: .available
        )

        let days = TokenUsageWindow.referenceDays(
            from: snapshot,
            allowance: allowance,
            now: try date("2026-08-15 20:00"),
            timeZone: utc
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.tokens), [1_200, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(
            days.map { dayString($0.date) },
            [
                "2026-08-13", "2026-08-14", "2026-08-15", "2026-08-16",
                "2026-08-17", "2026-08-18", "2026-08-19"
            ]
        )
    }

    func testCurrentCycleFillsSparseDaysAndExcludesOutsideOrFutureBuckets() throws {
        let allowance = AllowanceSnapshot(
            usedPercent: 50,
            remainingPercent: 50,
            resetsAt: try date("2026-08-20 19:31"),
            receivedAt: try date("2026-08-15 12:00"),
            windowDurationMins: 10_080
        )
        let snapshot = TokenUsageSnapshot(
            receivedAt: allowance.receivedAt,
            dailyBuckets: [
                TokenUsageDay(date: try date("2026-08-12 00:00"), tokens: 999, timeZone: utc),
                TokenUsageDay(date: try date("2026-08-13 00:00"), tokens: 1_200, timeZone: utc),
                TokenUsageDay(date: try date("2026-08-15 00:00"), tokens: 3_400, timeZone: utc),
                TokenUsageDay(date: try date("2026-08-21 00:00"), tokens: 777, timeZone: utc)
            ],
            summary: nil,
            availability: .available
        )

        let cycle = TokenUsageWindow.currentCycle(
            from: snapshot,
            allowance: allowance,
            now: try date("2026-08-15 12:00"),
            timeZone: utc
        )

        XCTAssertEqual(cycle?.dailyBuckets.map(\.tokens), [1_200, 0, 3_400])
        XCTAssertEqual(cycle?.totalTokens, 4_600)
        XCTAssertEqual(cycle?.dailyBuckets.map { dayString($0.date) }, ["2026-08-13", "2026-08-14", "2026-08-15"])
    }

    func testReturnsNilWhenAllowanceDoesNotDefineAPositiveWindow() throws {
        let allowance = AllowanceSnapshot(
            usedPercent: 50,
            remainingPercent: 50,
            resetsAt: try date("2026-08-20 19:31"),
            receivedAt: try date("2026-08-15 12:00"),
            windowDurationMins: 0
        )
        let snapshot = TokenUsageSnapshot(
            receivedAt: allowance.receivedAt,
            dailyBuckets: [],
            summary: nil,
            availability: .available
        )

        XCTAssertNil(TokenUsageWindow.currentCycle(from: snapshot, allowance: allowance, now: allowance.receivedAt, timeZone: utc))
    }

    func testReturnsNilWhenDuplicateDayTokensOverflow() throws {
        let allowance = try oneDayAllowance()
        let sameDay = try date("2026-08-20 00:00")
        let snapshot = TokenUsageSnapshot(
            receivedAt: allowance.receivedAt,
            dailyBuckets: [
                TokenUsageDay(date: sameDay, tokens: Int64.max, timeZone: utc),
                TokenUsageDay(date: sameDay, tokens: 1, timeZone: utc)
            ],
            summary: nil,
            availability: .available
        )

        XCTAssertNil(TokenUsageWindow.currentCycle(from: snapshot, allowance: allowance, now: allowance.receivedAt, timeZone: utc))
    }

    func testReturnsNilWhenCycleTotalOverflows() throws {
        let allowance = try twoDayAllowance()
        let snapshot = TokenUsageSnapshot(
            receivedAt: allowance.receivedAt,
            dailyBuckets: [
                TokenUsageDay(date: try date("2026-08-19 00:00"), tokens: Int64.max, timeZone: utc),
                TokenUsageDay(date: try date("2026-08-20 00:00"), tokens: 1, timeZone: utc)
            ],
            summary: nil,
            availability: .available
        )

        XCTAssertNil(TokenUsageWindow.currentCycle(from: snapshot, allowance: allowance, now: allowance.receivedAt, timeZone: utc))
    }

    private func oneDayAllowance() throws -> AllowanceSnapshot {
        AllowanceSnapshot(
            usedPercent: 50,
            remainingPercent: 50,
            resetsAt: try date("2026-08-21 00:00"),
            receivedAt: try date("2026-08-20 12:00"),
            windowDurationMins: 1_440
        )
    }

    private func twoDayAllowance() throws -> AllowanceSnapshot {
        AllowanceSnapshot(
            usedPercent: 50,
            remainingPercent: 50,
            resetsAt: try date("2026-08-21 00:00"),
            receivedAt: try date("2026-08-20 12:00"),
            windowDurationMins: 2_880
        )
    }

    private func date(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: string) else {
            throw NSError(domain: "TokenUsageWindowTests", code: 1)
        }
        return date
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
