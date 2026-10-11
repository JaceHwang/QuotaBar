import Foundation

public struct RelativeIntervalFormatter: Sendable {
    public init() {}

    public func string(
        from now: Date,
        to target: Date,
        language: CodexDisplayLanguage
    ) -> String {
        let interval = target.timeIntervalSince(now)
        let totalSeconds = Int(abs(interval).rounded(.down))
        let value: String

        if totalSeconds >= 86_400 {
            let days = totalSeconds / 86_400
            let hours = totalSeconds % 86_400 / 3_600
            value = "\(days)d\(hours)h"
        } else if totalSeconds >= 3_600 {
            let hours = totalSeconds / 3_600
            let minutes = totalSeconds % 3_600 / 60
            value = "\(hours)h\(minutes)m"
        } else if totalSeconds >= 60 {
            value = "\(totalSeconds / 60)m"
        } else {
            value = "<1m"
        }

        guard interval < 0 else {
            return value
        }
        return "\(value)\(QuotaLocalization(language: language).pastSuffix)"
    }
}
