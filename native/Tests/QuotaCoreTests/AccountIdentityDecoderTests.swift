import Foundation
import XCTest
@testable import QuotaCore

final class AccountIdentityDecoderTests: XCTestCase {
    func testDecodesDisplayNameEmailAndAvatarFromAccountRead() throws {
        let data = Data(
            #"{"result":{"account":{"displayName":"Jace","email":"jace@example.com","avatarUrl":"https://example.com/avatar.png"}}}"#.utf8
        )

        let identity = try AccountIdentityDecoder.decodeResponse(data)

        XCTAssertEqual(identity.displayName, "Jace")
        XCTAssertEqual(identity.email, "jace@example.com")
        XCTAssertEqual(identity.avatarURL?.absoluteString, "https://example.com/avatar.png")
        XCTAssertEqual(identity.preferredName, "Jace")
    }

    func testFallsBackToEmailWhenAccountReadHasNoDisplayName() throws {
        let data = Data(
            #"{"result":{"account":{"email":"jace@example.com","planType":"plus"}}}"#.utf8
        )

        let identity = try AccountIdentityDecoder.decodeResponse(data)

        XCTAssertNil(identity.displayName)
        XCTAssertEqual(identity.preferredName, "jace@example.com")
    }

    func testRejectsAccountReadWithoutIdentityFields() {
        let data = Data(#"{"result":{"account":{"planType":"plus"}}}"#.utf8)

        XCTAssertThrowsError(try AccountIdentityDecoder.decodeResponse(data)) { error in
            XCTAssertEqual(error as? AccountIdentityDecodingError, .missingAccount)
        }
    }
}
