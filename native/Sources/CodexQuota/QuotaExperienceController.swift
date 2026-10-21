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
    var onChange: (() -> Void)?
    var onCelebrate: (() -> Void)?
    var onCancelCelebration: (() -> Void)?
    var preferences: QuotaExperiencePreferences { engine.preferences }
    init(root: URL, defaults: UserDefaults = .standard, language: @escaping () -> CodexDisplayLanguage) {
        self.defaults = defaults; self.language = language; store = QuotaExperienceStore(url: root.appendingPathComponent("experience-state.json"))
        let state = store.load(); engine = QuotaExperienceEngine(state: state, suppressFirstBank: store.corrupted)
        super.init()
        let prefs = defaults.data(forKey: "experience.preferences").flatMap { try? JSONDecoder().decode(QuotaExperiencePreferences.self, from: $0) } ?? QuotaExperiencePreferences()
        engine.configure(prefs); persist()
    }
    private var copy: ExperienceCopy { ExperienceCopy(language()) }
    @discardableResult private func persist() -> Bool {
        do { try store.save(engine.state); storageReady = true; return true }
        catch { storageReady = false; statusLabel?.stringValue = copy.text("Could not save reminder state; no alert sent", "无法保存提醒状态，本次未发提醒", "無法儲存提醒狀態，本次未發提醒"); return false }
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
            if preferences.recovery { enqueue(.recovery, title: copy.text("Quota restored", "额度已恢复", "額度已恢復"), body: copy.recoveryBody(quota)) }
        }
        if !result.bank.isEmpty { enqueue(.bank, title: copy.text("Bank credits expiring", "Bank 权益即将到期", "Bank 權益即將到期"), body: copy.bankBody(result.bank), bank: result.bank) }
    }
    private func enqueue(_ kind: ExperienceNotificationKind, title: String, body: String, bank: [BankExpiryEvent] = []) {
        let epoch = engine.state.epoch
        let deadline = kind == .bank ? min(Date().addingTimeInterval(120), bank.map(\.expiresAt).min() ?? Date()) : nil
        let message = ExperienceNotification(id: "quotabar-\(UUID())", kind: kind, epoch: epoch, title: title, body: body, createdAt: Date(), validUntil: deadline)
        router.enqueue(message, valid: { [weak self] in
            guard let self, storageReady, engine.state.epoch == epoch else { return false }
            if kind == .recovery { return preferences.recovery }
            if kind == .test { return true }
            guard preferences.bank, let latest = lastObservation else { return false }
            return engine.bankEventsAreCurrent(bank, observation: latest, now: Date())
        }, failed: { [weak self] in
            guard let self else { return }; statusLabel?.stringValue = copy.text("System notifications unavailable; check system settings", "系统提醒不可用，请检查系统设置", "系統提醒不可用，請檢查系統設定")
        })
    }
    func stop() { router.cancelAuthenticationEpoch(engine.state.epoch); onCancelCelebration?() }
    func makeSettingsView() -> NSView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.addArrangedSubview(NSBox.separator())
        stack.addArrangedSubview(NSTextField(labelWithString: copy.text("Quota moods and reminders", "额度表情与提醒", "額度表情與提醒")))
        let labels = [copy.text("Quota mood mode", "额度表情模式", "額度表情模式"), copy.text("Notify when quota is restored", "额度恢复时提醒", "額度恢復時提醒"), copy.text("Celebrate quota recovery", "额度恢复时播放小庆祝", "額度恢復時播放小慶祝"), copy.text("Bank expiry reminders", "Bank 到期提醒", "Bank 到期提醒")]
        for i in 0..<4 {
            let button = NSButton(checkboxWithTitle: labels[i], target: self, action: #selector(changed(_:))); button.tag = i
            button.state = [preferences.moods, preferences.recovery, preferences.celebration, preferences.bank][i] ? .on : .off; stack.addArrangedSubview(button)
        }
        let note = NSTextField(wrappingLabelWithString: copy.text("Bank: 72 and 24 hours before expiry. Celebrations play only while the floating button is visible.", "Bank 提前72小时和24小时提醒，同批合并。小庆祝仅在悬浮按钮可见时播放。", "Bank 提前72小時和24小時提醒，同批合併。小慶祝僅在懸浮按鈕可見時播放。")); note.font = .systemFont(ofSize: 11); stack.addArrangedSubview(note)
        let row = NSStackView(); row.addArrangedSubview(NSButton(title: copy.text("Preview celebration", "预览庆祝", "預覽慶祝"), target: self, action: #selector(preview)))
        row.addArrangedSubview(NSButton(title: copy.text("Send test notification", "发送测试通知", "傳送測試通知"), target: self, action: #selector(testNotification))); stack.addArrangedSubview(row)
        let status = NSTextField(wrappingLabelWithString: ""); status.font = .systemFont(ofSize: 11); stack.addArrangedSubview(status); statusLabel = status
        return stack
    }
    @objc private func changed(_ sender: NSButton) {
        var p = preferences; let on = sender.state == .on
        switch sender.tag { case 0: p.moods = on; case 1: p.recovery = on; case 2: p.celebration = on; default: p.bank = on }
        engine.configure(p); defaults.set(try? JSONEncoder().encode(p), forKey: "experience.preferences")
        if !p.celebration { onCancelCelebration?() }
        if on && (sender.tag == 1 || sender.tag == 3) { permission() }
        onChange?()
    }
    private func permission() { router.requestPermission { [weak self] result in
        guard let self else { return }; statusLabel?.stringValue = result.isEmpty ? "" : copy.text("Notifications unavailable; allow QuotaBar in system settings", "系统提醒不可用，请在系统设置允许 QuotaBar 通知", "系統提醒不可用，請在系統設定允許 QuotaBar 通知")
    } }
    @objc private func preview() { onCelebrate?() }
    @objc private func testNotification() {
        router.requestPermission { [weak self] result in
            guard let self else { return }
            if result.isEmpty { enqueue(.test, title: "QuotaBar " + copy.text("test notification", "测试通知", "測試通知"), body: copy.text("Example only — your quota and reminder history are unchanged.", "这是一条示例通知，不改变真实额度及提醒记录。", "這是一條範例通知，不改變真實額度及提醒記錄。")) }
            else { statusLabel?.stringValue = copy.text("System notifications unavailable", "系统提醒不可用", "系統提醒不可用") }
        }
    }
}
private extension NSBox {
    static func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }
}
