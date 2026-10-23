import XCTest
import QuotaCore
@testable import CodexQuota
@MainActor final class ApplicationUpdateServiceTests: XCTestCase {
    func testExplicitStartDoubleClickAndLateCancellationCannotInstall() async throws {
        let calls = UpdateTestCounter()
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, emit in
            await calls.increment(); emit(ApplicationUpdateProgress(.downloading, received: 1, total: 3))
            try? await Task.sleep(for: .milliseconds(150)) // deliberately ignores cancellation
        })
        var ready = 0; service.onReady = { ready += 1 }
        XCTAssertEqual(service.progress.phase, .idle)
        try await Task.sleep(for: .milliseconds(20)); let initial = await calls.count(); XCTAssertEqual(initial, 0)
        service.start(version: "2.0.0"); service.start(version: "2.0.0")
        try await Task.sleep(for: .milliseconds(30)); service.cancel()
        try await Task.sleep(for: .milliseconds(200))
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
    func testReadyAndFailureAreTerminalAndRetryable() async throws {
        let service = ApplicationUpdateService(currentVersion: "1.3.0", execute: { _, _ in throw CocoaError(.fileReadCorruptFile) })
        service.start(version: "2.0.0"); try await Task.sleep(for: .milliseconds(30)); XCTAssertEqual(service.progress.phase, .failed)
        service.start(version: "2.0.0"); try await Task.sleep(for: .milliseconds(30)); XCTAssertEqual(service.progress.phase, .failed)
    }
}
private actor UpdateTestCounter { var value = 0; func increment() { value += 1 }; func count() -> Int { value } }
