import Foundation

public enum TokenUsageWindow {
    public static func referenceDays(
        from snapshot: TokenUsageSnapshot,
        allowance: AllowanceSnapshot,
        now: Date,
        timeZone: TimeZone
    ) -> [TokenUsageDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let usageWindow = allowance.tokenUsageWindow
        guard let durationMins = usageWindow.windowDurationMins, durationMins > 0 else {
            let endDay = calendar.startOfDay(for: now)
            return (-6 ... 0).map { offset in
                TokenUsageDay(
                    date: calendar.date(byAdding: .day, value: offset, to: endDay) ?? endDay,
                    tokens: 0,
                    timeZone: timeZone
                )
            }
        }

        let periodStart = usageWindow.resetsAt.addingTimeInterval(-Double(durationMins) * 60)
        let startDay = calendar.startOfDay(for: periodStart)
        let latestKnownDay = calendar.startOfDay(for: min(now, usageWindow.resetsAt))
        let referenceDates = (0 ..< 7).map {
            calendar.date(byAdding: .day, value: $0, to: startDay) ?? startDay
        }

        guard snapshot.availability == .available else {
            return referenceDates.map {
                TokenUsageDay(date: $0, tokens: 0, timeZone: timeZone)
            }
        }

        var tokensByDay: [Date: Int64] = [:]
        for bucket in snapshot.dailyBuckets {
            let date = calendar.startOfDay(for: bucket.date)
            guard date >= startDay, date <= latestKnownDay else {
                continue
            }
            let (tokens, overflow) = (tokensByDay[date] ?? 0).addingReportingOverflow(bucket.tokens)
            guard !overflow else {
                return referenceDates.map {
                    TokenUsageDay(date: $0, tokens: 0, timeZone: timeZone)
                }
            }
            tokensByDay[date] = tokens
        }

        return referenceDates.map {
            TokenUsageDay(
                date: $0,
                tokens: $0 <= latestKnownDay ? tokensByDay[$0] ?? 0 : 0,
                timeZone: timeZone
            )
        }
    }

    public static func currentCycle(
        from snapshot: TokenUsageSnapshot,
        allowance: AllowanceSnapshot,
        now: Date,
        timeZone: TimeZone
    ) -> TokenUsageCycle? {
        let usageWindow = allowance.tokenUsageWindow
        guard let durationMins = usageWindow.windowDurationMins, durationMins > 0 else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let periodStart = usageWindow.resetsAt.addingTimeInterval(-Double(durationMins) * 60)
        let startDay = calendar.startOfDay(for: periodStart)
        let endDay = calendar.startOfDay(for: min(now, usageWindow.resetsAt))
        guard startDay <= endDay else {
            return TokenUsageCycle(dailyBuckets: [], totalTokens: 0)
        }

        var tokensByDay: [Date: Int64] = [:]
        for bucket in snapshot.dailyBuckets {
            let date = calendar.startOfDay(for: bucket.date)
            let (tokens, overflow) = (tokensByDay[date] ?? 0).addingReportingOverflow(bucket.tokens)
            guard !overflow else {
                return nil
            }
            tokensByDay[date] = tokens
        }
        var days: [TokenUsageDay] = []
        var totalTokens: Int64 = 0
        var day = startDay
        while day <= endDay {
            let tokens = tokensByDay[day] ?? 0
            let (nextTotal, overflow) = totalTokens.addingReportingOverflow(tokens)
            guard !overflow else {
                return nil
            }
            totalTokens = nextTotal
            days.append(TokenUsageDay(date: day, tokens: tokens, timeZone: timeZone))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }
        return TokenUsageCycle(dailyBuckets: days, totalTokens: totalTokens)
    }
}
