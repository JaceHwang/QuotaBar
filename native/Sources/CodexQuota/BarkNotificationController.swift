import Foundation
import QuotaCore

@MainActor final class BarkNotificationController {
    enum Status { case unconfigured, configured, unavailable, invalidKey, sending, accepted, failed, unknown, persistenceFailure, capacity, historyRecovery }
    private let defaults: UserDefaults
    private let secrets: any BarkSecretStore
    private let transport: any BarkPushTransport
    private let deliveries: BarkDeliveryStore
    private let now: () -> Date
    private(set) var preferences: BarkPreferences
    private(set) var configured = false
    private(set) var status: Status = .unconfigured
    private(set) var lastOperation: Date?
    private(set) var testing = false
    var draft = ""
    var onChange: (() -> Void)?
    var onConfigurationChange: (() -> Void)?
    private struct Pending {
        let token: UUID; let identity: BarkEventIdentity; let message: ExperienceNotification
        let valid: () -> Bool; let accepted: () -> Void; let configuration: String
        var isTest: Bool { message.kind == .test }
    }
    private struct Known { let at: Date; let valid: () -> Bool }
    private var known: [BarkEventIdentity: Known] = [:]
    private var suppressionBlocked = false
    private var suppressionCapacityExceeded = false
    private var queue: [Pending] = []
    private var active: Pending?
    private var worker: Task<Void, Never>?
    private var workerRun = UUID()
    private var stopped = false
    init(defaults: UserDefaults, secrets: any BarkSecretStore, transport: any BarkPushTransport, deliveries: BarkDeliveryStore, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.secrets = secrets; self.transport = transport; self.deliveries = deliveries; self.now = now
        preferences = (defaults.data(forKey: "bark.preferences").flatMap { try? JSONDecoder().decode(BarkPreferences.self, from: $0) } ?? BarkPreferences()).validated()
        do { configured = try secrets.read().map(BarkPayload.isValidDeviceKey) ?? false; status = configured ? .configured : .unconfigured }
        catch { status = .unavailable }
        if !configured { preferences.enabled = false; persist() }
        if deliveries.needsBaseline { preferences.enabled = false; persist(); status = .historyRecovery }
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(preferences), forKey: "bark.preferences") }
    private func changed(_ status: Status) { self.status = status; lastOperation = now(); onChange?() }
    @discardableResult func saveKey(_ input: String) -> Bool {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BarkPayload.isValidDeviceKey(key) else { changed(.invalidKey); return false }
        do { try secrets.save(key) } catch { changed(.unavailable); return false }
        cancelAll(); preferences.configurationGeneration = UUID().uuidString; configured = true; draft = ""; onConfigurationChange?(); let baseline = persistSuppression(); if !baseline { preferences.enabled = false }; persist(); changed(baseline ? .configured : .persistenceFailure); return true
    }
    @discardableResult func clearKey() -> Bool {
        cancelAll(); preferences.enabled = false; preferences.configurationGeneration = UUID().uuidString; persist()
        do { try secrets.clear() } catch { changed(.unavailable); return false }
        configured = false; draft = ""; persist(); changed(.unconfigured); return true
    }
    @discardableResult func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            do {
                guard let key = try secrets.read(), BarkPayload.isValidDeviceKey(key) else {
                    cancelAll(); configured = false; preferences.enabled = false; persist(); changed(.unconfigured); return false
                }
                configured = true
            } catch { cancelAll(); preferences.enabled = false; persist(); changed(.unavailable); return false }
        }
        cancelAll()
        if enabled { onConfigurationChange?(); guard persistSuppression() else { preferences.enabled = false; persist(); changed(.persistenceFailure); return false } }
        preferences.enabled = enabled; persist(); onChange?(); return true
    }
    private func pruneKnown() {
        known = known.filter { now().timeIntervalSince($0.value.at) <= 30 * 86400 || $0.value.valid() }
    }
    private func persistSuppression() -> Bool {
        pruneKnown()
        guard !suppressionCapacityExceeded else { return false }
        suppressionBlocked = !deliveries.establishBaseline(identities: Array(known.keys), now: now())
        return !suppressionBlocked
    }
    func suppress(_ identities: [BarkEventIdentity], valid: @escaping (BarkEventIdentity) -> Bool = { _ in false }) {
        pruneKnown()
        for identity in identities {
            guard known[identity] != nil || known.count < 256 else { suppressionBlocked = true; suppressionCapacityExceeded = true; return }
            known[identity] = Known(at: now(), valid: { valid(identity) })
        }
    }
    func enqueue(_ message: ExperienceNotification, valid: @escaping () -> Bool, accepted: @escaping () -> Void) {
        guard !stopped, message.kind != .test, !message.id.hasPrefix("preview-") else { return }
        let identity = BarkEventIdentity(id: message.id, generation: message.reminderGeneration)
        pruneKnown()
        let alreadyKnown = known[identity] != nil
        guard alreadyKnown || known.count < 256 else { changed(.capacity); return }
        known[identity] = Known(at: now(), valid: { [weak self] in guard let self else { return false }; return valid() && message.valid(now: self.now()) })
        guard !alreadyKnown, !suppressionBlocked, preferences.enabled, configured, valid(), message.valid(now: now()), queue.count + (active == nil ? 0 : 1) < 32 else { return }
        if deliveries.needsBaseline { _ = deliveries.establishBaseline(identities: Array(known.keys), now: now()); return }
        queue.append(Pending(token: UUID(), identity: identity, message: message, valid: valid, accepted: accepted, configuration: preferences.configurationGeneration)); start()
    }
    private func start() {
        guard worker == nil, !queue.isEmpty, !stopped else { return }
        let run = UUID(); workerRun = run
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if workerRun == run { active = nil; worker = nil; start() } }
            while !Task.isCancelled, workerRun == run, !stopped, !queue.isEmpty {
                let item = queue.removeFirst(); active = item
                defer {
                    if workerRun == run {
                        active = nil
                        if item.isTest { testing = false; onChange?() }
                    }
                }
                guard item.valid(), item.message.valid(now: now()), item.configuration == preferences.configurationGeneration, (item.isTest || preferences.enabled) else { active = nil; continue }
                do {
                    guard let key = try secrets.read(), BarkPayload.isValidDeviceKey(key) else { changed(.unconfigured); active = nil; continue }
                    let payload = try BarkPayload.encode(deviceKey: key, title: item.message.title, body: item.message.body)
                    let protected = Set(known.filter { $0.value.valid() }.map(\.key))
                    if !item.isTest {
                        guard deliveries.reserve(identity: item.identity, now: now(), protected: protected) else { changed(deliveries.hasPersistenceError ? .persistenceFailure : .capacity); active = nil; continue }
                    }
                    changed(.sending)
                    let result = await transport.send(payload)
                    guard !Task.isCancelled, workerRun == run, active?.token == item.token, item.configuration == preferences.configurationGeneration, item.valid(), item.message.valid(now: now()), !stopped else { if workerRun == run { active = nil }; continue }
                    switch result {
                    case .accepted: if !item.isTest { deliveries.markAccepted(identity: item.identity, now: now()) }; changed(.accepted); item.accepted()
                    case .rejected: changed(.failed)
                    case .unknown: changed(.unknown)
                    }
                } catch { if workerRun == run && !Task.isCancelled { changed(.unavailable) } }
            }
        }
    }
    private func cancelActive() {
        workerRun = UUID(); active = nil; worker?.cancel(); worker = nil; start()
    }
    func cancel(id: String) { queue.removeAll { $0.message.id == id }; if active?.message.id == id { cancelActive() } }
    func cancel(epoch: String) { queue.removeAll { $0.message.epoch == epoch }; if active?.message.epoch == epoch { cancelActive() } }
    func cancelInvalid() { queue.removeAll { !$0.valid() }; if let active, !active.valid() { cancelActive() } }
    private func cancelAll() { queue = []; workerRun = UUID(); active = nil; worker?.cancel(); worker = nil; testing = false }
    func stop() { stopped = true; cancelAll() }
    func sendTest(title: String, body: String) {
        guard !stopped, configured, !testing, queue.count + (active == nil ? 0 : 1) < 32 else { return }
        testing = true
        let message = ExperienceNotification(id: "bark-test-" + UUID().uuidString, kind: .test, epoch: nil, title: title, body: body, createdAt: now(), validUntil: now().addingTimeInterval(30))
        queue.append(Pending(token: UUID(), identity: BarkEventIdentity(id: message.id), message: message, valid: { true }, accepted: {}, configuration: preferences.configurationGeneration)); onChange?(); start()
    }
    func waitUntilIdle() async { while let task = worker { await task.value } }
}
