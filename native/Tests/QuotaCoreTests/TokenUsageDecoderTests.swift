import Foundation
import XCTest
@testable import QuotaCore

final class TokenUsageDecoderTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testDecodesCamelCaseSummaryAndSparseDailyBuckets() throws {
        let data = Data(
            #"""
            {
              "summary": { "lifetimeTokens": 1234567, "peakDailyTokens": 900000,
                "longestRunningTurnSec": 10, "currentStreakDays": 2, "longestStreakDays": 5 },
              "dailyUsageBuckets": [
                { "startDate": "2026-08-13", "tokens": 1200 },
                { "startDate": "2026-08-15", "tokens": 3400 }
              ]
            }
            """#.utf8
        )

        let snapshot = try TokenUsageDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.receivedAt, receivedAt)
        XCTAssertEqual(snapshot.dailyBuckets.map(\.tokens), [1_200, 3_400])
        XCTAssertEqual(snapshot.summary?.lifetimeTokens, 1_234_567)
        XCTAssertEqual(snapshot.summary?.peakDailyTokens, 900_000)
        XCTAssertEqual(snapshot.summary?.longestRunningTurnSec, 10)
        XCTAssertEqual(snapshot.summary?.currentStreakDays, 2)
        XCTAssertEqual(snapshot.summary?.longestStreakDays, 5)
        XCTAssertEqual(dayComponents(snapshot.dailyBuckets[0].date), DateComponents(year: 2026, month: 8, day: 13))
        XCTAssertEqual(dayComponents(snapshot.dailyBuckets[1].date), DateComponents(year: 2026, month: 8, day: 15))
    }

    func testRejectsNegativeTokens() {
        XCTAssertThrowsError(
            try TokenUsageDecoder.decodeResponse(
                Data(#"{"dailyUsageBuckets":[{"startDate":"2026-08-13","tokens":-1}]}"#.utf8),
                receivedAt: receivedAt
            )
        ) { error in
            XCTAssertEqual(error as? TokenUsageDecodingError, .invalidTokens)
        }
    }

    func testRejectsTokensOutsideInt64RangeWithoutClamping() {
        XCTAssertThrowsError(
            try TokenUsageDecoder.decodeResponse(
                Data(#"{"dailyUsageBuckets":[{"startDate":"2026-08-13","tokens":9223372036854775808.0}]}"#.utf8),
                receivedAt: receivedAt
            )
        ) { error in
            XCTAssertEqual(error as? TokenUsageDecodingError, .invalidTokens)
        }
    }

    func testRejectsInvalidBucketDate() {
        XCTAssertThrowsError(
            try TokenUsageDecoder.decodeResponse(
                Data(#"{"dailyUsageBuckets":[{"startDate":"2026-02-30","tokens":1}]}"#.utf8),
                receivedAt: receivedAt
            )
        ) { error in
            XCTAssertEqual(error as? TokenUsageDecodingError, .invalidDate)
        }
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(
            try TokenUsageDecoder.decodeResponse(Data("{not json}".utf8), receivedAt: receivedAt)
        ) { error in
            XCTAssertEqual(error as? TokenUsageDecodingError, .invalidJSON)
        }
    }

    func testClassifiesMethodNotFoundAsUnsupported() {
        XCTAssertThrowsError(
            try TokenUsageDecoder.decodeResponse(
                Data(#"{"error":{"code":-32601,"message":"Method not found"}}"#.utf8),
                receivedAt: receivedAt
            )
        ) { error in
            XCTAssertEqual(error as? TokenUsageDecodingError, .unsupported)
        }
    }

    func testClassifiesOtherJSONRPCErrorsAsUnavailable() {
        XCTAssertThrowsError(
            try TokenUsageDecoder.decodeResponse(
                Data(#"{"error":{"code":-32000,"message":"Unavailable"}}"#.utf8),
                receivedAt: receivedAt
            )
        ) { error in
            XCTAssertEqual(error as? TokenUsageDecodingError, .unavailable)
        }
    }

    private func dayComponents(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.dateComponents([.year, .month, .day], from: date)
    }
}
