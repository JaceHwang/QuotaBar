import AppKit
import QuotaCore
import UserNotifications

@MainActor
final class QuotaUpdateController: NSObject {
    private var notificationCenter: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private let version: String
    private var developmentCandidate: Bool {
        guard let url = Bundle.main.url(forResource: "PROVENANCE", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return true }
        return object["kind"] as? String != "release"
    }
    private let now: () -> Date
    private let text: (String, String, String) -> String
    private var timer: Timer?
    private var request: Task<Void, Never>?
    private var notifyTask: Task<Void, Never>?
    private var nextCheck: Date
    private var lastManual = Date.distantPast
    private var stopped = false
    private let session: URLSession
    private var failures = 0
    private var cache: Data?
    private var etag: String?
    private var status = ""
    var currentVersion: String { version }
    var isChecking: Bool { request != nil }
    var statusText: String { status }
    private(set) var available: UpdateRelease?
    private weak var statusField: NSTextField?
    private weak var actions: NSStackView?
    private weak var checkButton: NSButton?
    private weak var progress: NSProgressIndicator?
    var onChange: (() -> Void)?
    private var auto: Bool { !defaults.bool(forKey: "updates.autoDisabled") }
    private var reminders: Bool { defaults.bool(forKey: "updates.reminders") }
    private var policy: UpdateReminderPolicy {
        get { defaults.data(forKey: "updates.policy").flatMap { try? JSONDecoder().decode(UpdateReminderPolicy.self, from: $0) } ?? UpdateReminderPolicy() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "updates.policy") }
    }
    init(defaults: UserDefaults = .standard, version: String, transport: URLSession? = nil, now: @escaping () -> Date = Date.init, text: @escaping (String, String, String) -> String) {
        self.now = now; nextCheck = now().addingTimeInterval(30)
        self.defaults = defaults; self.version = version; self.text = text
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        session = transport ?? URLSession(configuration: config)
        super.init()
        // UserNotifications requires an application bundle; CLI/test hosts have no bundle proxy.
        if Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil {
            notificationCenter = AppNotificationRouter.shared.center
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(); self?.notifyIfNeeded() }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.check()
        }
    }
    func stop() { stopped = true; session.invalidateAndCancel(); timer?.invalidate(); timer = nil; request?.cancel(); notifyTask?.cancel() }
    func check(manual: Bool = false) {
        guard !stopped, request == nil else { return }
        let now = self.now()
        guard manual ? now.timeIntervalSince(lastManual) >= 10 : auto && now >= nextCheck else { return }
        if manual { lastManual = now }
        status = text("Checking…", "正在检查…", "正在檢查…"); refreshView()
        request = Task { [weak self] in
            guard let self else { return }
            defer { request = nil; refreshView(); onChange?() }
            do {
                var query = URLRequest(url: UpdateFeed.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                if let etag { query.setValue(etag, forHTTPHeaderField: "If-None-Match") }
                let (bytes, response) = try await session.bytes(for: query)
                guard let http = response as? HTTPURLResponse, response.url?.absoluteString == UpdateFeed.endpoint.absoluteString else { throw URLError(.badServerResponse) }
                var data = Data()
                if http.statusCode == 304, let cache { data = cache }
                else {
                    guard http.statusCode == 200, response.expectedContentLength <= 262144 else { throw URLError(.badServerResponse) }
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard data.count < 262144 else { throw URLError(.dataLengthExceedsMaximum) }; data.append(byte)
                    }
                }
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let release = try UpdateFeed.available(in: data, platform: "macos-arm64", current: version, os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
                try Task.checkCancellation()
                available = release; cache = data
                if http.statusCode == 200 { etag = http.value(forHTTPHeaderField: "ETag") }
                defaults.set(self.now(), forKey: "updates.lastSuccess"); failures = 0
                nextCheck = self.now().addingTimeInterval(86400)
                status = release == nil ? text("No newer release found", "未发现更新版本", "未發現更新版本") : text("Update available", "有新版本可用", "有新版本可用")
                notifyIfNeeded()
            } catch {
                if Task.isCancelled { return }
                failures = min(failures + 1, 6)
                nextCheck = self.now().addingTimeInterval(min(21600, 300 * pow(2, Double(failures - 1))))
                status = text("Could not check. Try again later.", "检查失败，请稍后重试。", "檢查失敗，請稍後重試。")
            }
        }
        refreshView()
    }
    func makeSettingsView() -> NSView {
        let stack = QuotaSettingsStyle.column(20)
        let header = QuotaSettingsStyle.column(10)
        let brand = NSStackView(); brand.spacing = 10
        let icon = QuotaThemeIconView(frame: .zero)
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true; icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        brand.addArrangedSubview(icon)
        let name = QuotaSettingsStyle.label("QuotaBar", size: 16); name.font = .systemFont(ofSize: 16, weight: .semibold); brand.addArrangedSubview(name)
        header.addArrangedSubview(brand)
        let label = QuotaSettingsStyle.label("", size: 12, secondary: true); statusField = label; QuotaSettingsStyle.fill(label, in: header)
        let checkRow = NSStackView(); checkRow.spacing = 10
        let check = QuotaSettingsStyle.button(text("Check for updates", "检查更新", "檢查更新"), target: self, action: #selector(manualCheck)); checkButton = check; checkRow.addArrangedSubview(check)
        let spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false; progress = spinner; checkRow.addArrangedSubview(spinner)
        header.addArrangedSubview(checkRow)
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
        for (label, action) in [(text("View update", "查看更新", "查看更新"), #selector(openRelease)), (text("Remind later", "稍后提醒", "稍後提醒"), #selector(snooze)), (text("Skip version", "跳过此版本", "跳過此版本"), #selector(skip))] {
            row.addArrangedSubview(QuotaSettingsStyle.button(label, target: self, action: action))
        }
        header.addArrangedSubview(row); actions = row
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(header), in: stack)
        let options = QuotaSettingsStyle.column(0)
        let automatic = QuotaSettingsSwitch(); automatic.target = self; automatic.action = #selector(autoChanged); automatic.state = auto ? .on : .off
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Automatically check for updates", "自动检查更新", "自動檢查更新"), control: automatic), in: options)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: options)
        let reminder = QuotaSettingsSwitch(); reminder.target = self; reminder.action = #selector(remindersChanged); reminder.state = reminders ? .on : .off
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Update reminders", "更新提醒", "更新提醒"), control: reminder), in: options)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(options), in: stack)
        refreshView(); return stack
    }
    private func refreshView() {
        let current = text("Current version", "当前版本", "目前版本")
        let extra = available.map { " · " + text("Available", "可用更新", "可用更新") + " " + $0.version } ?? ""
        let candidate = developmentCandidate ? " (" + text("development candidate", "开发候选", "開發候選") + ")" : ""
        statusField?.stringValue = "\(current) \(version)\(candidate)\(extra)\n\(status)"
        if let notes = available?.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusField?.stringValue += "\n\n" + notes
        } else if let summary = available?.notificationSummary {
            statusField?.stringValue += "\n\n" + summary
        }
        actions?.isHidden = available == nil
        checkButton?.isEnabled = request == nil
        if request == nil { progress?.stopAnimation(nil) } else { progress?.startAnimation(nil) }
    }
    @objc private func manualCheck() { check(manual: true) }
    @objc private func autoChanged(_ sender: QuotaSettingsSwitch) { defaults.set(sender.state != .on, forKey: "updates.autoDisabled"); if sender.state == .on { nextCheck = .distantPast; check() } }
    @objc private func remindersChanged(_ sender: QuotaSettingsSwitch) {
        defaults.set(sender.state == .on, forKey: "updates.reminders")
        guard sender.state == .on else { return }
        guard let center = notificationCenter else { status = text("System reminders require the installed app", "系统提醒需要安装后的应用", "系統提醒需要安裝後的應用"); refreshView(); return }
        Task { [weak self] in
            do {
                let granted = try await center.requestAuthorization(options: [.alert])
                if !granted { self?.status = self?.text("System notifications are disabled; updates remain visible here", "系统提醒已关闭，可在此查看更新", "系統提醒已關閉，可在此查看更新") ?? "" }
            }
            catch { self?.status = self?.text("Notifications unavailable", "系统提醒不可用", "系統提醒不可用") ?? "" }
            guard self?.stopped == false else { return }
            self?.refreshView(); self?.notifyIfNeeded()
        }
    }
    @objc func openRelease() { if let available { NSWorkspace.shared.open(available.releaseNotesURL) } }
    @objc private func snooze() { var value = policy; if value.skippedVersion == available?.version { value.skippedVersion = nil }; value.snoozeUntil = Date().addingTimeInterval(86400); policy = value; status = text("Reminder postponed for 24 hours", "已延后提醒 24 小时", "已延後提醒 24 小時"); refreshView() }
    @objc private func skip() { var value = policy; value.skippedVersion = available?.version; value.snoozeUntil = nil; policy = value; status = text("Version skipped", "已跳过此版本", "已跳過此版本"); refreshView() }
    private func notifyIfNeeded() {
        guard !stopped, reminders, let release = available, policy.shouldNotify(release.version, now: Date()), notifyTask == nil else { return }
        notifyTask = Task { [weak self] in
            guard let self else { return }; defer { notifyTask = nil }
            guard let center = notificationCenter else { return }
            let settings = await center.notificationSettings()
            guard !stopped, settings.authorizationStatus == .authorized, reminders, available == release, policy.shouldNotify(release.version, now: Date()), !Task.isCancelled else { return }
            let content = UNMutableNotificationContent(); content.title = "QuotaBar " + text("update available", "有新版本", "有新版本") + " " + release.version
            content.body = release.notificationSummary ?? text("Click to view release notes", "点击查看更新说明", "點擊查看更新說明")
            // The release URL was validated by the feed parser; do not trust arbitrary notification payload URLs.
            content.userInfo = ["version": release.version]
            let attempted = policy
            do {
                try await center.add(UNNotificationRequest(identifier: "quotabar-update-\(release.version)", content: content, trigger: nil))
                guard !stopped, reminders, available == release, policy.skippedVersion != release.version else {
                    center.removeDeliveredNotifications(withIdentifiers: ["quotabar-update-\(release.version)"]); return
                }
                var value = policy; value.recordNotification(release.version, attempted: attempted); policy = value
            } catch { status = text("System reminder unavailable; view update here", "系统提醒不可用，可在此查看更新", "系統提醒不可用，可在此查看更新"); refreshView() }
        }
    }
}
