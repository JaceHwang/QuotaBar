import Foundation
import CryptoKit
import XCTest
@testable import QuotaCore

private actor FixtureUpdateTransport: UpdateTransport {
    let release: Data, tag: Data, proof: Data
    let corrupt: Bool, late: Bool
    init(corrupt: Bool = false, late: Bool = false, wrongSource: Bool = false) throws {
        self.corrupt = corrupt; self.late = late
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/in-app-updates/release-cases.json").standardizedFileURL
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [[String: Any]]
        var r = rows[1]["release"] as! [String: Any]
        proof = try JSONSerialization.data(withJSONObject: ["kind": "release", "workingTreeDirty": false, "version": "2.0.0", "releaseTag": "v2.0.0", "sourceCommit": String(repeating: wrongSource ? "c" : "b", count: 40)])
        var assets = r["assets"] as! [[String: Any]]
        for index in [0, 1] {
            let bytes = index == 0 ? Data("package".utf8) : proof
            assets[index]["size"] = bytes.count
            assets[index]["digest"] = "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        r["assets"] = assets; release = try JSONSerialization.data(withJSONObject: r)
        tag = try JSONSerialization.data(withJSONObject: rows[1]["tag"]!)
    }
    func metadata(_ url: URL, limit: Int) async throws -> Data { url.path.contains("/releases/") ? release : tag }
    func download(_ asset: UpdateAsset, to url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let bytes = asset.name.hasSuffix(".dmg") ? Data((corrupt ? "corrupt" : "package").utf8) : proof
        try bytes.write(to: url); progress(Int64(bytes.count))
        if late { try? await Task.sleep(for: .milliseconds(50)) }
    }
}
final class UpdateDownloadTests: XCTestCase {
    func testTrustedDownloadVerifiesBytesAndProvenanceBeforeReturning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let client = UpdateDownloadClient(transport: try FixtureUpdateTransport())
        let value = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        XCTAssertEqual(try Data(contentsOf: value.archive), Data("package".utf8)); XCTAssertEqual(value.release.sourceCommit, String(repeating: "b", count: 40))
    }
    func testCorruptSourceAndLateCancellationCleanOnlyOwnedStage() async throws {
        for mode in 0..<3 {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let marker = root.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: marker)
            let client = UpdateDownloadClient(transport: try FixtureUpdateTransport(corrupt: mode == 0, late: mode == 2, wrongSource: mode == 1))
            let task = Task { try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root) }
            if mode == 2 { try await Task.sleep(for: .milliseconds(5)); task.cancel() }
            do { _ = try await task.value; XCTFail("Invalid download returned a package") } catch { }
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["keep.txt"])
        }
    }
}

private final class ProgressHTTPProtocol: URLProtocol {
    static let body = Data(repeating: 42, count: 196608)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(Self.body.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class TransferProgressValues: @unchecked Sendable {
    let lock = NSLock()
    var values: [Int64] = []
    func append(_ value: Int64) { lock.lock(); defer { lock.unlock() }; values.append(value) }
}
extension UpdateDownloadTests {
    func testHTTPDownloadReportsProgressAndWritesVerifiedPayload() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ProgressHTTPProtocol.self]
        let transport = UpdateHTTPTransport(configuration: config)
        let body = ProgressHTTPProtocol.body
        let asset = UpdateAsset(name: "test.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/test.dmg")!, size: Int64(body.count), sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let progress = TransferProgressValues()
        try await transport.download(asset, to: destination) { progress.append($0) }
        XCTAssertTrue(progress.values.contains { $0 > 0 && $0 < asset.size })
        XCTAssertEqual(progress.values.last, asset.size)
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }
}
extension UpdateDownloadTests {
    func testHTTPBadDigestCleansTransferAndExistingDestinationIsPreserved() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ProgressHTTPProtocol.self]
        let transport = UpdateHTTPTransport(configuration: config)
        let asset = UpdateAsset(name: "test.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/test.dmg")!, size: Int64(ProgressHTTPProtocol.body.count), sha256: String(repeating: "0", count: 64))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        do { try await transport.download(asset, to: destination) { _ in }; XCTFail("Bad digest accepted") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let marker = Data("preserve".utf8); try marker.write(to: destination)
        do { try await transport.download(asset, to: destination) { _ in }; XCTFail("Existing file overwritten") } catch {}
        XCTAssertEqual(try Data(contentsOf: destination), marker)
    }
}
