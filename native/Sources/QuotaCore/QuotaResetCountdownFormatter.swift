import Foundation

public struct QuotaResetCountdownFormatter: Sendable {
    public init() {}

    public func string(
        from now: Date,
        to reset: Date,
        language: CodexDisplayLanguage
    ) -> String {
        let seconds = max(0, reset.timeIntervalSince(now))
        guard seconds >= 60 else {
            return "<1m"
        }

        if seconds < 3_600 {
            let minutes = Int(seconds / 60)
            switch language {
            case .simplifiedChinese:
                return "\(minutes)分钟"
            case .traditionalChinese:
                return "\(minutes)分鐘"
            case .english:
                return "\(minutes)m"
            }
        }

        let hours = Int(seconds / 3_600)
        let days = hours / 24
        let remainingHours = hours % 24
        switch language {
        case .simplifiedChinese:
            return "\(days)天\(remainingHours)小时"
        case .traditionalChinese:
            return "\(days)天\(remainingHours)小時"
        case .english:
            return "\(days)d \(remainingHours)h"
        }
    }
}
