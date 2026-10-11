import Foundation
import XCTest
@testable import QuotaCore

final class StandaloneStateTests: XCTestCase {
    func testExpiredAuthenticationIsVisibleAndStopsPollingUntilLogin() {
        var state = StandaloneState()
        state.receiveError(method: "account/rateLimits/read", message: "401 Unauthorized token_expired")
        XCTAssertEqual(state.phase, .needsLogin)
        XCTAssertFalse(state.shouldRefresh(at: Date()))
        state.loginCompleted(success: true)
        XCTAssertEqual(state.phase, .loading)
        XCTAssertTrue(state.shouldRefresh(at: Date()))
    }

    func testOptionalUsageFailureDoesNotInvalidateQuota() {
        var state = StandaloneState()
        let now = Date(timeIntervalSince1970: 1000)
        state.receivedQuota(at: now)
        state.receiveError(method: "account/usage/read", message: "Method not found")
        XCTAssertEqual(state.phase, .ready)
        XCTAssertFalse(state.shouldRefresh(at: now.addingTimeInterval(59)))
        XCTAssertTrue(state.shouldRefresh(at: now.addingTimeInterval(60)))
    }

    func testNetworkFailuresBackOffAndKeepLastSuccess() {
        var state = StandaloneState()
        let now = Date(timeIntervalSince1970: 1000)
        state.receivedQuota(at: now)
        state.receiveError(method: "account/rateLimits/read", message: "network unavailable", at: now)
        XCTAssertEqual(state.phase, .offline)
        XCTAssertEqual(state.lastSuccess, now)
        XCTAssertFalse(state.shouldRefresh(at: now.addingTimeInterval(14)))
        XCTAssertTrue(state.shouldRefresh(at: now.addingTimeInterval(15)))
    }
}
