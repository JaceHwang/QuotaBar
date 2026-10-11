import Foundation

public enum StandalonePhase: String, Sendable {
    case loading, ready, offline, needsLogin, signingIn, unsupported
}

public struct StandaloneState: Sendable {
    public private(set) var phase: StandalonePhase = .loading
    public private(set) var lastSuccess: Date?
    private var nextRefresh = Date.distantPast
    private var failureCount = 0
    public init() {}
    public mutating func beginLogin() { phase = .signingIn }
    public mutating func receivedQuota(at date: Date) {
        phase = .ready
        lastSuccess = date
        failureCount = 0
        nextRefresh = date.addingTimeInterval(60)
    }
    public mutating func loginCompleted(success: Bool) {
        phase = success ? .loading : .needsLogin
        nextRefresh = .distantPast
    }
    public mutating func receiveError(method: String, message: String, at date: Date = Date()) {
        guard method == "account/rateLimits/read" || method == "initialize" else { return }
        let value = message.lowercased()
        if value.contains("401") || value.contains("token_expired") || value.contains("authentication") || value.contains("not logged") {
            phase = .needsLogin
        } else if value.contains("method not found") || value.contains("unsupported") {
            phase = .unsupported
        } else {
            phase = .offline
            failureCount += 1
            nextRefresh = date.addingTimeInterval(min(300, 15 * pow(2, Double(min(failureCount - 1, 5)))))
        }
    }
    public func shouldRefresh(at date: Date) -> Bool {
        phase != .needsLogin && phase != .signingIn && phase != .unsupported && date >= nextRefresh
    }
}
