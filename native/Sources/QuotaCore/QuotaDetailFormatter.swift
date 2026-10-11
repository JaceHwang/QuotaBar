import Foundation

public enum QuotaDetailRowValueStyle: Equatable, Sendable {
    case standard
    case resetCountdown
}

public struct QuotaDetailRow: Equatable, Sendable {
    public let label: String
    public let value: String
    public let valueStyle: QuotaDetailRowValueStyle
    public let accentRemainingPercent: Int?

    public init(
        label: String,
        value: String,
        valueStyle: QuotaDetailRowValueStyle = .standard,
        accentRemainingPercent: Int? = nil
    ) {
        self.label = label
        self.value = value
        self.valueStyle = valueStyle
        self.accentRemainingPercent = accentRemainingPercent
    }
}

public struct QuotaInformationEntry: Equatable, Sendable {
    public let title: String
    public let accessibilityLabel: String
    public let destination: URL

    public init(
        title: String,
        accessibilityLabel: String,
        destination: URL
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.destination = destination
    }
}

public struct QuotaTokenUsageDay: Equatable, Sendable {
    public let label: String
    public let tokens: Int64
    public let isCurrentDay: Bool

    public init(label: String, tokens: Int64, isCurrentDay: Bool) {
        self.label = label
        self.tokens = tokens
        self.isCurrentDay = isCurrentDay
    }
}

public struct QuotaTokenUsagePresentation: Equatable, Sendable {
    public let title: String
    public let totalLabel: String
    public let totalTokens: Int64
    public let days: [QuotaTokenUsageDay]
    public let delayNote: String
    public let availability: TokenUsageAvailability

    public init(
        title: String,
        totalLabel: String,
        totalTokens: Int64,
        days: [QuotaTokenUsageDay],
        delayNote: String,
        availability: TokenUsageAvailability
    ) {
        self.title = title
        self.totalLabel = totalLabel
        self.totalTokens = totalTokens
        self.days = days
        self.delayNote = delayNote
        self.availability = availability
    }
}

public struct QuotaWindowPresentation: Equatable, Sendable {
    public let label: String
    public let remainingPercent: Int

    public init(label: String, remainingPercent: Int) {
        self.label = label
        self.remainingPercent = remainingPercent
    }
}

public struct QuotaDetailContent: Equatable, Sendable {
    public let title: String
    public let remainingPercent: Int
    public let remainingSummary: String?
    public let footerName: String?
    public let footerAvatarURL: URL?
    public let resizeHint: String
    public let informationEntry: QuotaInformationEntry
    public let tokenUsage: QuotaTokenUsagePresentation?
    public let quotaWindows: [QuotaWindowPresentation]
    public let rows: [QuotaDetailRow]

    public init(
        title: String,
        remainingPercent: Int,
        remainingSummary: String? = nil,
        footerName: String? = nil,
        footerAvatarURL: URL? = nil,
        resizeHint: String = "Adjust height",
        informationEntry: QuotaInformationEntry,
        tokenUsage: QuotaTokenUsagePresentation? = nil,
        quotaWindows: [QuotaWindowPresentation] = [],
        rows: [QuotaDetailRow]
    ) {
        self.title = title
        self.remainingPercent = remainingPercent
        self.remainingSummary = remainingSummary
        self.footerName = footerName
        self.footerAvatarURL = footerAvatarURL
        self.resizeHint = resizeHint
        self.informationEntry = informationEntry
        self.tokenUsage = tokenUsage
        self.quotaWindows = quotaWindows
        self.rows = rows
    }
}

public struct QuotaDetailFormatter: Sendable {
    private static let tiboProfileURL = URL(
        string: "https://x.com/thsottiaux"
    )!
    private let resetCountdownFormatter = QuotaResetCountdownFormatter()

    public init() {}

    public func content(
        snapshot: AllowanceSnapshot,
        tokenUsage: TokenUsageSnapshot? = nil,
        footerName: String? = nil,
        footerAvatarURL: URL? = nil,
        now: Date,
        language: CodexDisplayLanguage,
        timeZone: TimeZone
    ) -> QuotaDetailContent {
        let copy = QuotaLocalization(language: language)
        var rows: [QuotaDetailRow] = []

        if let planType = snapshot.planType, !planType.isEmpty {
            rows.append(.init(label: copy.plan, value: displayPlan(planType)))
        }
        rows.append(
            .init(
                label: primaryResetLabel(snapshot: snapshot, copy: copy),
                value: displayReset(
                    snapshot.resetsAt,
                    now: now,
                    copy: copy,
                    timeZone: timeZone
                ),
                valueStyle: .resetCountdown,
                accentRemainingPercent: snapshot.remainingPercent
            )
        )
        if let secondary = snapshot.secondary {
            rows.append(
                .init(
                    label: copy.secondaryNextReset,
                    value: displayReset(
                        secondary.resetsAt,
                        now: now,
                        copy: copy,
                        timeZone: timeZone
                    ),
                    valueStyle: .resetCountdown,
                    accentRemainingPercent: secondary.remainingPercent
                )
            )
        }
        if let bank = snapshot.bank {
            rows.append(
                .init(
                    label: copy.bankAvailable,
                    value: copy.bankCount(bank.availableCount)
                )
            )
            let credits = (bank.credits ?? []).enumerated().sorted {
                left,
                right in
                switch (left.element.expiresAt, right.element.expiresAt) {
                case let (.some(leftExpiry), .some(rightExpiry)):
                    if leftExpiry == rightExpiry {
                        return left.offset < right.offset
                    }
                    return leftExpiry < rightExpiry
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return left.offset < right.offset
                }
            }
            for (index, item) in credits.enumerated() {
                rows.append(
                    .init(
                        label: copy.bankExpiryLabel(index + 1),
                        value: displayBankExpiry(
                            item.element,
                            now: now,
                            copy: copy,
                            timeZone: timeZone
                        ),
                        valueStyle: .resetCountdown,
                        accentRemainingPercent: bankExpiryAccentPercent(
                            expiresAt: item.element.expiresAt,
                            now: now
                        )
                    )
                )
            }
            if credits.isEmpty, bank.availableCount > 0 {
                rows.append(.init(label: copy.bankDetails, value: copy.noData))
            }
        } else {
            rows.append(.init(label: copy.bankAvailable, value: copy.noData))
        }

        rows.append(
            .init(
                label: "Credits",
                value: displayCredits(snapshot.credits, copy: copy)
            )
        )

        rows.append(
            .init(
                label: copy.updated,
                value: displayFreshness(
                    snapshot.receivedAt,
                    now: now,
                    copy: copy
                )
            )
        )

        let primaryWindowLabel = snapshot.windowDurationMins.map {
            copy.period(minutes: $0)
        } ?? copy.primaryQuotaWindow

        return QuotaDetailContent(
            title: copy.title,
            remainingPercent: snapshot.remainingPercent,
            remainingSummary: copy.remainingSummary(snapshot.remainingPercent),
            footerName: footerName,
            footerAvatarURL: footerAvatarURL,
            resizeHint: copy.resizeHeight,
            informationEntry: QuotaInformationEntry(
                title: copy.tiboXTitle,
                accessibilityLabel: copy.tiboXAccessibilityLabel,
                destination: Self.tiboProfileURL
            ),
            tokenUsage: displayTokenUsage(
                tokenUsage,
                allowance: snapshot,
                now: now,
                copy: copy,
                timeZone: timeZone
            ),
            quotaWindows: [
                QuotaWindowPresentation(
                    label: primaryWindowLabel,
                    remainingPercent: snapshot.remainingPercent
                ),
                snapshot.secondary.map {
                    QuotaWindowPresentation(
                        label: copy.secondaryQuotaWindowValue,
                        remainingPercent: $0.remainingPercent
                    )
                }
            ].compactMap { $0 },
            rows: rows
        )
    }

    private func displayPlan(_ value: String) -> String {
        value.prefix(1).uppercased() + value.dropFirst()
    }

    private func primaryResetLabel(
        snapshot: AllowanceSnapshot,
        copy: QuotaLocalization
    ) -> String {
        guard let minutes = snapshot.windowDurationMins, minutes <= 300 else {
            return copy.nextReset
        }
        return copy.primaryNextReset
    }

    private func displayCredits(
        _ credits: CreditBalance?,
        copy: QuotaLocalization
    ) -> String {
        guard let credits else {
            return copy.noData
        }
        if credits.unlimited {
            return copy.unlimited
        }
        if credits.hasCredits {
            return credits.balance ?? copy.available
        }
        return copy.none
    }

    private func displayReset(
        _ date: Date,
        now: Date,
        copy: QuotaLocalization,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = copy.locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = copy.resetTimestampDateFormat
        let relative = resetCountdownFormatter.string(
            from: now,
            to: date,
            language: copy.language
        )
        let openingParenthesis = copy.openingParenthesis.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return "\(relative)\n\(openingParenthesis)\(formatter.string(from: date))\(copy.closingParenthesis)"
    }

    private func displayTokenUsage(
        _ tokenUsage: TokenUsageSnapshot?,
        allowance: AllowanceSnapshot,
        now: Date,
        copy: QuotaLocalization,
        timeZone: TimeZone
    ) -> QuotaTokenUsagePresentation? {
        guard let tokenUsage else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let currentDay = calendar.startOfDay(for: now)
        let displayDays = TokenUsageWindow.referenceDays(
            from: tokenUsage,
            allowance: allowance,
            now: now,
            timeZone: timeZone
        )
        let placeholderDays = displayDays.map {
            QuotaTokenUsageDay(
                label: copy.tokenUsageDayLabel($0.date, timeZone: timeZone),
                tokens: 0,
                isCurrentDay: $0.date == currentDay
            )
        }
        guard tokenUsage.availability == .available,
              let cycle = TokenUsageWindow.currentCycle(
                  from: tokenUsage,
                  allowance: allowance,
                  now: now,
                  timeZone: timeZone
              )
        else {
            return QuotaTokenUsagePresentation(
                title: copy.tokenUsageTitle,
                totalLabel: copy.tokenUsageUnavailable,
                totalTokens: 0,
                days: placeholderDays,
                delayNote: copy.tokenUsageUnavailable,
                availability: tokenUsage.availability == .available
                    ? .unavailable : tokenUsage.availability
            )
        }

        return QuotaTokenUsagePresentation(
            title: copy.tokenUsageTitle,
            totalLabel: copy.tokenUsageTotal(
                copy.compactTokenCount(cycle.totalTokens)
            ),
            totalTokens: cycle.totalTokens,
            days: displayDays.map {
                QuotaTokenUsageDay(
                    label: copy.tokenUsageDayLabel($0.date, timeZone: timeZone),
                    tokens: $0.tokens,
                    isCurrentDay: $0.date == currentDay
                )
            },
            delayNote: copy.tokenUsageDelayNote,
            availability: .available
        )
    }

    private func displayBankExpiry(
        _ credit: BankResetCredit,
        now: Date,
        copy: QuotaLocalization,
        timeZone: TimeZone
    ) -> String {
        let status = credit.status?.lowercased()
        guard let expiry = credit.expiresAt else {
            switch status {
            case "used":
                return "\(copy.noExpiry) · \(copy.used)"
            case "expired":
                return "\(copy.noExpiry) · \(copy.expired)"
            default:
                return copy.noExpiry
            }
        }
        let expiryDescription = displayReset(
            expiry,
            now: now,
            copy: copy,
            timeZone: timeZone
        )
        switch status {
        case "used":
            return "\(expiryDescription) · \(copy.used)"
        case "expired":
            return "\(expiryDescription) · \(copy.expired)"
        default:
            return expiry <= now
                ? "\(expiryDescription) · \(copy.expired)"
                : expiryDescription
        }
    }

    private func bankExpiryAccentPercent(
        expiresAt: Date?,
        now: Date
    ) -> Int? {
        guard let expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining <= 3 * 24 * 60 * 60 {
            return 10
        }
        if remaining <= 7 * 24 * 60 * 60 {
            return 49
        }
        return 100
    }

    private func displayFreshness(
        _ receivedAt: Date,
        now: Date,
        copy: QuotaLocalization
    ) -> String {
        let seconds = max(0, now.timeIntervalSince(receivedAt))
        if seconds < 60 {
            return copy.justNow
        }
        if seconds < 3_600 {
            return copy.freshness(minutes: Int(seconds / 60))
        }
        return copy.freshness(hours: Int(seconds / 3_600))
    }
}
