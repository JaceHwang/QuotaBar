import AppKit
import QuotaCore

@MainActor final class QuotaExperienceController: NSObject {
    private let store: QuotaExperienceStore
    private let defaults: UserDefaults
    private var engine: QuotaExperienceEngine
    private var sequence = 0
    private var lastObservation: QuotaObservation?
    private let language: () -> CodexDisplayLanguage
    private let router = AppNotificationRouter.shared
    private weak var statusLabel: NSTextField?
    private var storageReady = true
    private var notificationStatus = ""
    private let requestNotificationPermission: (@escaping (String) -> Void) -> Void
    var onChange: (() -> Void)?
    var onCelebrate: (() -> Void)?
    var onCancelCelebration: (() -> Void)?
    var preferences: QuotaExperiencePreferences { engine.preferences }
    init(root: URL, defaults: UserDefaults = .standard, language: @escaping () -> CodexDisplayLanguage, requestPermission: ((@escaping (String) -> Void) -> Void)? = nil) {
        self.requestNotificationPermission = requestPermission ?? { AppNotificationRouter.shared.requestPermission(completion: $0) }
        self.defaults = defaults; self.language = language; store = QuotaExperienceStore(url: root.appendingPathComponent("experience-state.json"))
        let state = store.load(); engine = QuotaExperienceEngine(state: state, suppressFirstBank: store.corrupted)
        super.init()
        let prefs = defaults.data(forKey: "experience.preferences").flatMap { try? JSONDecoder().decode(QuotaExperiencePreferences.self, from: $0) } ?? QuotaExperiencePreferences()
        engine.configure(prefs); persist()
        if prefs.recoveryNotificationEnabled || prefs.bank { permission() }
    }
    private var copy: ExperienceCopy { ExperienceCopy(language()) }
    private func setNotificationStatus(_ message: String) {
        notificationStatus = message; statusLabel?.stringValue = message; statusLabel?.isHidden = message.isEmpty
    }
    @discardableResult private func persist() -> Bool {
        do { try store.save(engine.state); storageReady = true; return true }
        catch { storageReady = false; setNotificationStatus(copy.text("Could not save reminder state; no alert sent", "无法保存提醒状态，本次未发提醒", "無法儲存提醒狀態，本次未發提醒")); return false }
    }
    func resetBaseline() { router.cancelAuthenticationEpoch(engine.state.epoch); engine.resetBaseline(); lastObservation = nil; onCancelCelebration?() }
    func accountCleared() {
        router.cancelAuthenticationEpoch(engine.state.epoch); engine.rotateEpoch(); sequence = 0; lastObservation = nil
        onCancelCelebration?(); persist()
    }
    func receive(_ quota: AllowanceSnapshot, bank: BankFieldState) {
        sequence += 1
        let o = QuotaObservation(epoch: engine.state.epoch, sequence: sequence, receivedAt: quota.receivedAt, quota: quota, bankFieldState: bank)
        lastObservation = o
        let result = engine.observe(o, now: Date())
        guard persist() else { return }
        if !result.recoveries.isEmpty {
            if preferences.celebration { onCelebrate?() }
            if preferences.recoveryNotificationEnabled { enqueue(.recovery, title: copy.text("Quota restored", "额度已恢复", "額度已恢復"), body: copy.recoveryBody(quota)) }
        }
        if !result.bank.isEmpty { enqueue(.bank, title: copy.text("Bank credits expiring", "Bank 权益即将到期", "Bank 權益即將到期"), body: copy.bankBody(result.bank), bank: result.bank) }
    }
    private func enqueue(_ kind: ExperienceNotificationKind, title: String, body: String, bank: [BankExpiryEvent] = []) {
        let epoch = engine.state.epoch
        let deadline = kind == .bank ? min(Date().addingTimeInterval(120), bank.map(\.expiresAt).min() ?? Date()) : nil
        let message = ExperienceNotification(id: "quotabar-\(UUID())", kind: kind, epoch: epoch, title: title, body: body, createdAt: Date(), validUntil: deadline)
        router.enqueue(message, valid: { [weak self] in
            guard let self, storageReady, engine.state.epoch == epoch else { return false }
            if kind == .recovery { return preferences.recoveryNotificationEnabled }
            if kind == .test { return true }
            guard preferences.bank, let latest = lastObservation else { return false }
            return engine.bankEventsAreCurrent(bank, observation: latest, now: Date())
        }, failed: { [weak self] in
            guard let self else { return }; setNotificationStatus(copy.text("System notifications unavailable; check system settings", "系统提醒不可用，请检查系统设置", "系統提醒不可用，請檢查系統設定"))
        })
    }
    func stop() { router.cancelAuthenticationEpoch(engine.state.epoch); onCancelCelebration?() }
    func makeSettingsView() -> NSView {
        let stack = QuotaSettingsStyle.column(12)
        let rows = QuotaSettingsStyle.column(0)
        let labels = [copy.text("Quota mood mode", "额度表情模式", "額度表情模式"), copy.text("Notify when quota is restored", "额度恢复时提醒", "額度恢復時提醒"), copy.text("Celebrate quota recovery", "额度恢复时播放小庆祝", "額度恢復時播放小慶祝"), copy.text("Bank expiry reminders", "Bank 到期提醒", "Bank 到期提醒")]
        let hints = [copy.text("Show the battery character for your current quota.", "根据当前额度状态，显示对应的电池表情。", "根據目前額度狀態，顯示對應的電池表情。"), copy.text("A system notification after confirmed recovery.", "额度确认恢复时，显示系统通知。", "額度確認恢復時，顯示系統通知。"), copy.text("A brief celebration with one recovery notification.", "播放短暂庆祝，并同步一条恢复通知。", "播放短暫慶祝，並同步一條恢復通知。"), copy.text("Known credits only; never redeem automatically.", "仅提醒已知权益，不会自动兑换。", "僅提醒已知權益，不會自動兌換。")]
        for i in 0..<4 {
            let row = NSStackView(); row.spacing = 20; row.alignment = .centerY; row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            let left = QuotaSettingsStyle.column(10)
            let title = NSStackView(); title.spacing = 12
            let name = QuotaSettingsStyle.label(labels[i], size: 13); name.font = .systemFont(ofSize: 13, weight: .semibold)
            let toggle = QuotaSettingsSwitch(); toggle.tag = i; toggle.target = self; toggle.action = #selector(changed(_:)); toggle.setAccessibilityLabel(labels[i])
            toggle.state = [preferences.moods, preferences.recovery, preferences.celebration, preferences.bank][i] ? .on : .off
            title.addArrangedSubview(name); title.addArrangedSubview(toggle); left.addArrangedSubview(title)
            QuotaSettingsStyle.fill(QuotaSettingsStyle.label(hints[i], size: 11, secondary: true), in: left)
            left.widthAnchor.constraint(equalToConstant: 255).isActive = true; row.addArrangedSubview(left)
            let right: NSView
            if i == 0 {
                let legend = NSStackView(); legend.spacing = 10
                for (index, mood) in [QuotaMood.good, .low, .exhausted, .unavailable, .recovered].enumerated() {
                    let item = QuotaSettingsStyle.column(5); item.alignment = .centerX
                    let icon = moodView(mood, size: 42); icon.identifier = NSUserInterfaceItemIdentifier("settings.mood.\(mood.rawValue)")
                    item.addArrangedSubview(icon); item.addArrangedSubview(QuotaSettingsStyle.label([copy.text("Good", "充足", "充足"), copy.text("Low", "偏低", "偏低"), copy.text("Empty", "耗尽", "耗盡"), copy.text("Unavailable", "不可用", "無法使用"), copy.text("Restored", "恢复", "恢復")][index], size: 10)); legend.addArrangedSubview(item)
                }
                right = legend
            } else if i == 1 {
                let example = QuotaSettingsStyle.column(5)
                let title = QuotaSettingsStyle.label("QuotaBar · " + copy.text("Quota restored", "额度已恢复", "額度已恢復"), size: 12); title.font = .systemFont(ofSize: 12, weight: .semibold)
                example.addArrangedSubview(title)
                example.addArrangedSubview(QuotaSettingsStyle.label(copy.text("Example: 5h 80% · 7d 36%", "示例：5 小时 80% · 7 天 36%", "範例：5 小時 80% · 7 天 36%"), size: 11, secondary: true))
                let notification = NSStackView(); notification.spacing = 12
                let bell = NSImageView(image: NSImage(systemSymbolName: "bell", accessibilityDescription: nil)!); bell.imageScaling = .scaleProportionallyUpOrDown
                bell.widthAnchor.constraint(equalToConstant: 30).isActive = true; bell.heightAnchor.constraint(equalToConstant: 34).isActive = true
                notification.addArrangedSubview(bell); notification.addArrangedSubview(QuotaSettingsStyle.card(example)); right = notification
            } else if i == 2 {
                let previewRow = NSStackView(); previewRow.spacing = 16
                let icon = moodView(.recovered, size: 58); icon.stars = true; previewRow.addArrangedSubview(icon)
                previewRow.addArrangedSubview(NSButton(title: copy.text("Preview", "预览", "預覽"), target: self, action: #selector(preview)))
                right = previewRow
            } else {
                let bank = NSStackView(); bank.spacing = 14
                let illustration = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 44))
                illustration.widthAnchor.constraint(equalToConstant: 48).isActive = true; illustration.heightAnchor.constraint(equalToConstant: 44).isActive = true
                let icon = NSImageView(image: NSImage(systemSymbolName: "building.columns", accessibilityDescription: nil)!)
                icon.frame = NSRect(x: 0, y: 8, width: 36, height: 36); icon.imageScaling = .scaleProportionallyUpOrDown; icon.contentTintColor = .secondaryLabelColor
                illustration.addSubview(icon)
                let clock = NSImageView(image: NSImage(systemSymbolName: "clock", accessibilityDescription: nil)!); clock.frame = NSRect(x: 25, y: 0, width: 22, height: 22); clock.imageScaling = .scaleProportionallyUpOrDown; illustration.addSubview(clock)
                bank.addArrangedSubview(illustration); bank.addArrangedSubview(QuotaSettingsStyle.label(copy.text("72 hours / 24 hours before expiry", "提前 72 小时 / 24 小时", "提前 72 小時 / 24 小時"), size: 12))
                right = bank
            }
            row.addArrangedSubview(right)
            let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); row.addArrangedSubview(spacer)
            QuotaSettingsStyle.fill(row, in: rows)
            if i != 3 { QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: rows) }
        }
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(rows), in: stack)
        let controls = NSStackView(); controls.spacing = 12
        controls.addArrangedSubview(QuotaSettingsStyle.label(copy.text("Preview and test", "预览与测试", "預覽與測試"), size: 12))
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); controls.addArrangedSubview(spacer)
        controls.addArrangedSubview(NSButton(title: copy.text("Preview celebration", "预览庆祝", "預覽慶祝"), target: self, action: #selector(preview)))
        controls.addArrangedSubview(NSButton(title: copy.text("Send test notification", "发送测试通知", "傳送測試通知"), target: self, action: #selector(testNotification)))
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(controls), in: stack)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(copy.text("Celebrations play only while the floating button is visible. Previews use example notifications.", "小庆祝仅在悬浮按钮可见时播放；预览同步发送示例通知。", "小慶祝僅在懸浮按鈕可見時播放；預覽同步傳送範例通知。"), size: 11, secondary: true), in: stack)
        let status = QuotaSettingsStyle.label(notificationStatus, size: 11, secondary: true); status.isHidden = notificationStatus.isEmpty; stack.addArrangedSubview(status); statusLabel = status
        return stack
    }
    private func moodView(_ mood: QuotaMood, size: CGFloat) -> QuotaMoodView {
        let view = QuotaMoodView(frame: NSRect(x: 0, y: 0, width: size, height: size)); view.mood = mood; view.usesEffectiveAppearance = true; view.stars = mood == .recovered
        view.widthAnchor.constraint(equalToConstant: size).isActive = true; view.heightAnchor.constraint(equalToConstant: size).isActive = true
        view.setAccessibilityElement(true); view.setAccessibilityRole(.image); view.setAccessibilityLabel(copy.moodLabel(mood))
        return view
    }
    @objc private func changed(_ sender: QuotaSettingsSwitch) {
        var p = preferences; let on = sender.state == .on
        switch sender.tag { case 0: p.moods = on; case 1: p.recovery = on; case 2: p.celebration = on; default: p.bank = on }
        engine.configure(p); defaults.set(try? JSONEncoder().encode(p), forKey: "experience.preferences")
        if !p.celebration { onCancelCelebration?() }
        if on && (sender.tag == 1 || sender.tag == 2 || sender.tag == 3) { permission() }
        onChange?()
    }
    private func permission() { requestNotificationPermission { [weak self] result in
        guard let self else { return }; notificationStatus = result.isEmpty ? "" : copy.text("Notifications unavailable; allow QuotaBar in system settings", "系统提醒不可用，请在系统设置允许 QuotaBar 通知", "系統提醒不可用，請在系統設定允許 QuotaBar 通知"); statusLabel?.stringValue = notificationStatus; statusLabel?.isHidden = notificationStatus.isEmpty
    } }
    @objc private func preview() { onCelebrate?(); testNotification() }
    @objc private func testNotification() {
        router.requestPermission { [weak self] result in
            guard let self else { return }
            if result.isEmpty { enqueue(.test, title: "QuotaBar " + copy.text("test notification", "测试通知", "測試通知"), body: copy.text("Example only — your quota and reminder history are unchanged.", "这是一条示例通知，不改变真实额度及提醒记录。", "這是一條範例通知，不改變真實額度及提醒記錄。")) }
            else { setNotificationStatus(copy.text("System notifications unavailable", "系统提醒不可用", "系統提醒不可用")) }
        }
    }
}
private extension NSBox {
    static func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }
}
