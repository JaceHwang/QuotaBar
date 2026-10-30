import AppKit
import QuotaCore
import UserNotifications

@MainActor
final class QuotaUpdateController: NSObject {
    let installer: ApplicationUpdateService
    var openUpdateSettings: (() -> Void)?
    private weak var installButton: NSButton?
    private weak var cancelInstallButton: NSButton?
    private weak var downloadBar: NSProgressIndicator?
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
    var currentMobileIdentities: [BarkEventIdentity] {
        guard let available else { return [] }
        return [BarkEventIdentity(id: "quotabar-update-" + available.version, generation: policy.snoozeUntil.map { "snooze:\(Int64(($0.timeIntervalSince1970 * 1000).rounded()))" } ?? "initial")]
    }
    var isChecking: Bool { request != nil }
    var statusText: String { status }
    private(set) var available: UpdateRelease?
    private weak var statusField: NSTextField?
    private weak var notesField: NSTextField?
    private weak var actions: NSStackView?
    private weak var checkButton: NSButton?
    private weak var progress: NSProgressIndicator?
    var onChange: (() -> Void)?
    private var auto: Bool { !defaults.bool(forKey: "updates.autoDisabled") }
    private var reminders: Bool { let router = AppNotificationRouter.shared; return router.policyActive ? !(router.policyPreferences.rules[.updateAvailable] ?? []).isEmpty : defaults.bool(forKey: "updates.reminders") }
    private var policy: UpdateReminderPolicy {
        get { defaults.data(forKey: "updates.policy").flatMap { try? JSONDecoder().decode(UpdateReminderPolicy.self, from: $0) } ?? UpdateReminderPolicy() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "updates.policy") }
    }
    init(defaults: UserDefaults = .standard, version: String, updateExecute: ApplicationUpdateService.Execute? = nil, transport: URLSession? = nil, now: @escaping () -> Date = Date.init, text: @escaping (String, String, String) -> String) {
        installer = ApplicationUpdateService(currentVersion: version, execute: updateExecute)
        self.now = now; nextCheck = now().addingTimeInterval(30)
        self.defaults = defaults; self.version = version; self.text = text
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        session = transport ?? URLSession(configuration: config)
        super.init()
        installer.onChange = { [weak self] in self?.refreshView(); self?.onChange?() }
        installer.onReady = { NSApp.terminate(nil) }
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
    func waitForUpdateCleanup() async { await installer.waitForCleanup() }
    func stop() { installer.cancel(); stopped = true; session.invalidateAndCancel(); timer?.invalidate(); timer = nil; request?.cancel(); notifyTask?.cancel() }
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
        let group = QuotaSettingsStyle.column(6)
        let heading = QuotaSettingsStyle.label(text("Version & updates", "版本与更新", "版本與更新"), size: 13)
        heading.font = .systemFont(ofSize: 13, weight: .semibold); QuotaSettingsStyle.fill(heading, in: group)
        let automatic = QuotaSettingsSwitch(); automatic.target = self; automatic.action = #selector(autoChanged); automatic.state = auto ? .on : .off
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Automatically check for updates", "自动检查更新", "自動檢查更新"), control: automatic), in: group)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: group)
        let reminder = QuotaSettingsSwitch(); reminder.target = self; reminder.action = #selector(remindersChanged); reminder.state = reminders ? .on : .off
        if !AppNotificationRouter.shared.policyActive {
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Update reminders", "更新提醒", "更新提醒"), control: reminder), in: group)
        } else { QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Choose update notification channels in Reminder settings.", "更新提醒渠道请在提醒设置中选择。", "更新提醒管道請在提醒設定中選擇。"), size: 11, secondary: true), in: group) }
        QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: group)
        let label = QuotaSettingsStyle.label("", size: 12, secondary: true); statusField = label
        let checkRow = NSStackView(); checkRow.spacing = 10; checkRow.alignment = .centerY; checkRow.addArrangedSubview(label)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let gap = NSView(); gap.setContentHuggingPriority(.init(1), for: .horizontal); checkRow.addArrangedSubview(gap)
        let check = QuotaSettingsStyle.button(text("Check for updates", "检查更新", "檢查更新"), target: self, action: #selector(manualCheck), primary: true); check.bezelColor = .systemGreen; checkButton = check; checkRow.addArrangedSubview(check)
        let spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false; progress = spinner; checkRow.addArrangedSubview(spinner)
        QuotaSettingsStyle.fill(checkRow, in: group)
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
        let install = QuotaSettingsStyle.button(text("Update now", "立即更新", "立即更新"), target: self, action: #selector(installUpdate), primary: true); installButton = install; row.addArrangedSubview(install)
        for (label, action) in [(text("View release notes", "查看更新内容", "查看更新內容"), #selector(openRelease)), (text("Remind later", "稍后提醒", "稍後提醒"), #selector(snooze)), (text("Skip version", "跳过此版本", "跳過此版本"), #selector(skip))] {
            row.addArrangedSubview(QuotaSettingsStyle.button(label, target: self, action: action))
        }
        group.addArrangedSubview(row); actions = row
        let bar = NSProgressIndicator(); bar.style = .bar; bar.isIndeterminate = false; bar.maxValue = 100; downloadBar = bar; QuotaSettingsStyle.fill(bar, in: group)
        let cancel = QuotaSettingsStyle.button(text("Cancel download", "取消下载", "取消下載"), target: self, action: #selector(cancelInstall)); cancelInstallButton = cancel; group.addArrangedSubview(cancel)
        let notes = QuotaSettingsStyle.label("", size: 12, secondary: true); notesField = notes; QuotaSettingsStyle.fill(notes, in: group)
        refreshView(); return QuotaSettingsStyle.card(group)
    }
    private func refreshView() {
        let current = text("Current version", "当前版本", "目前版本")
        let visibleVersion = installer.progress.phase.busy ? installer.targetVersion : available?.version
        let extra = visibleVersion.map { " · " + text("Available", "可用更新", "可用更新") + " " + $0 } ?? ""
        let candidate = developmentCandidate ? " (" + text("development candidate", "开发候选", "開發候選") + ")" : ""
        let update = installer.progress
        let updateStatus = update.phase == .idle ? status : installStatus(update)
        statusField?.stringValue = "\(current) \(version)\(candidate)\(extra)\n\(updateStatus)"
        notesField?.stringValue = ""
        if let notes = available?.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesField?.stringValue = notes
        } else if let summary = available?.notificationSummary {
            notesField?.stringValue = summary
        }
        notesField?.isHidden = notesField?.stringValue.isEmpty != false
        actions?.isHidden = available == nil && !update.phase.busy
        installButton?.title = update.phase == .failed ? text("Retry update", "重试更新", "重試更新") : text("Update now", "立即更新", "立即更新")
        installButton?.isEnabled = !update.phase.busy
        actions?.arrangedSubviews.dropFirst().forEach { ($0 as? NSControl)?.isEnabled = !update.phase.busy }
        cancelInstallButton?.isHidden = !update.phase.canCancel
        downloadBar?.isHidden = !update.phase.busy
        downloadBar?.isIndeterminate = update.phase != .downloading
        if update.phase == .downloading { downloadBar?.doubleValue = update.total > 0 ? Double(update.received) / Double(update.total) * 100 : 0; downloadBar?.stopAnimation(nil) } else if update.phase.busy { downloadBar?.startAnimation(nil) }
        checkButton?.isEnabled = request == nil && !update.phase.busy
        if request == nil { progress?.stopAnimation(nil) } else { progress?.startAnimation(nil) }
    }
    func installStatus(_ update: ApplicationUpdateProgress) -> String {
        switch update.phase {
        case .resolving: return text("Resolving official release…", "正在获取官方版本…", "正在取得官方版本…")
        case .downloading: return text("Downloading", "正在下载", "正在下載") + String(format: " %.1f / %.1f MB", Double(update.received) / 1048576, Double(update.total) / 1048576)
        case .verifying: return text("Verifying download…", "正在校验安装包…", "正在驗證安裝套件…")
        case .preparing: return text("Preparing update…", "正在准备更新…", "正在準備更新…")
        case .handingOff, .installing: return text("Installing and restarting…", "正在安装并重启…", "正在安裝並重新啟動…")
        case .failed: return text("Update failed. Retry or use the release page to install manually. Run QuotaBar from ~/Applications first.", "更新失败，可重试或从更新页面手动安装。请先将应用安装至 ~/Applications。", "更新失敗，可重試或從更新頁面手動安裝。請先將應用程式安裝至 ~/Applications。")
        case .succeeded: return text("Update installed successfully.", "更新安装成功。", "更新安裝成功。")
        case .rolledBack: return text("The new version could not start. Your previous version was restored.", "新版未能正常启动，已恢复旧版本。", "新版未能正常啟動，已恢復舊版本。")
        case .cancelled: return text("Download cancelled; current version unchanged.", "已取消下载，当前版本未变更。", "已取消下載，目前版本未變更。")
        default: return ""
        }
    }
    @objc func installUpdate() { guard !stopped, let available else { return }; installer.start(version: available.version) }
    @objc private func cancelInstall() { installer.cancel() }
    @objc private func manualCheck() { check(manual: true) }
    @objc private func autoChanged(_ sender: QuotaSettingsSwitch) { defaults.set(sender.state != .on, forKey: "updates.autoDisabled"); if sender.state == .on { nextCheck = .distantPast; check() } }
    @objc private func remindersChanged(_ sender: QuotaSettingsSwitch) {
        defaults.set(sender.state == .on, forKey: "updates.reminders")
        guard sender.state == .on else { if let v = available?.version { AppNotificationRouter.shared.cancelMessage(id: "quotabar-update-\(v)") }; return }
        AppNotificationRouter.shared.requestPermission { [weak self] result in
            guard let self else { return }
            if !result.isEmpty { status = text("System notifications unavailable; bubbles remain available", "系统通知不可用，仍可使用气泡提醒", "系統通知無法使用，仍可使用氣泡提醒") }
            if result.isEmpty { AppNotificationRouter.shared.retryFailedDeliveries() }
            refreshView(); notifyIfNeeded()
        }
    }

    @objc func openRelease() { if let available { NSWorkspace.shared.open(available.releaseNotesURL) } }
    @objc private func snooze() { if let v = available?.version { AppNotificationRouter.shared.cancelMessage(id: "quotabar-update-\(v)") }; var value = policy; if value.skippedVersion == available?.version { value.skippedVersion = nil }; value.snoozeUntil = Date().addingTimeInterval(86400); policy = value; status = text("Reminder postponed for 24 hours", "已延后提醒 24 小时", "已延後提醒 24 小時"); refreshView() }
    @objc private func skip() { if let v = available?.version { AppNotificationRouter.shared.cancelMessage(id: "quotabar-update-\(v)") }; var value = policy; value.skippedVersion = available?.version; value.snoozeUntil = nil; policy = value; status = text("Version skipped", "已跳过此版本", "已跳過此版本"); refreshView() }
    private func notifyIfNeeded() {
        guard !stopped, reminders, let release = available, policy.shouldNotify(release.version, now: now()) else { return }
        let attempted = policy
        let message = ExperienceNotification(id: "quotabar-update-\(release.version)", kind: .update, epoch: nil, title: "QuotaBar " + text("update available", "有新版本", "有新版本") + " " + release.version, body: release.notificationSummary ?? text("View release notes", "查看更新说明", "查看更新說明"), createdAt: now(), reminderGeneration: attempted.snoozeUntil.map { "snooze:\(Int64(($0.timeIntervalSince1970 * 1000).rounded()))" } ?? "initial", category: AppNotificationRouter.shared.policyActive ? .updateAvailable : nil)
        AppNotificationRouter.shared.enqueue(message, valid: { [weak self] in
            guard let self else { return false }
            return !stopped && reminders && available == release && policy.skippedVersion != release.version && (policy.snoozeUntil.map { $0 <= now() } ?? true)
        }, failed: { [weak self] in self?.status = self?.text("System reminder unavailable", "系统提醒不可用", "系統提醒無法使用") ?? ""; self?.refreshView() }, shown: { [weak self] in
            guard let self else { return }
            var value = policy; value.recordNotification(release.version, attempted: attempted); policy = value
        }, action: { [weak self] in guard self?.available == release else { return }; self?.installUpdate() })
    }
}
