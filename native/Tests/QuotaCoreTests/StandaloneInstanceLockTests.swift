import Foundation
import XCTest
@testable import QuotaCore

final class StandaloneInstanceLockTests: XCTestCase {
    func testDuplicateIsRejectedAndLockIsReusableAfterOwnerReleases() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var owner: StandaloneInstanceLock? = try StandaloneInstanceLock(url: url)
        XCTAssertNotNil(owner)
        XCTAssertThrowsError(try StandaloneInstanceLock(url: url))
        owner = nil
        let replacement = try StandaloneInstanceLock(url: url)
        XCTAssertNotNil(replacement)
    }
}
