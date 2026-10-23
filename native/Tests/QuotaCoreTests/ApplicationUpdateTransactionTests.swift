import XCTest
@testable import QuotaCore
final class ApplicationUpdateTransactionTests: XCTestCase {
    func testAtomicReplacementRollbackAndInterruptedRecovery() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("QuotaBar.app"), candidate = root.appendingPathComponent("candidate")
        for path in [target, candidate] { try fm.createDirectory(at: path, withIntermediateDirectories: true) }
        try Data("old".utf8).write(to: target.appendingPathComponent("version")); try Data("new".utf8).write(to: candidate.appendingPathComponent("version"))
        let transaction = ApplicationUpdateTransaction(target: target)
        XCTAssertThrowsError(try transaction.install(candidate: candidate, validate: { _ in }, health: { throw CocoaError(.executableNotLoadable) }))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "old")
        try transaction.install(candidate: candidate, validate: { _ in }, health: {})
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "new")
        // A crash after the old bundle moved but before activation must restore it.
        let store = root.appendingPathComponent(".QuotaBar-update")
        let backup = store.appendingPathComponent("backup-crash")
        try fm.moveItem(at: target, to: backup)
        try Data("{\"backup\":\"backup-crash\",\"stage\":\"stage-crash\"}".utf8).write(to: store.appendingPathComponent("journal.json"))
        try transaction.recover()
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("version").path))
    }
    func testJobRejectsExpiryReplayAndWrongTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let job = UpdateInstallJob(operationID: UUID().uuidString, target: "/wrong/QuotaBar.app", parentPID: 123, nonce: String(repeating: "a", count: 64), expiresAt: Date().addingTimeInterval(600), release: try fixtureRelease())
        XCTAssertThrowsError(try job.validate(directory: root, expectedTarget: "/right/QuotaBar.app", now: Date()))
        XCTAssertThrowsError(try job.validate(directory: root, expectedTarget: job.target, now: Date().addingTimeInterval(601)))
        try job.validate(directory: root, expectedTarget: job.target, now: Date())
        let receipts = root.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        try job.write(receipts)
        try job.receipt("succeeded", directory: receipts)
        XCTAssertEqual(UpdateInstallJob.consumeResult(in: root, expectedTarget: job.target), .succeeded)
        XCTAssertNil(UpdateInstallJob.consumeResult(in: root, expectedTarget: job.target))
        try Data().write(to: root.appendingPathComponent("consumed"))
        XCTAssertThrowsError(try job.validate(directory: root, expectedTarget: job.target, now: Date()))
    }
    private func fixtureRelease() throws -> TrustedUpdateRelease {
        let asset = UpdateAsset(name: "a", url: URL(string: "https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/a")!, size: 1, sha256: String(repeating: "a", count: 64))
        return TrustedUpdateRelease(version: "2.0.0", platform: "macos-arm64", sourceCommit: String(repeating: "b", count: 40), package: asset, provenance: asset)
    }
}
