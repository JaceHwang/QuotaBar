import Foundation
import XCTest
import QuotaCore
@testable import CodexQuota

private final class BarkProtocolProbe: @unchecked Sendable {
    let lock = NSLock()
    var request: URLRequest?
    var body = Data("{\"code\":200}".utf8)
    var status = 200
    func reply(to request: URLRequest) -> (Int, Data) { lock.withLock { self.request = request; return (status, body) } }
}
private final class BarkFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var probe = BarkProtocolProbe()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.probe.reply(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor final class BarkPushClientTests: XCTestCase {
    func testFixedHTTPSPostUsesJSONBodyAndBusinessSuccess() async throws {
        let probe = BarkProtocolProbe(); BarkFixtureProtocol.probe = probe
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BarkFixtureProtocol.self]
        let client = BarkPushClient(configuration: config)
        let payload = try BarkPayload.encode(deviceKey: "fake-key", title: "Example", body: "Example only")
        let result = await client.send(payload)
        if case .accepted = result {} else { XCTFail("Expected accepted") }
        let request = try XCTUnwrap(probe.lock.withLock { probe.request })
        XCTAssertEqual(request.url?.absoluteString, "https://api.day.app/push")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(request.url!.absoluteString.contains("fake-key")); XCTAssertEqual(request.timeoutInterval, 10)
    }
    func testHTTPAndBusinessFailuresAndOversizedResponseCannotSucceed() async {
        for (status, body) in [(200, Data("{\"code\":400}".utf8)), (503, Data("{\"code\":200}".utf8)), (200, Data(repeating: 32, count: 65537)), (200, Data("not-json".utf8)), (302, Data("{\"code\":200}".utf8))] {
            let probe = BarkProtocolProbe(); probe.status = status; probe.body = body; BarkFixtureProtocol.probe = probe
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BarkFixtureProtocol.self]
            let result = await BarkPushClient(configuration: config).send(Data("{}".utf8))
            if case .accepted = result { XCTFail("Invalid response was accepted") }
        }
    }
}
