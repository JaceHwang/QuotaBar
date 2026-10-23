import Foundation
public enum ExperienceNotificationKind: Int, Sendable { case recovery = 0, bank = 1, update = 2, test = 3 }
public struct ExperienceNotification: Sendable {
    public let reminderGeneration: String
    public let id: String
    public var deliveryToken: String? = nil
    public let kind: ExperienceNotificationKind
    public let epoch: String?
    public let title: String
    public let body: String
    public let createdAt: Date
    public var validUntil: Date? = nil
    public init(id: String, kind: ExperienceNotificationKind, epoch: String?, title: String, body: String, createdAt: Date, validUntil: Date? = nil, reminderGeneration: String = "initial") {
        self.reminderGeneration = reminderGeneration; self.id = id; self.kind = kind; self.epoch = epoch; self.title = title; self.body = body; self.createdAt = createdAt; self.validUntil = validUntil
    }
    public func valid(now: Date) -> Bool {
        now >= createdAt.addingTimeInterval(-5) && (validUntil.map { now < $0 } ?? true) && (kind != .recovery || now.timeIntervalSince(createdAt) <= 300)
    }
}
public struct ExperienceNotificationQueue {
    private var messages: [ExperienceNotification] = []
    public init() {}
    public mutating func enqueue(_ message: ExperienceNotification) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message); messages.sort { $0.kind.rawValue < $1.kind.rawValue }
        if messages.count > 32 { messages.removeLast() }
    }
    public mutating func cancel(epoch: String) { messages.removeAll { $0.epoch == epoch } }
    public mutating func next(now: Date) -> ExperienceNotification? {
        messages.removeAll { !$0.valid(now: now) }
        return messages.isEmpty ? nil : messages.removeFirst()
    }
}
public struct ExperienceCopy {
    private let language: CodexDisplayLanguage
    public init(_ language: CodexDisplayLanguage) { self.language = language }
    public func text(_ en: String, _ zh: String, _ tw: String) -> String {
        switch language { case .english: return en; case .simplifiedChinese: return zh; case .traditionalChinese: return tw }
    }
    public func period(_ minutes: Int?) -> String {
        guard let minutes else { return text("Quota", "额度", "額度") }
        if minutes < 60 { return "\(minutes)" + text(" minutes", " 分钟", " 分鐘") }
        return minutes >= 1440 ? "\(minutes/1440)" + text(" days", " 天", " 天") : "\(minutes/60)" + text(" hours", " 小时", " 小時")
    }
    public func moodLabel(_ mood: QuotaMood) -> String {
        switch mood {
        case .good: return text("Quota available", "额度充足", "額度充足")
        case .low: return text("Quota low", "额度偏低", "額度偏低")
        case .exhausted: return text("A quota window is depleted", "有额度周期已耗尽", "有額度週期已耗盡")
        case .unavailable: return text("Quota data unavailable or stale", "额度数据暂不可用或已过期", "額度資料暫不可用或已過期")
        case .recovered: return text("Quota restored", "额度已恢复", "額度已恢復")
        }
    }
    public func recoveryBody(_ quota: AllowanceSnapshot) -> String {
        [quota.primary, quota.secondary].compactMap { $0 }.map { w in
            period(w.windowDurationMins) + text(" remaining ", "额度剩余 ", "額度剩餘 ") + "\(w.remainingPercent)%" + (w.usedPercent >= 100 ? text(" (still depleted)", "（仍耗尽）", "（仍耗盡）") : "")
        }.joined(separator: "; ")
    }
    public func bankBody(_ events: [BankExpiryEvent]) -> String {
        let groups = Dictionary(grouping: events, by: \.stage)
        return groups.keys.sorted(by: >).map { stage in
            let rows = groups[stage] ?? [], count = rows.reduce(0) { $0 + $1.count }
            let expires = rows.map(\.expiresAt).min() ?? Date()
            let date = DateFormatter(); date.locale = Locale(identifier: language == .english ? "en_US" : language == .simplifiedChinese ? "zh_CN" : "zh_TW"); date.dateFormat = "yyyy/MM/dd HH:mm"
            return text("\(count) known reset credits expire within \(stage) hours; earliest: ", "已知 \(count) 次重置权益将在 \(stage) 小时内到期，最近：", "已知 \(count) 次重置權益將在 \(stage) 小時內到期，最近：") + date.string(from: expires)
        }.joined(separator: "\n")
    }
}
