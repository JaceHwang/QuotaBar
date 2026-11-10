import XCTest
import QuotaCore
@testable import CodexQuota
@MainActor final class ApplicationUpdateServiceTests: XCTestCase {
    func testImmediateRetryWaitsForCancelledWorkerCleanup() async throws {
        let calls = UpdateTestCounter(), gate = UpdateTestGate()
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, _ in
            await calls.increment()
            if await calls.count() == 1 { await gate.wait() }
        })
        service.start(version: "2.0.0")
        for _ in 0..<100 { if await calls.count() == 1 { break }; try await Task.sleep(for: .milliseconds(5)) }
        service.cancel(); service.start(version: "2.0.0")
        try await Task.sleep(for: .milliseconds(50))
        let beforeCleanup = await calls.count()
        XCTAssertEqual(beforeCleanup, 1, "Retry must wait for the old worker to release its cache lock")
        await gate.open()
        for _ in 0..<100 { if await calls.count() == 2 { break }; try await Task.sleep(for: .milliseconds(5)) }
        let afterCleanup = await calls.count()
        XCTAssertEqual(afterCleanup, 2)
    }
    func testExplicitStartDoubleClickAndLateCancellationCannotInstall() async throws {
        let calls = UpdateTestCounter()
        let gate = UpdateTestGate()
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, emit in
            await calls.increment(); emit(ApplicationUpdateProgress(.downloading, received: 1, total: 3))
            await gate.wait() // deliberately ignores cancellation until explicitly released
        })
        var ready = 0; service.onReady = { ready += 1 }
        XCTAssertEqual(service.progress.phase, .idle)
        try await Task.sleep(for: .milliseconds(20)); let initial = await calls.count(); XCTAssertEqual(initial, 0)
        service.start(version: "2.0.0"); service.start(version: "3.0.0"); XCTAssertEqual(service.targetVersion, "2.0.0")
        for _ in 0..<100 {
            if await calls.count() == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        service.cancel()
        await gate.open()
        await service.waitForCleanup()
        let count = await calls.count(); XCTAssertEqual(count, 1); XCTAssertEqual(ready, 0); XCTAssertEqual(service.progress.phase, .cancelled)
    }
    func testLateProgressCannotReenableCancellationAfterReady() async throws {
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, emit in
            Task { try? await Task.sleep(for: .milliseconds(10)); emit(ApplicationUpdateProgress(.downloading)) }
        })
        service.onReady = {}
        service.start(version: "2.0.0"); try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.progress.phase, .handingOff)
        service.cancel(); XCTAssertEqual(service.progress.phase, .handingOff)
    }
    func testStartupReadsReceiptCreatedAfterHealthAcknowledgement() async throws {
        var reads = 0
        let service = ApplicationUpdateService(currentVersion: "1.3.0", resultReader: { reads += 1; return reads > 1 ? .succeeded : nil })
        XCTAssertEqual(service.progress.phase, .idle)
        try await Task.sleep(for: .milliseconds(3200))
        XCTAssertEqual(service.progress.phase, .succeeded)
    }
    func testExitWaitsForCancelledPreparationToFinishCleanup() async throws {
        let finished = UpdateTestCounter()
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, _ in
            try? await Task.sleep(for: .milliseconds(80)); await finished.increment()
        })
        service.start(version: "2.0.0"); service.cancel()
        await service.waitForCleanup()
        let count = await finished.count(); XCTAssertEqual(count, 1)
        XCTAssertEqual(service.progress.phase, .cancelled)
    }
    func testFailureRetainsSafeErrorCodeWithoutSensitiveMessage() async throws {
        let service = ApplicationUpdateService(currentVersion: "1.4.0", execute: { _, _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "secret signed download URL"])
        })
        service.start(version: "1.5.0")
        for _ in 0..<100 { if service.progress.phase == .failed { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(service.progress.phase, .failed)
        XCTAssertTrue(service.progress.failure?.contains("-1001") == true)
        XCTAssertFalse(service.progress.failure?.contains("secret") == true)
    }
    func testReadyAndFailureAreTerminalAndRetryable() async throws {
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, _ in throw CocoaError(.fileReadCorruptFile) })
        service.start(version: "2.0.0"); try await Task.sleep(for: .milliseconds(30)); XCTAssertEqual(service.progress.phase, .failed)
        service.start(version: "2.0.0"); try await Task.sleep(for: .milliseconds(30)); XCTAssertEqual(service.progress.phase, .failed)
    }
}
private actor UpdateTestCounter { var value = 0; func increment() { value += 1 }; func count() -> Int { value } }

private actor UpdateTestGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
