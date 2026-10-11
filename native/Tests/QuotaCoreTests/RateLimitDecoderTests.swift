import Foundation
import XCTest
@testable import QuotaCore

final class RateLimitDecoderTests: XCTestCase {
    private let resetTimestamp = 1_785_628_824.0
    private let receivedAt = Date(timeIntervalSince1970: 1_780_000_000)

    func testDecodesSingleCodexBucket() throws {
        let data = Data(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {
                  "usedPercent": 24,
                  "windowDurationMins": 10080,
                  "resetsAt": 1785628824
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.usedPercent, 24)
        XCTAssertEqual(snapshot.remainingPercent, 76)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: resetTimestamp))
        XCTAssertEqual(snapshot.receivedAt, receivedAt)
    }

    func testDecodesFiveHourPrimaryAndWeeklySecondaryBuckets() throws {
        let data = Data(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {
                  "usedPercent": 15,
                  "windowDurationMins": 300,
                  "resetsAt": 1787727330
                },
                "secondary": {
                  "usedPercent": 2,
                  "windowDurationMins": 10080,
                  "resetsAt": 1788276999
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.windowDurationMins, 300)
        XCTAssertEqual(snapshot.remainingPercent, 85)
        XCTAssertEqual(snapshot.secondary?.windowDurationMins, 10080)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 98)
        XCTAssertEqual(
            snapshot.secondary?.resetsAt,
            Date(timeIntervalSince1970: 1_788_276_999)
        )
    }

    func testPrefersCodexMultiBucket() throws {
        let data = Data(
            """
            {
              "rateLimitsByLimitId": {
                "other": {
                  "primary": {"usedPercent": 90, "resetsAt": 1780000000}
                },
                "codex": {
                  "primary": {"usedPercent": 24, "resetsAt": 1785628824}
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.remainingPercent, 76)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: resetTimestamp))
    }

    func testDecodesUpdatedNotification() throws {
        let data = Data(
            """
            {
              "method": "account/rateLimits/updated",
              "params": {
                "rateLimits": {
                  "limitId": "codex",
                  "primary": {"usedPercent": 24, "resetsAt": 1785628824}
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeNotification(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.remainingPercent, 76)
    }

    func testDecodesPlanCreditsAndBankResetCredits() throws {
        let data = Data(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {
                  "usedPercent": 24,
                  "windowDurationMins": 10080,
                  "resetsAt": 1785628824
                },
                "planType": "plus",
                "credits": {
                  "hasCredits": true,
                  "unlimited": false,
                  "balance": "12.50"
                }
              },
              "rateLimitResetCredits": {
                "availableCount": 2,
                "credits": [
                  {
                    "id": "private-id-must-not-leak",
                    "resetType": "codexRateLimits",
                    "status": "available",
                    "grantedAt": 1782937171,
                    "expiresAt": 1785529171,
                    "title": "Full reset",
                    "description": "Courtesy reset"
                  },
                  {
                    "id": "another-private-id",
                    "resetType": "codexRateLimits",
                    "status": "available",
                    "grantedAt": 1783965641,
                    "expiresAt": null,
                    "title": null,
                    "description": null
                  }
                ]
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.windowDurationMins, 10080)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(
            snapshot.credits,
            CreditBalance(hasCredits: true, unlimited: false, balance: "12.50")
        )
        XCTAssertEqual(snapshot.bank?.availableCount, 2)
        XCTAssertEqual(snapshot.bank?.credits?.count, 2)
        XCTAssertEqual(snapshot.bank?.credits?.first?.status, "available")
        XCTAssertEqual(
            snapshot.bank?.credits?.first?.grantedAt,
            Date(timeIntervalSince1970: 1_782_937_171)
        )
        XCTAssertEqual(
            snapshot.bank?.credits?.first?.expiresAt,
            Date(timeIntervalSince1970: 1_785_529_171)
        )
        XCTAssertEqual(snapshot.bank?.credits?.first?.title, "Full reset")
        XCTAssertEqual(snapshot.bank?.credits?.first?.description, "Courtesy reset")
        XCTAssertNil(snapshot.bank?.credits?[1].expiresAt)
    }

    func testPreservesBankDetailAvailabilityAndClampsCount() throws {
        let cases: [(creditsJSON: String, expectedDetails: [BankResetCredit]?)] = [
            ("null", nil),
            ("[]", [])
        ]

        for item in cases {
            let data = Data(
                """
                {
                  "rateLimits": {
                    "limitId": "codex",
                    "primary": {"usedPercent": 24, "resetsAt": 1785628824}
                  },
                  "rateLimitResetCredits": {
                    "availableCount": -3,
                    "credits": \(item.creditsJSON)
                  }
                }
                """.utf8
            )

            let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

            XCTAssertEqual(snapshot.bank?.availableCount, 0)
            XCTAssertEqual(snapshot.bank?.credits, item.expectedDetails)
        }
    }

    func testDecodesSingleBankCreditAsNumberNotBoolean() throws {
        let data = Data(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {"usedPercent": 10, "resetsAt": 1786133341}
              },
              "rateLimitResetCredits": {
                "availableCount": 1,
                "credits": [
                  {"status": "available", "expiresAt": 1786557641}
                ]
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.bank?.availableCount, 1)
        XCTAssertEqual(
            snapshot.bank?.credits?.first?.expiresAt,
            Date(timeIntervalSince1970: 1_786_557_641)
        )
    }

    func testRejectsMissingResetTime() {
        let data = Data(
            """
            {"rateLimits":{"limitId":"codex","primary":{"usedPercent":24}}}
            """.utf8
        )

        XCTAssertThrowsError(
            try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)
        ) { error in
            XCTAssertEqual(error as? RateLimitDecodingError, .missingResetTime)
        }
    }

    func testClampsAndRoundsRemainingPercent() throws {
        let cases = [
            (used: 24.4, remaining: 76),
            (used: -5.0, remaining: 100),
            (used: 140.0, remaining: 0)
        ]

        for item in cases {
            let data = Data(
                """
                {"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(item.used),"resetsAt":1785628824}}}
                """.utf8
            )

            let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

            XCTAssertEqual(snapshot.remainingPercent, item.remaining)
        }
    }

    func testIgnoresUnknownFields() throws {
        let data = Data(
            """
            {
              "futureTopLevelField": {"anything": true},
              "rateLimits": {
                "limitId": "codex",
                "futureBucketField": ["a", "b"],
                "primary": {
                  "usedPercent": 24,
                  "resetsAt": 1785628824,
                  "futureWindowField": "ignored"
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitDecoder.decodeResponse(data, receivedAt: receivedAt)

        XCTAssertEqual(snapshot.remainingPercent, 76)
    }
}
