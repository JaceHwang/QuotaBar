import Foundation
import CryptoKit
import XCTest
@testable import QuotaCore

private actor FixtureUpdateTransport: UpdateTransport {
    let release: Data, tag: Data, proof: Data
    let corrupt: Bool, late: Bool
    private(set) var downloads = 0
    init(corrupt: Bool = false, late: Bool = false, wrongSource: Bool = false, version: String = "2.0.0") throws {
        self.corrupt = corrupt; self.late = late
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../contracts/in-app-updates/release-cases.json").standardizedFileURL
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [[String: Any]]
        var r = rows[1]["release"] as! [String: Any]
        if version != "2.0.0" {
            r["prerelease"] = true
            let json = String(data: try JSONSerialization.data(withJSONObject: r), encoding: .utf8)!.replacingOccurrences(of: "2.0.0", with: version)
            r = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        }
        proof = try JSONSerialization.data(withJSONObject: ["kind": "release", "workingTreeDirty": false, "version": version, "releaseTag": "v" + version, "sourceCommit": String(repeating: wrongSource ? "c" : "b", count: 40)])
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
        downloads += 1
        let bytes = asset.name.hasSuffix(".dmg") ? Data((corrupt ? "corrupt" : "package").utf8) : proof
        try bytes.write(to: url); progress(Int64(bytes.count))
        if late { try? await Task.sleep(for: .milliseconds(50)) }
    }
}
final class UpdateDownloadTests: XCTestCase {
    func testRetryReusesVerifiedAssetsInFreshInstallationDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let transport = try FixtureUpdateTransport()
        let client = UpdateDownloadClient(transport: transport)
        let first = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        try FileManager.default.removeItem(at: first.directory)
        let second = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        XCTAssertNotEqual(first.directory, second.directory)
        let downloads = await transport.downloads
        XCTAssertEqual(downloads, 2, "A retry must reuse the verified package and provenance")
        XCTAssertEqual(try Data(contentsOf: second.archive), Data("package".utf8))
    }
    func testCorruptCachedAssetIsDownloadedAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let transport = try FixtureUpdateTransport(), client = UpdateDownloadClient(transport: transport)
        let first = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        try FileManager.default.removeItem(at: first.directory)
        try Data("badfile".utf8).write(to: root.appendingPathComponent("downloads").appendingPathComponent(first.release.package.sha256))
        let retry = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        let count = await transport.downloads
        XCTAssertEqual(count, 3)
        XCTAssertEqual(try Data(contentsOf: retry.archive), Data("package".utf8))
    }
    func testVerifiedLegacyJobIsImportedWithoutNetworkDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let transport = try FixtureUpdateTransport(), client = UpdateDownloadClient(transport: transport)
        let first = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("downloads"))
        let second = try await client.download(version: "2.0.0", platform: "macos-arm64", currentVersion: "1.3.0", cache: root)
        let count = await transport.downloads
        XCTAssertEqual(count, 2)
        XCTAssertNotEqual(first.directory, second.directory)
    }
    func testCacheRejectsConcurrentReservationAndSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let first = try UpdateDownloadCache(root: root)
        XCTAssertThrowsError(try UpdateDownloadCache(root: root))
        withExtendedLifetime(first) {}
        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: root.appendingPathComponent("downloads"))
        XCTAssertThrowsError(try UpdateDownloadCache(root: linked))
    }
    func testBetaDownloadRequiresConsentAndVerifiesMatchingProvenance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let client = UpdateDownloadClient(transport: try FixtureUpdateTransport(version: "2.0.0-beta.1"))
        do { _ = try await client.download(version: "2.0.0-beta.1", platform: "macos-arm64", currentVersion: "1.9.0", cache: root); XCTFail("Beta allowed without consent") } catch {}
        let value = try await client.download(version: "2.0.0-beta.1", platform: "macos-arm64", currentVersion: "1.9.0", cache: root, allowBeta: true)
        XCTAssertEqual(value.release.version, "2.0.0-beta.1")
    }
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
            let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
            XCTAssertFalse(entries.contains { UUID(uuidString: $0) != nil }, "Failed attempts must not retain installation jobs")
            XCTAssertTrue(entries.contains("downloads"), "Reusable cache must outlive the attempt")
        }
    }
}

private final class RangeHTTPProtocol: URLProtocol {
    static let body = Data(repeating: 7, count: 196608)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let name = request.url!.lastPathComponent
        if name == "restart.dmg" || (name == "fallback.dmg" && request.value(forHTTPHeaderField: "Range") == nil) {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(Self.body.count)])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self); return
        }
        if name == "fallback.dmg" {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 416, httpVersion: nil, headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self); return
        }
        guard request.value(forHTTPHeaderField: "Range") == "bytes=65536-" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let remainder = Self.body.dropFirst(65536)
        let headers = ["Content-Length": String(remainder.count), "Content-Range": name == "invalid.dmg" ? "bytes 0-131071/196608" : "bytes 65536-196607/196608"]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(remainder)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class TruncatedHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "196608"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(RangeHTTPProtocol.body.prefix(65536)))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class FullHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "196608"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: RangeHTTPProtocol.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension UpdateDownloadTests {
    func testCancellationRetainsDownloadedPrefixForRetry() async throws {
        let body = RangeHTTPProtocol.body
        let asset = UpdateAsset(name: "test.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/test.dmg")!, size: Int64(body.count), sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: destination) }
        let initial = URLSessionConfiguration.ephemeral; initial.protocolClasses = [FullHTTPProtocol.self]
        let task = Task {
            try await UpdateHTTPTransport(configuration: initial).download(asset, to: destination) { received in
                if received >= 65536 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { try await task.value; XCTFail("Cancelled transfer completed") } catch {}
        XCTAssertEqual(try Data(contentsOf: destination), Data(body.prefix(65536)))
        let resumed = URLSessionConfiguration.ephemeral; resumed.protocolClasses = [RangeHTTPProtocol.self]
        try await UpdateHTTPTransport(configuration: resumed).download(asset, to: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }
    func testInterruptedDownloadKeepsPrefixAndResumesOnNextRequest() async throws {
        let body = RangeHTTPProtocol.body
        let asset = UpdateAsset(name: "test.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/test.dmg")!, size: Int64(body.count), sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: destination) }
        let interrupted = URLSessionConfiguration.ephemeral; interrupted.protocolClasses = [TruncatedHTTPProtocol.self]
        do { try await UpdateHTTPTransport(configuration: interrupted).download(asset, to: destination) { _ in }; XCTFail("Truncated response accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: destination), Data(body.prefix(65536)))
        let resumed = URLSessionConfiguration.ephemeral; resumed.protocolClasses = [RangeHTTPProtocol.self]
        try await UpdateHTTPTransport(configuration: resumed).download(asset, to: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }
    func testHTTPFullAnd416ResponsesRestartPartialDownload() async throws {
        for name in ["restart.dmg", "fallback.dmg"] {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RangeHTTPProtocol.self]
            let body = RangeHTTPProtocol.body
            let asset = UpdateAsset(name: name, url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/\(name)")!, size: Int64(body.count), sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: destination) }
            try Data(repeating: 1, count: 65536).write(to: destination)
            try await UpdateHTTPTransport(configuration: config).download(asset, to: destination) { _ in }
            XCTAssertEqual(try Data(contentsOf: destination), body)
        }
    }
    func testHTTPRejectsIncorrectRangeWithoutModifyingPrefix() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RangeHTTPProtocol.self]
        let body = RangeHTTPProtocol.body
        let asset = UpdateAsset(name: "invalid.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/invalid.dmg")!, size: Int64(body.count), sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: destination) }
        let prefix = Data(body.prefix(65536)); try prefix.write(to: destination)
        do { try await UpdateHTTPTransport(configuration: config).download(asset, to: destination) { _ in }; XCTFail("Invalid range accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: destination), prefix)
    }
    func testHTTPResumesExistingPartialFileWithVerifiedRange() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RangeHTTPProtocol.self]
        let body = RangeHTTPProtocol.body
        let asset = UpdateAsset(name: "test.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/test.dmg")!, size: Int64(body.count), sha256: SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: destination) }
        try Data(body.prefix(65536)).write(to: destination)
        try await UpdateHTTPTransport(configuration: config).download(asset, to: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), body)
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
    func testHTTPBadDigestRemovesInvalidCompleteDownload() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ProgressHTTPProtocol.self]
        let transport = UpdateHTTPTransport(configuration: config)
        let asset = UpdateAsset(name: "test.dmg", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/test.dmg")!, size: Int64(ProgressHTTPProtocol.body.count), sha256: String(repeating: "0", count: 64))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        do { try await transport.download(asset, to: destination) { _ in }; XCTFail("Bad digest accepted") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let marker = Data("preserve".utf8); try marker.write(to: destination)
        do { try await transport.download(asset, to: destination) { _ in }; XCTFail("Existing file overwritten") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "A completed digest mismatch cannot remain a resumable prefix")
    }
}
