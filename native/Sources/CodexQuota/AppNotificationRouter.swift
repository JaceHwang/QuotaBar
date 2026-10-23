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
        let retry = candidates.filter { !received.contains($0.message.id) && !consumed.contains($0.message.id) }
        failedDeliveries = []
        for d in retry {
            cancelMessage(id: d.message.id, cancelMobile: false)
            if d.valid(), d.message.valid(now: Date()) { enqueue(d.message, valid: d.valid, failed: d.failed, shown: d.shown, action: d.action) }
        }
    }
    func requestPermission(completion: @escaping (String) -> Void) {
        guard preferences.mode.usesSystem else { completion(""); return }
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
        let identity = BarkEventIdentity(id: m.id, generation: m.reminderGeneration)
        let sharedShown = { [weak self] in
            guard let self, !self.sharedReceived.contains(identity), valid() else { return }
            self.sharedReceived.insert(identity); shown()
        }
        if !forceBubble { bark?.enqueue(m, valid: valid, accepted: sharedShown) }
        guard deliveries[m.id] == nil, (preferences.mode != .off || forceBubble) else { return }
        deliveries[m.id] = Delivery(message: m, valid: valid, failed: failed, shown: sharedShown, action: action)
        if deliveries.count > 128, let oldest = deliveries.values.filter({ $0.message.id != state.activeID }).min(by: { $0.message.createdAt < $1.message.createdAt }) { deliveries.removeValue(forKey: oldest.message.id); received.remove(oldest.message.id) }
        if preferences.mode.usesBubble || forceBubble { state.enqueue(m, canPresent: canPresent && (!preferences.paused(now: Date()) || forceBubble), now: Date()) }
        if preferences.mode.usesSystem && !forceBubble {
            let done: (Bool) -> Void = { [weak self] success in
                guard let self, !stopped, let d = deliveries[m.id], d.message.deliveryToken == m.deliveryToken, d.valid(), m.valid(now: Date()) else { return }
                if success { failedDeliveries.remove(m.id); receipt(m.id, token: m.deliveryToken) } else { if !received.contains(m.id) { failedDeliveries.insert(m.id) }; d.failed() }
            }
            if let sendSystem { sendSystem(m, done) } else { deliverSystem(m, done: done) }
        }
        onUnreadChange?(); dispatch()
    }
    private func deliverSystem(_ m: ExperienceNotification, done: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self, let center else { done(false); return }
            let permission = await center.notificationSettings()
            guard !stopped, deliveries[m.id]?.message.deliveryToken == m.deliveryToken, deliveries[m.id]?.valid() == true, m.valid(now: Date()), preferences.mode.usesSystem else { return }
            guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else { done(false); return }
            let content = UNMutableNotificationContent(); content.title = m.title; content.body = m.body
            content.userInfo = ["token": m.deliveryToken ?? "", "id": m.id, "kind": String(describing: m.kind), "epoch": m.epoch ?? ""]
            if m.kind == .update { let v = m.id.replacingOccurrences(of: "quotabar-update-", with: ""); if (try? UpdateFeed.versionParts(v)) != nil { content.userInfo["version"] = v } }
            do {
                try await center.add(UNNotificationRequest(identifier: m.id + "." + (m.deliveryToken ?? ""), content: content, trigger: nil))
                guard !stopped, deliveries[m.id]?.message.deliveryToken == m.deliveryToken, deliveries[m.id]?.valid() == true else { center.removeDeliveredNotifications(withIdentifiers: [m.id + "." + (m.deliveryToken ?? "")]); return }
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
        guard !stopped, canPresent, ((preferences.mode.usesBubble && !preferences.paused(now: Date())) || !previews.isEmpty) else { return }
        while let m = state.next(canPresent: true, now: Date()) {
            guard deliveries[m.id]?.message.deliveryToken == m.deliveryToken, deliveries[m.id]?.valid() == true else { state.dismiss(id: m.id, read: false); continue }
            guard presentBubble?(m) == true else { state.suspend(); break }
            state.shown(id: m.id, now: Date()); receipt(m.id, token: m.deliveryToken)
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
        if read { consumed.insert(id) }
        let active = state.activeID == id
        state.dismiss(id: id, read: read); previews.remove(id)
        if active { hideBubble?(); timer?.invalidate(); timer = nil }
        onUnreadChange?(); dispatch()
    }
    func suspend() { previews = []; state.suspend(); timer?.invalidate(); timer = nil; hideBubble?() }
    func activateLatest(id: String, token: String? = nil) {
        guard !consumed.contains(id), let d = deliveries[id], token == nil || token == d.message.deliveryToken else { return }
        if d.message.kind == .update { activate(id: id); return }
        dismiss(id: id, read: true); openDetails?()
    }
    func activate(id: String, token: String? = nil) {
        guard !consumed.contains(id), let d = deliveries[id], token == nil || token == d.message.deliveryToken else { return }
        guard d.valid() else { dismiss(id: id, read: true, token: token); return }
        consumed.insert(id)
        receipt(id); suspend(); state.dismiss(id: id, read: true); onUnreadChange?()
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
            if let id, self?.deliveries[id] != nil { self?.activate(id: id, token: token) }
            else if let version, (try? UpdateFeed.versionParts(version)) != nil, let url = URL(string: "https://github.com/JaceHwang/QuotaBar/releases/tag/v\(version)") { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
}
