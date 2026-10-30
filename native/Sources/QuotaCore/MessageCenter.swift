import Foundation

public struct MessageCenterKey: Codable, Hashable, Sendable {
    public let id: String
    public let generation: String
    public let epoch: String?
    public init(id: String, generation: String = "initial", epoch: String? = nil) { self.id = id; self.generation = generation; self.epoch = epoch }
}
public struct MessageCenterRecord: Codable, Equatable, Sendable {
    public let key: MessageCenterKey
    public let category: NotificationCategory
    public var title: String
    public var body: String
    public let createdAtMilliseconds: Int64
    public var readAtMilliseconds: Int64?
    public var channels: Set<NotificationChannel>
    public var createdAt: Date { Date(timeIntervalSince1970: Double(createdAtMilliseconds) / 1000) }
    public init(key: MessageCenterKey, category: NotificationCategory, title: String, body: String, createdAtMilliseconds: Int64, readAtMilliseconds: Int64? = nil, channels: Set<NotificationChannel>) {
        self.key = key; self.category = category; self.title = title; self.body = body; self.createdAtMilliseconds = createdAtMilliseconds; self.readAtMilliseconds = readAtMilliseconds; self.channels = channels
    }
}

/// Durable business-message snapshots. This store never owns or restores delivery work.
public final class MessageCenterStore {
    private struct Document: Codable { let schema: Int; let messages: [MessageCenterRecord] }
    private let url: URL
    private var durable: [MessageCenterKey: MessageCenterRecord] = [:]
    private var pending: [MessageCenterKey: MessageCenterRecord] = [:]
    private var loadBlocked = false
    public private(set) var records: [MessageCenterRecord] = []
    public private(set) var error: String?
    public var unreadCount: Int { records.reduce(0) { $0 + ($1.readAtMilliseconds == nil ? 1 : 0) } }
    public var hasUnpersistedMessages: Bool { !pending.isEmpty }
    public func isPersisted(_ key: MessageCenterKey) -> Bool { durable[key] != nil && pending[key] == nil }
    public init(url: URL) { self.url = url; _ = reload() }

    private func merged(_ first: MessageCenterRecord, _ other: MessageCenterRecord) -> MessageCenterRecord {
        var result = first
        result.channels.formUnion(other.channels)
        if let time = other.readAtMilliseconds { result.readAtMilliseconds = first.readAtMilliseconds.map { min($0, time) } ?? time }
        return result
    }
    private func combined() -> [MessageCenterKey: MessageCenterRecord] {
        var result = durable
        for (key, row) in pending { result[key] = result[key].map { merged($0, row) } ?? row }
        return result
    }
    private func refresh() {
        records = combined().values.sorted { a, b in
            if a.createdAtMilliseconds != b.createdAtMilliseconds { return a.createdAtMilliseconds > b.createdAtMilliseconds }
            if a.key.id != b.key.id { return a.key.id < b.key.id }
            if a.key.generation != b.key.generation { return a.key.generation < b.key.generation }
            return (a.key.epoch ?? "") < (b.key.epoch ?? "")
        }
    }
    private func valid(_ row: MessageCenterRecord) -> Bool {
        !row.key.id.isEmpty && row.key.id.utf16.count <= 4096 && !row.key.generation.isEmpty && row.key.generation.utf16.count <= 4096 &&
        (row.key.epoch.map { !$0.isEmpty && $0.utf16.count <= 4096 } ?? true) && row.title.utf16.count <= 4096 && row.body.utf16.count <= 65536 &&
        row.createdAtMilliseconds >= 0 && row.createdAtMilliseconds <= 253402300799999 &&
        (row.readAtMilliseconds.map { $0 >= 0 && $0 <= 253402300799999 } ?? true) && !row.channels.isEmpty
    }
    @discardableResult public func reload() -> Bool {
        do {
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
                let known = combined(); durable = [:]; pending = known; loadBlocked = false
                if known.isEmpty { error = nil; refresh(); return true }
                return persist(known, stageOnFailure: true)
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.schema == 1, document.messages.allSatisfy(valid), Set(document.messages.map(\.key)).count == document.messages.count else { throw CocoaError(.fileReadCorruptFile) }
            durable = Dictionary(uniqueKeysWithValues: document.messages.map { ($0.key, $0) }); loadBlocked = false
            if pending.isEmpty { error = nil; refresh(); return true }
            return persist(combined(), stageOnFailure: true)
        } catch {
            loadBlocked = true; self.error = error.localizedDescription; refresh(); return false
        }
    }
    @discardableResult public func append(_ row: MessageCenterRecord) -> Bool { append([row]) }
    @discardableResult public func append(_ rows: [MessageCenterRecord]) -> Bool {
        guard rows.allSatisfy(valid) else { error = "Invalid message record."; return false }
        var next = combined()
        for row in rows { next[row.key] = next[row.key].map { merged($0, row) } ?? row }
        if loadBlocked { stage(next); refresh(); return false }
        if next == durable && pending.isEmpty { return true }
        return persist(next, stageOnFailure: true)
    }
    @discardableResult public func markRead(_ key: MessageCenterKey, atMilliseconds time: Int64) -> Bool {
        guard !loadBlocked else { return false }
        var next = combined(); guard var row = next[key] else { return false }
        guard row.readAtMilliseconds == nil else { return true }
        guard time >= 0 && time <= 253402300799999 else { return false }
        row.readAtMilliseconds = max(row.createdAtMilliseconds, time); next[key] = row
        return persist(next, stageOnFailure: false)
    }
    @discardableResult public func markAllRead(atMilliseconds time: Int64) -> Bool {
        guard !loadBlocked, time >= 0 && time <= 253402300799999 else { return false }
        var next = combined()
        guard next.values.contains(where: { $0.readAtMilliseconds == nil }) else { return true }
        for (key, var row) in next where row.readAtMilliseconds == nil { row.readAtMilliseconds = max(row.createdAtMilliseconds, time); next[key] = row }
        return persist(next, stageOnFailure: false)
    }
    private func stage(_ next: [MessageCenterKey: MessageCenterRecord]) { pending = next.filter { durable[$0.key] != $0.value } }
    private func persist(_ next: [MessageCenterKey: MessageCenterRecord], stageOnFailure: Bool) -> Bool {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Document(schema: 1, messages: Array(next.values)))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            durable = next; pending = [:]; error = nil; loadBlocked = false; refresh(); return true
        } catch {
            self.error = error.localizedDescription
            if stageOnFailure { stage(next) }
            refresh(); return false
        }
    }
}
