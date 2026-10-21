import AppKit
import UserNotifications
import QuotaCore

@MainActor final class AppNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationRouter()
    let center: UNUserNotificationCenter?
    var openDetails: (() -> Void)?
    private var tasks: [String: (String?, Task<Void, Never>)] = [:]
    private var delivered: [String: String] = [:]
    private override init() {
        center = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init(); center?.delegate = self
    }
    func requestPermission(completion: @escaping (String) -> Void) {
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
    func enqueue(_ message: ExperienceNotification, valid: @escaping () -> Bool, failed: @escaping () -> Void) {
        guard tasks[message.id] == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { tasks[message.id] = nil }
            guard let center else { failed(); return }
            let permission = await center.notificationSettings()
            guard !Task.isCancelled, message.valid(now: Date()), valid() else { return }
            guard permission.authorizationStatus == .authorized else { failed(); return }
            let content = UNMutableNotificationContent(); content.title = message.title; content.body = message.body
            content.userInfo = ["kind": String(describing: message.kind), "epoch": message.epoch ?? ""]
            do {
                try await center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
                guard !Task.isCancelled, valid() else { center.removeDeliveredNotifications(withIdentifiers: [message.id]); return }
                if let epoch = message.epoch { delivered[message.id] = epoch }
                if delivered.count > 128 { delivered.removeValue(forKey: delivered.keys.sorted().first!) }
            } catch { failed() }
        }
        tasks[message.id] = (message.epoch, task)
    }
    func cancelAuthenticationEpoch(_ epoch: String) {
        for (_, value) in tasks where value.0 == epoch { value.1.cancel() }
        let ids = delivered.filter { $0.value == epoch }.map(\.key)
        center?.removeDeliveredNotifications(withIdentifiers: ids)
        delivered = delivered.filter { $0.value != epoch }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let version = info["version"] as? String, kind = info["kind"] as? String
        Task { @MainActor [weak self] in
            if let version, (try? UpdateFeed.versionParts(version)) != nil,
               let url = URL(string: "https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v\(version)") { NSWorkspace.shared.open(url) }
            else if kind == "recovery" || kind == "bank" || kind == "test" { self?.openDetails?() }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
}
