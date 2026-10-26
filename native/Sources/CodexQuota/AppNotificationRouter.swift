import AppKit
import UserNotifications
import QuotaCore

@MainActor final class AppNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationRouter(defaults: .standard)
    let center: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private var state = NotificationPresentationState()
    private struct Delivery { let message: ExperienceNotification; let valid: () -> Bool; let failed: () -> Void; let shown: () -> Void; let action: (() -> Void)? }
    private var deliveries: [String: Delivery] = [:]
    var bark: BarkNotificationController?
    private(set) var policyActive = false
    private(set) var policyPreferences = NotificationPolicyPreferences()
    private var policyStore: NotificationPolicyStore?
    private var snapshots: [BarkEventIdentity: NotificationDeliverySnapshot] = [:]
    private var snapshotOrder: [BarkEventIdentity] = []
    private(set) var messageStore: MessageCenterStore?
    private var messageObservers: [UUID: () -> Void] = [:]
    var currentMessageEpoch: String? { didSet { if oldValue != currentMessageEpoch { messageChanged() } } }
    var messageHistory: [MessageCenterRecord] { messageStore?.records ?? [] }
    var messageUnreadCount: Int { messageStore?.unreadCount ?? unread.count }
    var messageStorageError: String? { messageStore?.error }
    var messageHasUnpersistedMessages: Bool { messageStore?.hasUnpersistedMessages ?? false }
    func isMessagePersisted(_ key: MessageCenterKey) -> Bool { messageStore?.isPersisted(key) ?? false }
    func observeMessages(_ change: @escaping () -> Void) -> UUID { let id = UUID(); messageObservers[id] = change; return id }
    func removeMessageObserver(_ id: UUID) { messageObservers.removeValue(forKey: id) }
    private func messageChanged() { onUnreadChange?(); for change in Array(messageObservers.values) { change() } }
    func bindMessageCenter(_ store: MessageCenterStore) {
        messageStore = store
        let active = deliveries.values.filter { $0.valid() && !previews.contains($0.message.id) }.compactMap { messageRecord($0.message) }
        if !active.isEmpty { _ = store.append(active) }
        messageChanged()
    }
    private func messageRecord(_ message: ExperienceNotification) -> MessageCenterRecord? {
        guard message.kind != .test else { return nil }
        let category = message.category ?? (message.kind == .bank ? .bankExpiring72h : message.kind == .update ? .updateAvailable : .quotaRecovered)
        let channels: Set<NotificationChannel>
        if message.category != nil {
            channels = Set(NotificationChannel.allCases.filter {
                let decision = NotificationPolicy.decision(category: category, channel: $0, preferences: policyPreferences, now: Date(), threshold: message.reminderThreshold)
                return decision == .allowed || decision == .paused
            })
        } else {
            var selected: Set<NotificationChannel> = []
            if preferences.mode.usesBubble { selected.insert(.bubble) }; if preferences.mode.usesSystem { selected.insert(.system) }
            if bark?.preferences.enabled == true { selected.insert(.mobile) }; channels = selected
        }
        let time = message.createdAt.timeIntervalSince1970 * 1000
        guard !channels.isEmpty, time.isFinite, time >= 0, time <= 253402300799999 else { return nil }
        return MessageCenterRecord(key: MessageCenterKey(id: message.id, generation: message.reminderGeneration, epoch: message.epoch), category: category, title: message.title, body: message.body, createdAtMilliseconds: Int64(time), readAtMilliseconds: consumed.contains(message.id) ? Int64(Date().timeIntervalSince1970 * 1000) : nil, channels: channels)
    }
    private func captureMessage(_ message: ExperienceNotification) {
        guard let store = messageStore, let row = messageRecord(message) else { return }
        _ = store.append(row); messageChanged()
    }
    private func saveLiveRead(_ message: ExperienceNotification) {
        guard message.kind != .test, !previews.contains(message.id) else { return }
        _ = messageStore?.markRead(MessageCenterKey(id: message.id, generation: message.reminderGeneration, epoch: message.epoch), atMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
    }
    @discardableResult func markMessageRead(_ key: MessageCenterKey) -> Bool {
        let saved = messageStore?.markRead(key, atMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)) ?? false
        if saved, let live = deliveries[key.id]?.message, live.reminderGeneration == key.generation, live.epoch == key.epoch {
            consumed.insert(key.id); let active = state.activeID == key.id; state.dismiss(id: key.id, read: true)
            if active { hideBubble?(); timer?.invalidate(); timer = nil }
        }
        messageChanged(); return saved
    }
    @discardableResult func markAllMessagesRead() -> Bool {
        let saved = messageStore?.markAllRead(atMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)) ?? false
        if saved {
            let keys = Set(messageHistory.map(\.key))
            for live in deliveries.values where live.message.kind != .test {
                let key = MessageCenterKey(id: live.message.id, generation: live.message.reminderGeneration, epoch: live.message.epoch)
                if keys.contains(key) { consumed.insert(live.message.id); state.dismiss(id: live.message.id, read: true) }
            }
            hideBubble?(); timer?.invalidate(); timer = nil
        }
        messageChanged(); return saved
    }
    @discardableResult func retryMessageStorage() -> Bool { let saved = messageStore?.reload() ?? false; messageChanged(); return saved }
    @discardableResult func openMessageLatest(_ record: MessageCenterRecord) -> Bool {
        let open = record.category == .updateAvailable ? openUpdates : openDetails
        guard let open else { return false }; open(); _ = markMessageRead(record.key); return true
    }
    var policyError = false
    var onPolicyChange: (() -> Void)?
    @discardableResult func loadPolicy(store: NotificationPolicyStore, legacy: LegacyNotificationPreferences?) -> Bool {
        do {
            let value = try store.loadOrMigrate(legacy: legacy)
            policyStore = store; applyPolicy(value); policyError = store.corrupted
            return true
        } catch { policyError = true; return false }
    }
    @discardableResult func configurePolicy(_ value: NotificationPolicyPreferences) -> Bool {
        do { try policyStore?.save(value) } catch { policyError = true; return false }
        policyError = false; applyPolicy(value); return true
    }
    @discardableResult func setChannelEnabled(_ channel: NotificationChannel, enabled: Bool) -> Bool {
        var value = policyPreferences
        let oldMobile = bark?.preferences.enabled ?? false
        if channel == .mobile {
            guard let bark, bark.setEnabled(enabled) else { return false }
        }
        if enabled { value.enabledChannels.insert(channel) } else { value.enabledChannels.remove(channel) }
        guard configurePolicy(value) else {
            if channel == .mobile { _ = bark?.setEnabled(oldMobile) }
            return false
        }
        return true
    }
    private func applyPolicy(_ value: NotificationPolicyPreferences) {
        policyActive = true; policyPreferences = value
        for key in snapshots.keys { snapshots[key]?.restrict(to: value, now: Date()) }
        for delivery in deliveries.values where delivery.message.category != nil || (delivery.message.kind == .test && !previews.contains(delivery.message.id)) {
            let m = delivery.message
            if !channelAllowed(m, .bubble) {
                let active = state.activeID == m.id
                state.dismiss(id: m.id, read: false)
                if active { hideBubble?(); timer?.invalidate(); timer = nil }
            }
            if !channelAllowed(m, .system) {
                let ids = [m.id + "." + (m.deliveryToken ?? "")]
                center?.removeDeliveredNotifications(withIdentifiers: ids)
                center?.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        bark?.cancelInvalid(); onPolicyChange?(); dispatch()
    }
    private func channelAllowed(_ m: ExperienceNotification, _ channel: NotificationChannel) -> Bool {
        guard let category = m.category else {
            if policyActive && m.kind == .test { return policyPreferences.enabledChannels.contains(channel) && (channel != .bubble || !(policyPreferences.bubblePausedUntil.map { $0 > Date() } ?? false)) }
            switch channel { case .bubble: return preferences.mode.usesBubble && !preferences.paused(now: Date()); case .system: return preferences.mode.usesSystem; case .mobile: return true }
        }
        let identity = BarkEventIdentity(id: m.id, generation: m.reminderGeneration)
        return snapshots[identity]?.eligible.contains(channel) == true && NotificationPolicy.decision(category: category, channel: channel, preferences: policyPreferences, now: Date(), threshold: m.reminderThreshold) == .allowed
    }
    private func canStartChannel(_ m: ExperienceNotification, _ channel: NotificationChannel) -> Bool {
        guard m.category != nil else { return channelAllowed(m, channel) }
        return snapshots[BarkEventIdentity(id: m.id, generation: m.reminderGeneration)]?.allows(channel, preferences: policyPreferences, now: Date()) == true
    }
    private func snapshot(_ m: ExperienceNotification) {
        guard let category = m.category else { return }
        let identity = BarkEventIdentity(id: m.id, generation: m.reminderGeneration)
        guard snapshots[identity] == nil else { return }
        snapshots[identity] = NotificationDeliverySnapshot(category: category, preferences: policyPreferences, now: Date(), threshold: m.reminderThreshold)
        snapshotOrder.append(identity)
        if snapshotOrder.count > 256 { let old = snapshotOrder.removeFirst(); snapshots.removeValue(forKey: old) }
    }
    private func recordChannel(_ m: ExperienceNotification, _ channel: NotificationChannel) {
        snapshots[BarkEventIdentity(id: m.id, generation: m.reminderGeneration)]?.recordAccepted(channel)
    }
    private var sharedReceived: Set<BarkEventIdentity> = []
    private var received: Set<String> = []
    private var previews: Set<String> = []
    private var consumed: Set<String> = []
    private var failedDeliveries: Set<String> = []
    private var cancelledTokens: Set<String> = []
    private var canPresent = false
    private var timer: Timer?
    private var stopped = false
    var presentBubble: ((ExperienceNotification) -> Bool)?
    var hideBubble: (() -> Void)?
    var onUnreadChange: (() -> Void)?
    var openDetails: (() -> Void)?
    var openBank: (() -> Void)?
    var sendSystem: ((ExperienceNotification, @escaping (Bool) -> Void) -> Void)?
    var preferences: NotificationPresentationPreferences {
        defaults.data(forKey: "notifications.presentation").flatMap { try? JSONDecoder().decode(NotificationPresentationPreferences.self, from: $0) } ?? NotificationPresentationPreferences()
    }
    var unread: [NotificationUnreadItem] {
        state.unread(now: Date()).filter { !$0.message.id.hasPrefix("preview-") }.map { item in
            NotificationUnreadItem(message: item.message, stale: item.stale || !(deliveries[item.message.id]?.valid() ?? false))
        }
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        center = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init()
        if center != nil { center?.delegate = self }
    }
    func configure(_ value: NotificationPresentationPreferences) {
        let channelChanged = preferences.mode != value.mode
        defaults.set(try? JSONEncoder().encode(value), forKey: "notifications.presentation")
        suspend(); retryFailedDeliveries(allUndelivered: channelChanged); dispatch()
    }
    func retryFailedDeliveries(allUndelivered: Bool = false) {
        let candidates = allUndelivered ? Array(deliveries.values) : failedDeliveries.compactMap { deliveries[$0] }
        let retry = candidates.filter { $0.message.category == nil && !received.contains($0.message.id) && !consumed.contains($0.message.id) }
        failedDeliveries = []
        for d in retry {
            cancelMessage(id: d.message.id, cancelMobile: false)
            if d.valid(), d.message.valid(now: Date()) { enqueue(d.message, valid: d.valid, failed: d.failed, shown: d.shown, action: d.action) }
        }
    }
    func requestPermission(completion: @escaping (String) -> Void) {
        guard policyActive ? policyPreferences.enabledChannels.contains(.system) : preferences.mode.usesSystem else { completion(""); return }
        Task {
            guard let center else { completion("unavailable"); return }
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional: completion(""); return
            case .notDetermined: break
            default: completion("denied"); return
            }
            do { completion(try await center.requestAuthorization(options: [.alert]) ? "" : "denied") }
            catch { completion("unavailable") }
        }
    }
    func sendTestNotification(title: String, body: String) {
        guard !stopped, !policyPreferences.enabledChannels.isEmpty else { return }
        let message = ExperienceNotification(id: "channel-test-" + UUID().uuidString, kind: .test, epoch: nil, title: title, body: body, createdAt: Date(), validUntil: Date().addingTimeInterval(30))
        enqueue(message, valid: { true }, failed: {})
        if policyPreferences.enabledChannels.contains(.mobile) { bark?.sendTest(title: title, body: body) }
    }
    @discardableResult func preview(_ message: ExperienceNotification) -> Bool {
        guard canPresent, !stopped else { return false }
        suspend()
        for item in state.unread(now: Date()) { state.dismiss(id: item.message.id, read: false) }
        previews.insert(message.id)
        enqueue(message, valid: { true }, failed: {}, forceBubble: true)
        return state.activeID == message.id
    }
    func enqueue(_ input: ExperienceNotification, valid: @escaping () -> Bool, failed: @escaping () -> Void, shown: @escaping () -> Void = {}, action: (() -> Void)? = nil, forceBubble: Bool = false) {
        var m = input; m.deliveryToken = UUID().uuidString
        guard !stopped, valid(), m.valid(now: Date()) else { return }
        if !forceBubble { captureMessage(m) }
        let identity = BarkEventIdentity(id: m.id, generation: m.reminderGeneration)
        let sharedShown = { [weak self] in
            guard let self, !self.sharedReceived.contains(identity), valid() else { return }
            self.sharedReceived.insert(identity); shown()
        }
        snapshot(m)
        if !forceBubble, canStartChannel(m, .mobile) {
            bark?.enqueue(m, valid: { [weak self] in valid() && self?.channelAllowed(m, .mobile) == true }, accepted: { [weak self] in self?.recordChannel(m, .mobile); sharedShown() })
        }
        guard deliveries[m.id] == nil, (canStartChannel(m, .bubble) || canStartChannel(m, .system) || forceBubble) else { return }
        deliveries[m.id] = Delivery(message: m, valid: valid, failed: failed, shown: sharedShown, action: action)
        if deliveries.count > 128, let oldest = deliveries.values.filter({ $0.message.id != state.activeID }).min(by: { $0.message.createdAt < $1.message.createdAt }) { deliveries.removeValue(forKey: oldest.message.id); received.remove(oldest.message.id) }
        if canStartChannel(m, .bubble) || forceBubble { state.enqueue(m, canPresent: canPresent, now: Date()) }
        if canStartChannel(m, .system) && !forceBubble {
            let done: (Bool) -> Void = { [weak self] success in
                guard let self, !stopped, let d = deliveries[m.id], d.message.deliveryToken == m.deliveryToken, d.valid(), m.valid(now: Date()), channelAllowed(m, .system) else { return }
                if success { recordChannel(m, .system); failedDeliveries.remove(m.id); receipt(m.id, token: m.deliveryToken) } else { if !received.contains(m.id) { failedDeliveries.insert(m.id) }; d.failed() }
            }
            if let sendSystem { sendSystem(m, done) } else { deliverSystem(m, done: done) }
        }
        onUnreadChange?(); dispatch()
    }
    private func deliverSystem(_ m: ExperienceNotification, done: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self, let center else { done(false); return }
            let permission = await center.notificationSettings()
            guard !stopped, deliveries[m.id]?.message.deliveryToken == m.deliveryToken, deliveries[m.id]?.valid() == true, m.valid(now: Date()), channelAllowed(m, .system) else { return }
            guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else { done(false); return }
            let content = UNMutableNotificationContent(); content.title = m.title; content.body = m.body
            content.userInfo = ["token": m.deliveryToken ?? "", "id": m.id, "kind": String(describing: m.kind), "epoch": m.epoch ?? ""]
            if m.kind == .update { let v = m.id.replacingOccurrences(of: "quotabar-update-", with: ""); if (try? UpdateFeed.versionParts(v)) != nil { content.userInfo["version"] = v } }
            do {
                try await center.add(UNNotificationRequest(identifier: m.id + "." + (m.deliveryToken ?? ""), content: content, trigger: nil))
                guard !stopped, deliveries[m.id]?.message.deliveryToken == m.deliveryToken, deliveries[m.id]?.valid() == true, channelAllowed(m, .system) else { center.removeDeliveredNotifications(withIdentifiers: [m.id + "." + (m.deliveryToken ?? "")]); return }
                done(true)
            } catch { done(false) }
        }
    }
    private func receipt(_ id: String, token: String? = nil) {
        guard !received.contains(id), let d = deliveries[id], token == nil || token == d.message.deliveryToken, d.valid() else { return }
        received.insert(id); d.shown()
    }
    func updateEnvironment(canPresent: Bool) {
        self.canPresent = canPresent
        if !canPresent { suspend() } else { dispatch() }
    }
    private func dispatch() {
        guard !stopped, canPresent else { return }
        while let m = state.next(canPresent: true, now: Date()) {
            guard deliveries[m.id]?.message.deliveryToken == m.deliveryToken, deliveries[m.id]?.valid() == true, (channelAllowed(m, .bubble) || previews.contains(m.id)) else { state.dismiss(id: m.id, read: false); continue }
            guard presentBubble?(m) == true else { state.suspend(); break }
            state.shown(id: m.id, now: Date()); recordChannel(m, .bubble); receipt(m.id, token: m.deliveryToken)
            timer?.invalidate()
            timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(timer!, forMode: .common)
            break
        }
    }
    func tick() {
        if let id = state.activeID, deliveries[id]?.valid() != true { state.dismiss(id: id, read: false); hideBubble?() }
        if state.tick(now: Date()) { previews = []; hideBubble?(); onUnreadChange?() }
        if state.activeID == nil { timer?.invalidate(); timer = nil; dispatch() }
    }
    func observeQuota(_ observation: QuotaObservation) {
        guard state.observeQuota(observation, now: Date()) else { return }
        previews = []; timer?.invalidate(); timer = nil; hideBubble?(); onUnreadChange?(); dispatch()
    }
    func setInteracting(_ value: Bool) { state.setInteracting(value, now: Date()) }
    func dismiss(id: String, read: Bool, token: String? = nil) {
        guard token == nil || deliveries[id]?.message.deliveryToken == token else { return }
        if read { if let message = deliveries[id]?.message { saveLiveRead(message) }; consumed.insert(id) }
        let active = state.activeID == id
        state.dismiss(id: id, read: read); previews.remove(id)
        if active { hideBubble?(); timer?.invalidate(); timer = nil }
        messageChanged(); dispatch()
    }
    func suspend() { previews = []; state.suspend(); timer?.invalidate(); timer = nil; hideBubble?() }
    var openUpdates: (() -> Void)?
    func activateLatest(id: String, token: String? = nil) {
        guard !consumed.contains(id), let d = deliveries[id], token == nil || token == d.message.deliveryToken else { return }
        if d.message.kind == .update { dismiss(id: id, read: true, token: token); openUpdates?(); return }
        dismiss(id: id, read: true); openDetails?()
    }
    func activate(id: String, token: String? = nil) {
        guard !consumed.contains(id), let d = deliveries[id], token == nil || token == d.message.deliveryToken else { return }
        guard d.valid() else { dismiss(id: id, read: true, token: token); return }
        saveLiveRead(d.message); consumed.insert(id)
        receipt(id); suspend(); state.dismiss(id: id, read: true); messageChanged()
        if let action = d.action { action() }
        else if d.message.kind == .bank { (openBank ?? openDetails)?() }
        else { openDetails?() }
    }
    func cancelMessage(id: String, cancelMobile: Bool = true) {
        if cancelMobile { bark?.cancel(id: id) }
        let active = state.activeID == id
        if let token = deliveries[id]?.message.deliveryToken { cancelledTokens.insert(token) }; if cancelledTokens.count > 256 { cancelledTokens = Set(cancelledTokens.sorted().suffix(128)) }
        let identifiers = [id, id + "." + (deliveries[id]?.message.deliveryToken ?? "")]
        consumed.remove(id); failedDeliveries.remove(id); state.forget(id: id); deliveries.removeValue(forKey: id); received.remove(id); previews.remove(id)
        center?.removeDeliveredNotifications(withIdentifiers: identifiers); center?.removePendingNotificationRequests(withIdentifiers: identifiers)
        if active { hideBubble?(); timer?.invalidate(); timer = nil }
        onUnreadChange?()
    }
    func cancelAuthenticationEpoch(_ epoch: String) {
        bark?.cancel(epoch: epoch)
        let ids = deliveries.values.filter { $0.message.epoch == epoch }.map { $0.message.id }
        let active = ids.contains(state.activeID ?? "")
        let identifiers = ids.flatMap { [$0, $0 + "." + (deliveries[$0]?.message.deliveryToken ?? "")] }
        for id in ids { if let token = deliveries[id]?.message.deliveryToken { cancelledTokens.insert(token) }; consumed.remove(id) }
        state.cancel(epoch: epoch)
        for id in ids { deliveries.removeValue(forKey: id); received.remove(id); failedDeliveries.remove(id) }
        if cancelledTokens.count > 256 { cancelledTokens = Set(cancelledTokens.sorted().suffix(128)) }
        center?.removeDeliveredNotifications(withIdentifiers: identifiers); center?.removePendingNotificationRequests(withIdentifiers: identifiers)
        if active { hideBubble?(); timer?.invalidate(); timer = nil }
        onUnreadChange?(); dispatch()
    }
    func stop() { bark?.stop(); stopped = true; state.stop(); timer?.invalidate(); timer = nil; hideBubble?(); deliveries = [:]; received = []; previews = []; consumed = []; cancelledTokens = []; failedDeliveries = [] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["id"] as? String
        let version = response.notification.request.content.userInfo["version"] as? String
        let token = response.notification.request.content.userInfo["token"] as? String
        Task { @MainActor [weak self] in
            if let token, self?.cancelledTokens.contains(token) == true { return }
            if let id, let delivery = self?.deliveries[id] {
                guard delivery.valid(), token == nil || token == delivery.message.deliveryToken else { return }
                if delivery.message.kind == .update { self?.dismiss(id: id, read: true, token: token); self?.openUpdates?() }
                else { self?.activate(id: id, token: token) }
            }
            else if let version, (try? UpdateFeed.versionParts(version)) != nil { self?.openUpdates?() }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
}
