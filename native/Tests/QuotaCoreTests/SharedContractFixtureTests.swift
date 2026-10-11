import Foundation
import XCTest
@testable import QuotaCore

final class SharedContractFixtureTests: XCTestCase {
    func testMacDecoderConsumesTheSameReadResponseAsWindowsCore() throws {
        let fixture = try Data(contentsOf: contractURL("rate-limits/read-response.json"))

        let snapshot = try RateLimitDecoder.decodeResponse(
            fixture,
            receivedAt: Date(timeIntervalSince1970: 1_785_000_000)
        )

        XCTAssertEqual(snapshot.usedPercent, 24)
        XCTAssertEqual(snapshot.remainingPercent, 76)
        XCTAssertEqual(snapshot.resetsAt.timeIntervalSince1970, 1_785_628_824)
        XCTAssertEqual(snapshot.windowDurationMins, 300)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 98)
        XCTAssertEqual(snapshot.secondary?.windowDurationMins, 10_080)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.credits?.balance, "12.50")
        XCTAssertEqual(snapshot.bank?.availableCount, 2)
        XCTAssertEqual(snapshot.bank?.credits?.count, 2)
    }

    func testMacDecoderConsumesTheSameNotificationAsWindowsCore() throws {
        let fixture = try Data(contentsOf: contractURL("rate-limits/updated-notification.json"))
        let snapshot = try RateLimitDecoder.decodeNotification(
            fixture,
            receivedAt: .distantPast
        )
        XCTAssertEqual(snapshot.remainingPercent, 69)
    }

    private func contractURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts")
            .appendingPathComponent(relativePath)
    }
}
