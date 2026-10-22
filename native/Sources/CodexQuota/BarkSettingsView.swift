import AppKit

@MainActor final class BarkSettingsView: NSView, NSTextFieldDelegate {
    private let controller: BarkNotificationController?
    private let text: (String, String, String) -> String
    private let toggle = QuotaSettingsSwitch()
    let keyField = NSSecureTextField()
    private let statusField = QuotaSettingsStyle.label("", secondary: true)
    private var testButton: NSButton!
    init(controller: BarkNotificationController?, text: @escaping (String, String, String) -> String) {
        self.controller = controller; self.text = text
        super.init(frame: .zero)
        let stack = QuotaSettingsStyle.column(20)
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Receive quota recovery, Bank expiry and update reminders through Bark.", "通过 Bark 接收额度恢复、Bank 到期和软件更新提醒。", "透過 Bark 接收額度恢復、Bank 到期和軟體更新提醒。"), secondary: true), in: stack)
        let connection = QuotaSettingsStyle.column(10)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label("Bark", size: 16), in: connection)
        toggle.target = self; toggle.action = #selector(toggleChanged)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Enable mobile push", "启用手机推送", "啟用手機推播"), control: toggle), in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Official server: https://api.day.app", "官方服务器：https://api.day.app", "官方伺服器：https://api.day.app"), secondary: true), in: connection)
        keyField.placeholderString = text("Paste Device Key from Bark", "粘贴从 Bark 复制的 Device Key", "貼上從 Bark 複製的 Device Key")
        keyField.stringValue = controller?.draft ?? ""; keyField.delegate = self
        keyField.setAccessibilityLabel("Bark Device Key")
        keyField.identifier = NSUserInterfaceItemIdentifier("bark.deviceKey")
        QuotaSettingsStyle.fill(keyField, in: connection)
        let actions = NSStackView(); actions.spacing = 8; actions.distribution = .fillProportionally
        actions.addArrangedSubview(QuotaSettingsStyle.button(text("Save Key", "保存 Key", "儲存 Key"), target: self, action: #selector(save)))
        actions.addArrangedSubview(QuotaSettingsStyle.button(text("Clear Key", "清除 Key", "清除 Key"), target: self, action: #selector(clear)))
        testButton = QuotaSettingsStyle.button(text("Send test push", "发送测试推送", "傳送測試推播"), target: self, action: #selector(test))
        actions.addArrangedSubview(testButton); QuotaSettingsStyle.fill(actions, in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(connection), in: stack)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.section(text("Status", "状态", "狀態"), content: statusField), in: stack)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Independent of desktop bubbles. When enabled, reminder titles and text are sent over HTTPS to Bark and APNs. Keys stay in Keychain and are never logged. Test push uses example data only. Bark and iOS control delivery and display.", "独立于桌面气泡。启用后，提醒标题和正文经 HTTPS 发送至 Bark 与 APNs。Key 仅保存在钥匙串，不写日志。测试推送仅使用示例数据。Bark 与 iOS 控制实际送达和展示。", "獨立於桌面氣泡。啟用後，提醒標題和正文經 HTTPS 傳送至 Bark 與 APNs。Key 僅儲存在鑰匙圈，不寫入日誌。測試推播僅使用範例資料。Bark 與 iOS 控制實際送達與顯示。"), secondary: true), in: stack)
        controller?.onChange = { [weak self] in self?.refresh() }; refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func controlTextDidChange(_ obj: Notification) { controller?.draft = keyField.stringValue }
    @objc private func toggleChanged() { _ = controller?.setEnabled(toggle.state == .on); refresh() }
    @objc private func save() { if controller?.saveKey(keyField.stringValue) == true { keyField.stringValue = "" }; refresh() }
    @objc private func clear() { if controller?.clearKey() == true { keyField.stringValue = "" }; refresh() }
    @objc private func test() { controller?.sendTest(title: text("QuotaBar test", "QuotaBar 测试", "QuotaBar 測試"), body: text("Example: quota recovered to 100%.", "示例：额度已恢复至 100%。", "範例：額度已恢復至 100%。")) }
    private func refresh() {
        toggle.state = controller?.preferences.enabled == true ? .on : .off
        toggle.isEnabled = controller?.configured == true
        testButton.isEnabled = controller?.configured == true && controller?.testing != true
        let status = controller?.status ?? .unconfigured
        let value: String
        switch status {
        case .unconfigured: value = text("Not configured", "未配置", "未設定")
        case .configured: value = text("Configured", "已配置", "已設定")
        case .unavailable: value = text("Secure storage unavailable", "安全存储不可用", "安全儲存無法使用")
        case .invalidKey: value = text("Invalid Device Key. Copy the key, not its URL.", "Device Key 无效，请复制 Key 而非完整网址。", "Device Key 無效，請複製 Key 而非完整網址。")
        case .sending: value = text("Sending…", "请求中…", "請求中…")
        case .accepted: value = text("Bark service accepted", "Bark 服务已接受", "Bark 服務已接受")
        case .failed: value = text("Send failed", "发送失败", "傳送失敗")
        case .unknown: value = text("Result unknown", "发送结果未知", "傳送結果未知")
        case .capacity: value = text("Push capacity reached; current event suppressed", "推送容量已满，当前事件已抑制", "推播容量已滿，目前事件已抑制")
        case .historyRecovery: value = text("Reminder history recovered; enable again to resume new reminders", "提醒记录已恢复；请重新开启以接收新提醒", "提醒記錄已恢復；請重新開啟以接收新提醒")
        case .persistenceFailure: value = text("Receipt storage unavailable; push suppressed", "收据存储不可用，已抑制推送", "收據儲存無法使用，已抑制推播")
        }
        statusField.stringValue = value + (controller?.lastOperation.map { "\n" + DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .medium) } ?? "")
    }
}
