import AppKit
import QuotaCore

@MainActor final class QuotaExperienceController: NSObject {
    private let store: QuotaExperienceStore
    private let defaults: UserDefaults
    private var engine: QuotaExperienceEngine
    private var sequence = 0
    private var lastObservation: QuotaObservation?
    private let language: () -> CodexDisplayLanguage
    private let router: AppNotificationRouter
    private weak var statusLabel: NSTextField?
    private var storageReady = true
    private var notificationMessage: (String, String, String)?
    private var notificationStatus: String {
        guard let message = notificationMessage else { return "" }
        return copy.text(message.0, message.1, message.2)
    }
    private let requestNotificationPermission: (@escaping (String) -> Void) -> Void
    var onChange: (() -> Void)?
    var onShowUnread: (() -> Void)?
    var onEnableFloating: (() -> Void)?
    var floatingVisible: () -> Bool = { false }
    var onCelebrate: (() -> Void)?
    var onCancelCelebration: (() -> Void)?
    var preferences: QuotaExperiencePreferences { engine.preferences }
    init(root: URL, defaults: UserDefaults = .standard, language: @escaping () -> CodexDisplayLanguage, requestPermission: ((@escaping (String) -> Void) -> Void)? = nil, router: AppNotificationRouter? = nil) {
        self.router = router ?? .shared
        self.requestNotificationPermission = requestPermission ?? { AppNotificationRouter.shared.requestPermission(completion: $0) }
        self.defaults = defaults; self.language = language; store = QuotaExperienceStore(url: root.appendingPathComponent("experience-state.json"))
        let state = store.load(); engine = QuotaExperienceEngine(state: state, suppressFirstBank: store.corrupted)
        super.init()
        let prefs = defaults.data(forKey: "experience.preferences").flatMap { try? JSONDecoder().decode(QuotaExperiencePreferences.self, from: $0) } ?? QuotaExperiencePreferences()
        engine.configure(prefs); persist()
        // No startup permission prompt; only explicit system-channel choices request permission.
    }
    private var copy: ExperienceCopy { ExperienceCopy(language()) }
    private func setNotificationStatus(_ message: (String, String, String)?) {
        notificationMessage = message; statusLabel?.stringValue = notificationStatus; statusLabel?.isHidden = notificationStatus.isEmpty
    }
    @discardableResult private func persist() -> Bool {
        do { try store.save(engine.state); storageReady = true; return true }
        catch { storageReady = false; setNotificationStatus(("Could not save reminder state; no alert sent", "无法保存提醒状态，本次未发提醒", "無法儲存提醒狀態，本次未發提醒")); return false }
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
        router.observeQuota(o)
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
            guard let self else { return }; setNotificationStatus(("System notifications unavailable; check system settings", "系统提醒不可用，请检查系统设置", "系統提醒不可用，請檢查系統設定"))
        })
    }
    func stop() { router.cancelAuthenticationEpoch(engine.state.epoch); onCancelCelebration?() }
    func makeSettingsView() -> NSView {
        let stack = QuotaSettingsStyle.column(12)
        let channel = NotificationSettingsView(router: router, language: language(), floatingVisible: floatingVisible(), preview: { [weak self] in self?.previewBubble() }, showUnread: { [weak self] in self?.onShowUnread?() }, enableFloating: { [weak self] in self?.onEnableFloating?() })
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(channel), in: stack)
        let rows = QuotaSettingsStyle.column(0)
        let labels = [copy.text("Quota mood mode", "额度表情模式", "額度表情模式"), copy.text("Notify when quota is restored", "额度恢复时提醒", "額度恢復時提醒"), copy.text("Celebrate quota recovery", "额度恢复时播放小庆祝", "額度恢復時播放小慶祝"), copy.text("Bank expiry reminders", "Bank 到期提醒", "Bank 到期提醒")]
        let hints = [copy.text("Show the battery character for your current quota.", "根据当前额度状态，显示对应的电池表情。", "根據目前額度狀態，顯示對應的電池表情。"), copy.text("A reminder after confirmed recovery.", "额度确认恢复时，按所选方式提醒。", "額度確認恢復時，依所選方式提醒。"), copy.text("A brief celebration with one recovery notification.", "播放短暂庆祝，并同步一条恢复通知。", "播放短暫慶祝，並同步一條恢復通知。"), copy.text("Known credits only; never redeem automatically.", "仅提醒已知权益，不会自动兑换。", "僅提醒已知權益，不會自動兌換。")]
        for i in 0..<4 {
            let item = QuotaSettingsStyle.column(8)
            let toggle = QuotaSettingsSwitch(); toggle.tag = i; toggle.target = self; toggle.action = #selector(changed(_:)); toggle.setAccessibilityLabel(labels[i])
            toggle.state = [preferences.moods, preferences.recovery, preferences.celebration, preferences.bank][i] ? .on : .off
            QuotaSettingsStyle.fill(QuotaSettingsStyle.row(labels[i], control: toggle, hint: hints[i]), in: item)
            if i == 0 {
                let legend = NSStackView(); legend.spacing = 16; legend.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
                for (index, mood) in [QuotaMood.good, .low, .exhausted, .unavailable, .recovered].enumerated() {
                    let cell = QuotaSettingsStyle.column(4); cell.alignment = .centerX
                    let icon = moodView(mood, size: 36); icon.identifier = NSUserInterfaceItemIdentifier("settings.mood.\(mood.rawValue)")
                    cell.addArrangedSubview(icon)
                    cell.addArrangedSubview(QuotaSettingsStyle.label([copy.text("Good", "充足", "充足"), copy.text("Low", "偏低", "偏低"), copy.text("Empty", "耗尽", "耗盡"), copy.text("Unavailable", "不可用", "無法使用"), copy.text("Restored", "恢复", "恢復")][index], size: 10, secondary: true))
                    legend.addArrangedSubview(cell)
                }
                item.addArrangedSubview(legend)
            } else if i == 1 {
                QuotaSettingsStyle.fill(QuotaSettingsStyle.label(copy.text("Example: Quota restored · 5h 80% · 7d 36%", "示例：额度已恢复 · 5 小时 80% · 7 天 36%", "範例：額度已恢復 · 5 小時 80% · 7 天 36%"), size: 11, secondary: true), in: item)
            } else if i == 2 {
                let previewRow = NSStackView(); previewRow.spacing = 12
                previewRow.addArrangedSubview(moodView(.recovered, size: 36))
                previewRow.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Preview celebration", "预览庆祝", "預覽慶祝"), target: self, action: #selector(preview)))
                item.addArrangedSubview(previewRow)
            } else {
                QuotaSettingsStyle.fill(QuotaSettingsStyle.label(copy.text("72 hours and 24 hours before expiry; credits are grouped.", "提前 72 小时和 24 小时提醒，同批权益合并。", "提前 72 小時與 24 小時提醒，同批權益合併。"), size: 11, secondary: true), in: item)
            }
            item.edgeInsets.bottom = 12
            QuotaSettingsStyle.fill(item, in: rows)
            if i < 3 { QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: rows) }
        }
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(rows), in: stack)
        let testing = QuotaSettingsStyle.column(8)
        testing.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Send test notification", "发送测试通知", "傳送測試通知"), target: self, action: #selector(testNotification)))
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(copy.text("Celebrations play only while the floating button is visible. Tests use example notifications and do not change reminder history.", "小庆祝仅在悬浮按钮可见时播放；测试使用示例通知，不改变提醒记录。", "小慶祝僅在懸浮按鈕可見時播放；測試使用範例通知，不改變提醒記錄。"), size: 11, secondary: true), in: testing)
        QuotaSettingsStyle.fill(testing, in: stack)
        let status = QuotaSettingsStyle.label(notificationStatus, size: 11, secondary: true); status.isHidden = notificationStatus.isEmpty; stack.addArrangedSubview(status); statusLabel = status
        stack.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Notification settings…", "通知设置…", "通知設定…"), target: self, action: #selector(openNotificationSettings)))
        return stack
    }
    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
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
        engine.configure(p); defaults.set(try? JSONEncoder().encode(p), forKey: "experience.preferences"); router.bark?.cancelInvalid()
        if !p.celebration { onCancelCelebration?() }
        if on && (sender.tag == 1 || sender.tag == 2 || sender.tag == 3) { permission() }
        onChange?()
    }
    func permission() {
        guard router.preferences.mode.usesSystem else { return }
        requestNotificationPermission { [weak self] result in
        guard let self else { return }
        if result.isEmpty { router.retryFailedDeliveries() }
        setNotificationStatus(result.isEmpty ? nil : ("Notifications unavailable; allow QuotaBar in system settings", "系统提醒不可用，请在系统设置允许 QuotaBar 通知", "系統提醒不可用，請在系統設定允許 QuotaBar 通知"))
    } }
    private func previewBubble() {
        let message = ExperienceNotification(id: "preview-\(UUID())", kind: .test, epoch: nil, title: copy.text("Example notification", "示例通知", "範例通知"), body: copy.text("5 hours remaining 100%; 7 days remaining 36%. Example only.", "5 小时剩余 100%；7 天剩余 36%。仅为示例。", "5 小時剩餘 100%；7 天剩餘 36%。僅為範例。"), createdAt: Date())
        if !router.preview(message) { setNotificationStatus(("Show the floating button and close quota details to preview.", "请开启悬浮按钮并收起额度详情后预览。", "請開啟懸浮按鈕並收起額度詳情後預覽。")) }
    }
    @objc private func preview() { onCelebrate?(); testNotification() }
    @objc private func testNotification() {
        if !router.preferences.mode.usesSystem { enqueue(.test, title: copy.text("Example notification", "示例通知", "範例通知"), body: copy.text("Example only — reminder history is unchanged.", "示例提醒，不改变真实额度及提醒记录。", "範例提醒，不改變真實額度及提醒記錄。")); return }
        requestNotificationPermission { [weak self] result in
            guard let self else { return }
            if result.isEmpty || router.preferences.mode.usesBubble { enqueue(.test, title: "QuotaBar " + copy.text("test notification", "测试通知", "測試通知"), body: copy.text("Example only — your quota and reminder history are unchanged.", "这是一条示例通知，不改变真实额度及提醒记录。", "這是一條範例通知，不改變真實額度及提醒記錄。")) }
            else { setNotificationStatus(("System notifications unavailable", "系统提醒不可用", "系統提醒不可用")) }
        }
    }
}
private extension NSBox {
    static func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }
}
