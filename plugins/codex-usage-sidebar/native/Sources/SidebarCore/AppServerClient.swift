import Foundation

public enum AppServerClientError: Error, Equatable, Sendable {
    case transportUnavailable
    case notInitialized
    case remoteError
}

public enum AppServerEvent: Equatable, Sendable {
    case failure(method: String, message: String)
    case loginURL(URL)
    case loginCompleted(Bool)
    case loggedOut
    case accountCleared
    case quota(AllowanceSnapshot)
    case tokenUsage(TokenUsageSnapshot)
    case identity(AccountIdentity)
}

public actor AppServerClient {
    public nonisolated let events: AsyncStream<AppServerEvent>
    private let eventContinuation: AsyncStream<AppServerEvent>.Continuation
    public nonisolated let snapshots: AsyncStream<AllowanceSnapshot>
    public nonisolated let tokenUsages: AsyncStream<TokenUsageSnapshot>
    public nonisolated let accounts: AsyncStream<AccountIdentity>
    public private(set) var restartAttemptCount = 0

    private enum PendingMethod {
        case initialize
        case readRateLimits
        case readTokenUsage
        case readAccount
        case login
        case logout
        case cancelLogin
    }

    private let snapshotContinuation: AsyncStream<AllowanceSnapshot>.Continuation
    private let tokenUsageContinuation: AsyncStream<TokenUsageSnapshot>.Continuation
    private let accountContinuation: AsyncStream<AccountIdentity>.Continuation
    private let transportFactory: @Sendable () throws -> any LineTransport
    private let restartDelaysNanoseconds: [UInt64]
    private var transport: (any LineTransport)?
    private var readerTask: Task<Void, Never>?
    private var sequencer = JSONRPCSequencer()
    private var pending: [Int: PendingMethod] = [:]
    private var sentAt: [Int: Date] = [:]
    private var initialized = false
    private var stopping = false
    private var generation = 0
    private var restartIndex = 0
    private var lastSnapshot: AllowanceSnapshot?
    private var rateLimitReadNeededAfterPending = false
    private var tokenUsageReadNeededAfterPending = false
    private var accountReadNeededAfterInitialization = false
    private var loginID: String?
    private var suppressAccountData = false

    public init(
        transportFactory: @escaping @Sendable () throws -> any LineTransport,
        restartDelaysNanoseconds: [UInt64] = [
            500_000_000,
            2_000_000_000,
            5_000_000_000
        ]
    ) {
        self.transportFactory = transportFactory
        let eventPair = AsyncStream<AppServerEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        events = eventPair.stream
        eventContinuation = eventPair.continuation
        self.restartDelaysNanoseconds = restartDelaysNanoseconds
        let pair = AsyncStream<AllowanceSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        snapshots = pair.stream
        snapshotContinuation = pair.continuation
        let tokenUsagePair = AsyncStream<TokenUsageSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        tokenUsages = tokenUsagePair.stream
        tokenUsageContinuation = tokenUsagePair.continuation
        let accountPair = AsyncStream<AccountIdentity>.makeStream(
            bufferingPolicy: .bufferingNewest(2)
        )
        accounts = accountPair.stream
        accountContinuation = accountPair.continuation
    }

    public init(
        executableURL: URL,
        environmentOverrides: [String: String] = [:],
        restartDelaysNanoseconds: [UInt64] = [
            500_000_000,
            2_000_000_000,
            5_000_000_000
        ]
    ) {
        self.init(
            transportFactory: {
                ProcessLineTransport(
                    executableURL: executableURL,
                    environmentOverrides: environmentOverrides
                )
            },
            restartDelaysNanoseconds: restartDelaysNanoseconds
        )
    }

    public func start() async throws {
        guard transport == nil else {
            return
        }
        stopping = false
        restartIndex = 0
        restartAttemptCount = 0
        try await startSession()
    }

    public func refresh() async throws {
        guard !suppressAccountData else { throw AppServerClientError.remoteError }
        guard initialized else {
            throw AppServerClientError.notInitialized
        }
        if !hasPendingRateLimitRead {
            _ = try await sendRequest(method: "account/rateLimits/read")
        }
        if hasPendingTokenUsageRead {
            tokenUsageReadNeededAfterPending = true
        } else {
            _ = try await sendRequest(method: "account/usage/read")
        }
    }

    public func readAccount() async throws {
        guard transport != nil else {
            throw AppServerClientError.notInitialized
        }
        guard initialized else {
            accountReadNeededAfterInitialization = true
            return
        }
        _ = try await sendRequest(method: "account/read", params: [:])
    }

    public func login() async throws {
        guard initialized else { throw AppServerClientError.notInitialized }
        clearAccountRequests()
        _ = try await sendRequest(method: "account/login/start", params: ["type": "chatgpt"])
    }

    public func expireRequests(before date: Date) async {
        for id in sentAt.filter({ $0.value < date }).map(\.key) {
            sentAt.removeValue(forKey: id)
            guard let method = pending.removeValue(forKey: id) else { continue }
            let name: String
            switch method {
            case .initialize: name = "initialize"
            case .readRateLimits: name = "account/rateLimits/read"
            case .readTokenUsage: name = "account/usage/read"
            case .readAccount: name = "account/read"
            case .login: name = "account/login/start"
            case .logout: name = "account/logout"
            case .cancelLogin: name = "account/login/cancel"
            }
            eventContinuation.yield(.failure(method: name, message: "Request timeout"))
            if case .initialize = method { await restartAfterFailure(); return }
        }
    }

    public func cancelLogin() async throws {
        guard let loginID else { return }
        _ = try await sendRequest(method: "account/login/cancel", params: ["loginId": loginID])
        self.loginID = nil
    }

    public func logout() async throws {
        clearAccountRequests()
        _ = try await sendRequest(method: "account/logout")
    }

    private func clearAccountRequests() {
        suppressAccountData = true
        lastSnapshot = nil
        for (id, method) in pending {
            switch method {
            case .readRateLimits, .readTokenUsage, .readAccount:
                pending.removeValue(forKey: id); sentAt.removeValue(forKey: id)
            default: break
            }
        }
        rateLimitReadNeededAfterPending = false
        tokenUsageReadNeededAfterPending = false
        eventContinuation.yield(.accountCleared)
    }

    public func stop() async {
        stopping = true
        readerTask?.cancel()
        readerTask = nil
        let activeTransport = transport
        transport = nil
        initialized = false
        pending.removeAll()
        lastSnapshot = nil
        rateLimitReadNeededAfterPending = false
        tokenUsageReadNeededAfterPending = false
        accountReadNeededAfterInitialization = false
        await activeTransport?.stop()
        snapshotContinuation.finish()
        eventContinuation.finish()
        tokenUsageContinuation.finish()
        accountContinuation.finish()
    }

    private func startSession() async throws {
        let newTransport = try transportFactory()
        generation += 1
        let sessionGeneration = generation
        transport = newTransport
        initialized = false
        pending.removeAll()
        lastSnapshot = nil
        rateLimitReadNeededAfterPending = false
        tokenUsageReadNeededAfterPending = false

        do {
            try await newTransport.start()
        } catch {
            transport = nil
            throw error
        }

        readerTask = Task { [weak self] in
            for await line in newTransport.lines {
                await self?.handle(line: line, generation: sessionGeneration)
            }
            await self?.transportFinished(generation: sessionGeneration)
        }

        let parameters: [String: Any] = [
            "clientInfo": [
                "name": "codex-usage-sidebar",
                "title": "Codex Usage Sidebar",
                "version": "1.0.0"
            ],
            "capabilities": [
                "experimentalApi": true,
                "requestAttestation": false
            ]
        ]
        _ = try await sendRequest(method: "initialize", params: parameters)
    }

    private func sendRequest(
        method: String,
        params: [String: Any]? = nil
    ) async throws -> Int {
        guard let transport else {
            throw AppServerClientError.transportUnavailable
        }
        let id = sequencer.nextRequestID()
        var object: [String: Any] = [
            "method": method,
            "id": id
        ]
        if let params {
            object["params"] = params
        }
        let line = try encode(object)
        switch method {
        case "initialize":
            pending[id] = .initialize
        case "account/rateLimits/read":
            pending[id] = .readRateLimits
        case "account/usage/read":
            pending[id] = .readTokenUsage
        case "account/read":
            pending[id] = .readAccount
        case "account/login/start": pending[id] = .login
        case "account/logout": pending[id] = .logout
        case "account/login/cancel": pending[id] = .cancelLogin
        default:
            throw AppServerClientError.remoteError
        }
        do {
            sentAt[id] = Date()
            try await transport.send(line: line)
        } catch {
            sentAt.removeValue(forKey: id)
            pending.removeValue(forKey: id)
            await restartAfterFailure()
            throw error
        }
        return id
    }

    private func sendNotification(method: String) async throws {
        guard let transport else {
            throw AppServerClientError.transportUnavailable
        }
        try await transport.send(line: encode(["method": method]))
    }

    private func handle(line: String, generation: Int) async {
        guard generation == self.generation else {
            return
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                as? [String: Any]
        else {
            return
        }

        if object["method"] as? String == "account/rateLimits/updated" {
            guard !suppressAccountData else { return }
            if let snapshot = try? RateLimitDecoder.decodeNotification(Data(line.utf8)) {
                let enriched = snapshot.mergingSupplementary(from: lastSnapshot)
                lastSnapshot = enriched
                snapshotContinuation.yield(enriched)
                eventContinuation.yield(.quota(enriched))
            }
            if initialized {
                if hasPendingRateLimitRead {
                    rateLimitReadNeededAfterPending = true
                } else {
                    do {
                        _ = try await sendRequest(method: "account/rateLimits/read")
                    } catch {
                        await restartAfterFailure()
                    }
                }
            }
            return
        }

        if object["method"] as? String == "account/login/completed" {
            let success = (object["params"] as? [String: Any])?["success"] as? Bool ?? false
            loginID = nil
            if success { suppressAccountData = false }
            eventContinuation.yield(.loginCompleted(success))
            if success { try? await refresh(); try? await readAccount() }
            return
        }

        guard
            let number = object["id"] as? NSNumber,
            let method = pending.removeValue(forKey: number.intValue)
        else {
            return
        }
        guard object["error"] == nil else {
            sentAt.removeValue(forKey: number.intValue)
            let methodName: String
            switch method {
            case .initialize: methodName = "initialize"
            case .readRateLimits: methodName = "account/rateLimits/read"
            case .readTokenUsage: methodName = "account/usage/read"
            case .readAccount: methodName = "account/read"
            case .login: methodName = "account/login/start"
            case .logout: methodName = "account/logout"
            case .cancelLogin: methodName = "account/login/cancel"
            }
            let remote = object["error"] as? [String: Any]
            eventContinuation.yield(.failure(method: methodName, message: remote?["message"] as? String ?? "Request failed"))
            switch method {
            case .readRateLimits:
                await sendDeferredRateLimitReadIfNeeded()
            case .readTokenUsage:
                yieldUnavailableTokenUsage(from: Data(line.utf8))
                await sendDeferredTokenUsageReadIfNeeded()
            case .readAccount:
                break
            case .initialize:
                break
            case .login, .logout, .cancelLogin: break
            }
            return
        }

        sentAt.removeValue(forKey: number.intValue)
        switch method {
        case .initialize:
            initialized = true
            do {
                try await sendNotification(method: "initialized")
                _ = try await sendRequest(method: "account/rateLimits/read")
                _ = try await sendRequest(method: "account/usage/read")
                await sendDeferredAccountReadIfNeeded()
            } catch {
                await restartAfterFailure()
            }
        case .readRateLimits:
            if let snapshot = try? RateLimitDecoder.decodeResponse(Data(line.utf8)) {
                let value = rateLimitReadNeededAfterPending
                    ? (lastSnapshot?.mergingSupplementary(from: snapshot) ?? snapshot)
                    : snapshot
                lastSnapshot = value
                snapshotContinuation.yield(value)
                eventContinuation.yield(.quota(value))
            } else {
                eventContinuation.yield(.failure(method: "account/rateLimits/read", message: "Unsupported quota response"))
            }
            await sendDeferredRateLimitReadIfNeeded()
        case .readTokenUsage:
            do {
                let usage = try TokenUsageDecoder.decodeResponse(Data(line.utf8))
                tokenUsageContinuation.yield(usage)
                eventContinuation.yield(.tokenUsage(usage))
            } catch {
                yieldUnavailableTokenUsage(from: Data(line.utf8))
            }
            await sendDeferredTokenUsageReadIfNeeded()
        case .readAccount:
            if let identity = try? AccountIdentityDecoder.decodeResponse(
                Data(line.utf8)
            ) {
                accountContinuation.yield(identity)
                eventContinuation.yield(.identity(identity))
            }
        case .login:
            let result = object["result"] as? [String: Any]
            loginID = result?["loginId"] as? String
            if let address = result?["authUrl"] as? String, let url = URL(string: address), url.scheme == "https" {
                eventContinuation.yield(.loginURL(url))
            }
        case .logout:
            lastSnapshot = nil
            eventContinuation.yield(.loggedOut)
        case .cancelLogin:
            eventContinuation.yield(.loginCompleted(false))
        }
    }

    private func sendDeferredRateLimitReadIfNeeded() async {
        guard initialized, rateLimitReadNeededAfterPending else {
            return
        }
        rateLimitReadNeededAfterPending = false
        do {
            _ = try await sendRequest(method: "account/rateLimits/read")
        } catch {
            await restartAfterFailure()
        }
    }

    private func sendDeferredTokenUsageReadIfNeeded() async {
        guard initialized, tokenUsageReadNeededAfterPending else {
            return
        }
        tokenUsageReadNeededAfterPending = false
        do {
            _ = try await sendRequest(method: "account/usage/read")
        } catch {
            await restartAfterFailure()
        }
    }

    private func sendDeferredAccountReadIfNeeded() async {
        guard initialized, accountReadNeededAfterInitialization else {
            return
        }
        accountReadNeededAfterInitialization = false
        do {
            _ = try await sendRequest(method: "account/read", params: [:])
        } catch {
            await restartAfterFailure()
        }
    }

    private func yieldUnavailableTokenUsage(from data: Data) {
        let availability: TokenUsageAvailability
        do {
            _ = try TokenUsageDecoder.decodeResponse(data)
            availability = .unavailable
        } catch TokenUsageDecodingError.unsupported {
            availability = .unsupported
        } catch {
            availability = .unavailable
        }
        let unavailable = TokenUsageSnapshot(
                receivedAt: Date(),
                dailyBuckets: [],
                summary: nil,
                availability: availability
            )
        tokenUsageContinuation.yield(unavailable)
        eventContinuation.yield(.tokenUsage(unavailable))
    }

    private var hasPendingRateLimitRead: Bool {
        pending.values.contains { method in
            if case .readRateLimits = method {
                return true
            }
            return false
        }
    }

    private var hasPendingTokenUsageRead: Bool {
        pending.values.contains { method in
            if case .readTokenUsage = method {
                return true
            }
            return false
        }
    }

    private func transportFinished(generation: Int) async {
        guard generation == self.generation, !stopping else {
            return
        }
        transport = nil
        readerTask = nil
        initialized = false
        eventContinuation.yield(.failure(method: "initialize", message: "Runtime exited"))
        pending.removeAll()
        rateLimitReadNeededAfterPending = false
        tokenUsageReadNeededAfterPending = false
        scheduleRestart()
    }

    private func restartAfterFailure() async {
        generation += 1
        let activeTransport = transport
        transport = nil
        initialized = false
        pending.removeAll()
        rateLimitReadNeededAfterPending = false
        tokenUsageReadNeededAfterPending = false
        await activeTransport?.stop()
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !stopping, restartIndex < restartDelaysNanoseconds.count else {
            return
        }
        let delay = restartDelaysNanoseconds[restartIndex]
        restartIndex += 1
        restartAttemptCount += 1
        let expectedGeneration = generation

        Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            await self?.performRestart(expectedGeneration: expectedGeneration)
        }
    }

    private func performRestart(expectedGeneration: Int) async {
        guard
            !stopping,
            transport == nil,
            generation == expectedGeneration
        else {
            return
        }
        do {
            try await startSession()
        } catch {
            scheduleRestart()
        }
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw LineTransportError.invalidLine
        }
        return line
    }
}
