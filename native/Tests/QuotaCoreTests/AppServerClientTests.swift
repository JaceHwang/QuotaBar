import Foundation
import XCTest
@testable import QuotaCore

final class AppServerClientTests: XCTestCase {
    func testLogoutRejectsLateQuotaResponsesAndNotifications() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)
        let received = Task<[AllowanceSnapshot], Never> {
            var values: [AllowanceSnapshot] = []
            for await value in client.snapshots { values.append(value) }
            return values
        }
        try await client.logout()
        transport.emit(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":24,"resetsAt":1785628824}}}}"#)
        transport.emit(#"{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":24,"resetsAt":1785628824}}}}"#)
        transport.emit(#"{"id":4,"result":{}}"#)
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.stop()
        let values = await received.value
        XCTAssertTrue(values.isEmpty)
    }

    func testMalformedPrimaryQuotaResponseReportsProtocolFailure() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)
        let received = Task<AppServerEvent?, Never> {
            for await value in client.events { return value }
            return nil
        }
        transport.emit(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":"invalid"}}}}"#)
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.stop()
        let value = await received.value
        XCTAssertEqual(value, .failure(method: "account/rateLimits/read", message: "Unsupported quota response"))
    }

    func testExpiredPendingReadDoesNotSuppressEveryFutureRefresh() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)
        await client.expireRequests(before: .distantFuture)
        try await client.refresh()
        XCTAssertEqual(transport.sentLines.count, 6)
        await client.stop()
    }

    func testLoginReturnsBrowserURLAndCompletionNotification() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)
        try await client.login()
        try await eventually { transport.sentLines.count == 5 }
        let loginRequest = try XCTUnwrap(transport.sentLines.last.flatMap(parse))
        XCTAssertEqual(loginRequest["method"] as? String, "account/login/start")
        let result = Task<AppServerEvent?, Never> {
            for await event in client.events { if case .loginURL = event { return event } }
            return nil
        }
        transport.emit(#"{"id":4,"result":{"type":"chatgpt","loginId":"test-login","authUrl":"https://auth.openai.com/test"}}"#)
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.stop()
        let value = await result.value
        XCTAssertEqual(value, .loginURL(URL(string: "https://auth.openai.com/test")!))
    }

    func testRateLimitErrorIsDeliveredInsteadOfSilentlyDiscarded() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        let result = Task<AppServerEvent?, Never> {
            for await event in client.events { return event }
            return nil
        }
        try await completeHandshake(client: client, transport: transport)
        transport.emit(#"{"id":2,"error":{"code":-32603,"message":"401 token_expired"}}"#)
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.stop()
        let event = await result.value
        XCTAssertEqual(event, .failure(method: "account/rateLimits/read", message: "401 token_expired"))
    }

    func testInitializesThenReadsRateLimitsAndTokenUsageWithIncreasingIDs() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })

        try await client.start()
        try await eventually {
            transport.sentLines.count == 1
        }

        let initialize = try XCTUnwrap(parse(transport.sentLines[0]))
        XCTAssertEqual(initialize["method"] as? String, "initialize")
        XCTAssertEqual((initialize["id"] as? NSNumber)?.intValue, 1)

        transport.emit(#"{"id":1,"result":{"serverInfo":{"name":"codex"}}}"#)
        try await eventually {
            transport.sentLines.count == 4
        }

        let initialized = try XCTUnwrap(parse(transport.sentLines[1]))
        let rateLimits = try XCTUnwrap(parse(transport.sentLines[2]))
        let tokenUsage = try XCTUnwrap(parse(transport.sentLines[3]))
        XCTAssertEqual(initialized["method"] as? String, "initialized")
        XCTAssertNil(initialized["id"])
        XCTAssertEqual(rateLimits["method"] as? String, "account/rateLimits/read")
        XCTAssertEqual((rateLimits["id"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(tokenUsage["method"] as? String, "account/usage/read")
        XCTAssertEqual((tokenUsage["id"] as? NSNumber)?.intValue, 3)

        await client.stop()
    }

    func testResponseIDEmitsSnapshotAndMalformedJSONDoesNotStopReader() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let snapshotTask = Task<AllowanceSnapshot?, Never> {
            for await snapshot in client.snapshots {
                return snapshot
            }
            return nil
        }

        transport.emit("{malformed")
        transport.emit(
            #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":24,"resetsAt":1785628824}}}}"#
        )

        let snapshotValue = await snapshotTask.value
        let snapshot = try XCTUnwrap(snapshotValue)
        XCTAssertEqual(snapshot.remainingPercent, 76)
        await client.stop()
    }

    func testReadAccountEmitsCodexIdentity() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let identityTask = Task<AccountIdentity?, Never> {
            var iterator = client.accounts.makeAsyncIterator()
            return await iterator.next()
        }

        try await client.readAccount()
        try await eventually {
            transport.sentLines.count == 5
        }
        transport.emit(
            #"{"id":4,"result":{"account":{"displayName":"Jace","email":"jace@example.com"}}}"#
        )

        let identityValue = await identityTask.value
        let identity = try XCTUnwrap(identityValue)
        XCTAssertEqual(identity.preferredName, "Jace")
        XCTAssertEqual(identity.email, "jace@example.com")
        await client.stop()
    }

    func testRefreshCoalescesPendingReadAndResumesAfterResponse() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        try await client.refresh()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(transport.sentLines.count, 4)

        let snapshotTask = Task<AllowanceSnapshot?, Never> {
            var iterator = client.snapshots.makeAsyncIterator()
            return await iterator.next()
        }
        transport.emit(
            #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":24,"resetsAt":1785628824}}}}"#
        )
        _ = await snapshotTask.value

        try await client.refresh()
        try await eventually {
            transport.sentLines.count == 5
        }
        let refresh = try XCTUnwrap(parse(transport.sentLines[4]))
        XCTAssertEqual(refresh["method"] as? String, "account/rateLimits/read")
        XCTAssertEqual((refresh["id"] as? NSNumber)?.intValue, 4)

        await client.stop()
    }

    func testUpdatedNotificationReplacesOlderSnapshot() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let snapshotsTask = Task {
            var values: [AllowanceSnapshot] = []
            for await snapshot in client.snapshots {
                values.append(snapshot)
                if values.count == 2 {
                    return values
                }
            }
            return values
        }

        transport.emit(
            #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":24,"resetsAt":1785628824}}}}"#
        )
        transport.emit(
            #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":31,"resetsAt":1785628824}}}}"#
        )

        let values = await snapshotsTask.value
        XCTAssertEqual(values.map(\.remainingPercent), [76, 69])
        await client.stop()
    }

    func testUpdatedNotificationPreservesBankDataAndRequestsFullRefresh() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let snapshotsTask = Task {
            var values: [AllowanceSnapshot] = []
            for await snapshot in client.snapshots {
                values.append(snapshot)
                if values.count == 2 {
                    return values
                }
            }
            return values
        }

        transport.emit(
            """
            {"id":2,"result":{
              "rateLimits":{
                "limitId":"codex",
                "primary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":1785628824},
                "planType":"plus"
              },
              "rateLimitResetCredits":{"availableCount":2,"credits":[]}
            }}
            """
        )
        transport.emit(
            #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":31,"resetsAt":1785628824}}}}"#
        )

        let values = await snapshotsTask.value
        XCTAssertEqual(values.map(\.remainingPercent), [76, 69])
        XCTAssertEqual(values.last?.windowDurationMins, 10080)
        XCTAssertEqual(values.last?.planType, "plus")
        XCTAssertEqual(values.last?.bank?.availableCount, 2)

        try await eventually {
            transport.sentLines.count == 5
        }
        let refresh = try XCTUnwrap(parse(transport.sentLines[4]))
        XCTAssertEqual(refresh["method"] as? String, "account/rateLimits/read")
        XCTAssertEqual((refresh["id"] as? NSNumber)?.intValue, 4)

        await client.stop()
    }

    func testNotificationDuringPendingReadNeverRevertsAndQueuesFollowUp() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let snapshotsTask = Task {
            var values: [AllowanceSnapshot] = []
            for await snapshot in client.snapshots {
                values.append(snapshot)
                if values.count == 2 {
                    return values
                }
            }
            return values
        }

        transport.emit(
            #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":31,"resetsAt":1785628824}}}}"#
        )
        transport.emit(
            """
            {"id":2,"result":{
              "rateLimits":{
                "limitId":"codex",
                "primary":{"usedPercent":24,"resetsAt":1785628824},
                "planType":"plus"
              },
              "rateLimitResetCredits":{"availableCount":1,"credits":[]}
            }}
            """
        )

        let values = await snapshotsTask.value
        XCTAssertEqual(values.map(\.remainingPercent), [69, 69])
        XCTAssertEqual(values.last?.planType, "plus")
        XCTAssertEqual(values.last?.bank?.availableCount, 1)
        try await eventually {
            transport.sentLines.count == 5
        }
        if transport.sentLines.count == 5 {
            let followUp = try XCTUnwrap(parse(transport.sentLines[4]))
            XCTAssertEqual(followUp["method"] as? String, "account/rateLimits/read")
            XCTAssertEqual((followUp["id"] as? NSNumber)?.intValue, 4)
        }

        await client.stop()
    }

    func testTokenUsageResponseEmitsIndependentSnapshot() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let snapshotTask = Task<TokenUsageSnapshot?, Never> {
            var iterator = client.tokenUsages.makeAsyncIterator()
            return await iterator.next()
        }
        transport.emit(
            #"{"id":3,"result":{"summary":{"lifetimeTokens":1234},"dailyUsageBuckets":[{"startDate":"2026-08-14","tokens":456}]}}"#
        )

        let snapshotValue = await snapshotTask.value
        let snapshot = try XCTUnwrap(snapshotValue)
        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.summary?.lifetimeTokens, 1_234)
        XCTAssertEqual(snapshot.dailyBuckets.map(\.tokens), [456])
        await client.stop()
    }

    func testDuplicateRefreshCoalescesPendingTokenUsageRead() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        try await client.refresh()
        try await client.refresh()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(transport.sentLines.count, 4)

        transport.emit(
            #"{"id":3,"result":{"dailyUsageBuckets":[]}}"#
        )
        try await eventually {
            transport.sentLines.count == 5
        }
        let followUp = try XCTUnwrap(parse(transport.sentLines[4]))
        XCTAssertEqual(followUp["method"] as? String, "account/usage/read")
        XCTAssertEqual((followUp["id"] as? NSNumber)?.intValue, 4)
        await client.stop()
    }

    func testUnsupportedTokenUsageDoesNotPreventRateLimitSnapshot() async throws {
        let transport = InMemoryLineTransport()
        let client = AppServerClient(transportFactory: { transport })
        try await completeHandshake(client: client, transport: transport)

        let tokenTask = Task<TokenUsageSnapshot?, Never> {
            var iterator = client.tokenUsages.makeAsyncIterator()
            return await iterator.next()
        }
        let rateTask = Task<AllowanceSnapshot?, Never> {
            var iterator = client.snapshots.makeAsyncIterator()
            return await iterator.next()
        }
        transport.emit(#"{"id":3,"error":{"code":-32601,"message":"Method not found"}}"#)
        transport.emit(
            #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":24,"resetsAt":1785628824}}}}"#
        )

        let tokenValue = await tokenTask.value
        let rateValue = await rateTask.value
        let token = try XCTUnwrap(tokenValue)
        let rate = try XCTUnwrap(rateValue)
        XCTAssertEqual(token.availability, .unsupported)
        XCTAssertTrue(token.dailyBuckets.isEmpty)
        XCTAssertEqual(rate.remainingPercent, 76)
        await client.stop()
    }

    func testTransportExitSchedulesBoundedRestart() async throws {
        let first = InMemoryLineTransport()
        let second = InMemoryLineTransport()
        let transports = TransportQueue([first, second])
        let client = AppServerClient(
            transportFactory: { try transports.next() },
            restartDelaysNanoseconds: [0]
        )

        try await client.start()
        first.finish()

        try await eventually {
            await client.restartAttemptCount == 1 && second.started
        }
        let restartAttempts = await client.restartAttemptCount
        XCTAssertEqual(restartAttempts, 1)

        second.finish()
        try await Task.sleep(nanoseconds: 20_000_000)
        let attemptsAfterSecondExit = await client.restartAttemptCount
        XCTAssertEqual(attemptsAfterSecondExit, 1)
        await client.stop()
    }

    private func completeHandshake(
        client: AppServerClient,
        transport: InMemoryLineTransport
    ) async throws {
        try await client.start()
        try await eventually {
            transport.sentLines.count == 1
        }
        transport.emit(#"{"id":1,"result":{}}"#)
        try await eventually {
            transport.sentLines.count == 4
        }
    }

    private func parse(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private func eventually(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async throws {
        let started = DispatchTime.now().uptimeNanoseconds
        while !(await condition()) {
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                XCTFail("condition was not met before timeout")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private final class InMemoryLineTransport: LineTransport, @unchecked Sendable {
    let lines: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var storage: [String] = []
    private var startStorage = false

    init() {
        let pair = AsyncStream<String>.makeStream()
        lines = pair.stream
        continuation = pair.continuation
    }

    var sentLines: [String] {
        lock.withLock { storage }
    }

    var started: Bool {
        lock.withLock { startStorage }
    }

    func start() async throws {
        lock.withLock {
            startStorage = true
        }
    }

    func send(line: String) async throws {
        lock.withLock {
            storage.append(line)
        }
    }

    func stop() async {
        continuation.finish()
    }

    func emit(_ line: String) {
        continuation.yield(line)
    }

    func finish() {
        continuation.finish()
    }
}

private final class TransportQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [InMemoryLineTransport]

    init(_ transports: [InMemoryLineTransport]) {
        self.transports = transports
    }

    func next() throws -> any LineTransport {
        try lock.withLock {
            guard !transports.isEmpty else {
                throw AppServerClientError.transportUnavailable
            }
            return transports.removeFirst()
        }
    }
}
