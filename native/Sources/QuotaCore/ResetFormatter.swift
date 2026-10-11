import Foundation

public struct ResetIndicatorSummary: Equatable, Sendable {
    public let primary: String
    public let secondary: String?
    public let primaryRemainingPercent: Int
    public let secondaryRemainingPercent: Int?

    public init(
        primary: String,
        secondary: String?,
        primaryRemainingPercent: Int,
        secondaryRemainingPercent: Int?
    ) {
        self.primary = primary
        self.secondary = secondary
        self.primaryRemainingPercent = primaryRemainingPercent
        self.secondaryRemainingPercent = secondaryRemainingPercent
    }
}

public struct ResetFormatter: Sendable {
    public init() {}

    public func indicatorSummary(
        snapshot: AllowanceSnapshot,
        language: CodexDisplayLanguage,
        timeZone: TimeZone,
        maxWidth: Double
    ) -> ResetIndicatorSummary {
        let localization = QuotaLocalization(language: language)
        let primaryWindowLabel = snapshot.windowDurationMins.map {
            localization.period(minutes: $0)
        } ?? localization.primaryQuotaWindow
        let primary = indicatorLine(
            windowLabel: primaryWindowLabel,
            remainingPercent: snapshot.remainingPercent,
            date: snapshot.resetsAt,
            localization: localization,
            timeZone: timeZone,
            maxWidth: maxWidth
        )
        let secondary = snapshot.secondary.map {
            indicatorLine(
                windowLabel: localization.secondaryQuotaWindowValue,
                remainingPercent: $0.remainingPercent,
                date: $0.resetsAt,
                localization: localization,
                timeZone: timeZone,
                maxWidth: maxWidth
            )
        }
        return ResetIndicatorSummary(
            primary: primary,
            secondary: secondary,
            primaryRemainingPercent: snapshot.remainingPercent,
            secondaryRemainingPercent: snapshot.secondary?.remainingPercent
        )
    }

    public func label(
        snapshot: AllowanceSnapshot,
        now _: Date,
        language: CodexDisplayLanguage,
        timeZone: TimeZone,
        maxWidth: Double
    ) -> String {
        let localization = QuotaLocalization(language: language)
        let format: String
        if maxWidth >= 130 {
            format = localization.fullIndicatorDateFormat
        } else if maxWidth >= 90 {
            format = "EEE HH:mm"
        } else {
            format = "HH:mm"
        }

        let formatter = DateFormatter()
        formatter.locale = localization.locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format

        return "\(snapshot.remainingPercent)% · \(formatter.string(from: snapshot.resetsAt))"
    }

    private func indicatorLine(
        windowLabel: String,
        remainingPercent: Int,
        date: Date,
        localization: QuotaLocalization,
        timeZone: TimeZone,
        maxWidth: Double
    ) -> String {
        let format: String
        if maxWidth >= 130 {
            format = localization.fullIndicatorDateFormat
        } else if maxWidth >= 90 {
            format = "EEE HH:mm"
        } else {
            format = "HH:mm"
        }
        let formatter = DateFormatter()
        formatter.locale = localization.locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return "\(windowLabel) \(remainingPercent)% · \(formatter.string(from: date))"
    }
}
