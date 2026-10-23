import AppKit

@MainActor final class BarkSettingsView: NSView, NSTextFieldDelegate {
    private let controller: BarkNotificationController?
    private let text: (String, String, String) -> String
    private let toggle = QuotaSettingsSwitch()
    let keyField = NSSecureTextField()
    private let plain = NSTextField()
    private let eye = NSButton()
    private let statusField = QuotaSettingsStyle.label("", secondary: true)
    private var testButtons: [NSButton] = []
    private weak var saveControl: NSButton?
    private var showingSaved = false
    var onLayoutChange: (() -> Void)?
    private var revealed = false
    init(controller: BarkNotificationController?, text: @escaping (String, String, String) -> String) {
        self.controller = controller; self.text = text
        super.init(frame: .zero)
        let stack = QuotaSettingsStyle.column(14)
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Receive quota reminders on your iPhone with Bark.", "通过 Bark 在 iPhone 接收额度提醒。", "透過 Bark 在 iPhone 接收額度提醒。"), secondary: true), in: stack)
        let connection = QuotaSettingsStyle.column(10)
        let heading = NSStackView(); heading.alignment = .centerY; heading.spacing = 12
        let bell = NSImageView(image: NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)!); bell.contentTintColor = .systemPink
        bell.widthAnchor.constraint(equalToConstant: 28).isActive = true; bell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        heading.addArrangedSubview(bell)
        let brand = QuotaSettingsStyle.label("Bark", size: 16); brand.font = .systemFont(ofSize: 16, weight: .semibold); heading.addArrangedSubview(brand)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal); heading.addArrangedSubview(spacer)
        heading.addArrangedSubview(QuotaSettingsStyle.label(text("Enable mobile push", "启用手机推送", "啟用手機推播"), size: 12))
        toggle.target = self; toggle.action = #selector(toggleChanged); toggle.setAccessibilityLabel(text("Enable mobile push", "启用手机推送", "啟用手機推播")); heading.addArrangedSubview(toggle)
        statusField.identifier = .init("bark.status"); statusField.font = .systemFont(ofSize: 11)
        statusField.widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true; heading.addArrangedSubview(statusField)
        QuotaSettingsStyle.fill(heading, in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label("Device Key", size: 13), in: connection)
        let input = NSView(); input.heightAnchor.constraint(equalToConstant: 34).isActive = true
        for (field, id) in [(keyField as NSTextField, "bark.deviceKey"), (plain, "bark.deviceKey.plain")] {
            field.placeholderString = text("Paste your Device Key", "粘贴 Device Key", "貼上 Device Key")
            field.font = .monospacedSystemFont(ofSize: 13, weight: .regular); field.delegate = self
            field.bezelStyle = .roundedBezel; field.identifier = .init(id); field.setAccessibilityLabel("Bark Device Key")
            field.translatesAutoresizingMaskIntoConstraints = false; input.addSubview(field)
            NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: input.leadingAnchor), field.trailingAnchor.constraint(equalTo: input.trailingAnchor, constant: -40), field.centerYAnchor.constraint(equalTo: input.centerYAnchor), field.heightAnchor.constraint(equalToConstant: 30)])
        }
        keyField.stringValue = controller?.draft ?? ""; plain.isHidden = true
        eye.target = self; eye.action = #selector(reveal); eye.isBordered = false; eye.identifier = .init("bark.reveal")
        eye.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil); eye.translatesAutoresizingMaskIntoConstraints = false; input.addSubview(eye)
        NSLayoutConstraint.activate([eye.trailingAnchor.constraint(equalTo: input.trailingAnchor), eye.widthAnchor.constraint(equalToConstant: 32), eye.centerYAnchor.constraint(equalTo: input.centerYAnchor)])
        eye.setAccessibilityLabel(text("Show Key", "显示 Key", "顯示 Key")); eye.toolTip = text("Show Key", "显示 Key", "顯示 Key")
        QuotaSettingsStyle.fill(input, in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Leave blank to keep the saved Key. Use the eye to view it.", "留空保留已保存的 Key；点击眼睛可查看。", "留空保留已儲存的 Key；按眼睛可查看。"), size: 11, secondary: true), in: connection)
        let actions = NSStackView(); actions.spacing = 8
        let save = QuotaSettingsStyle.button(text("Save Key", "保存 Key", "儲存 Key"), target: self, action: #selector(save), primary: true); save.bezelColor = .systemGreen; save.identifier = .init("bark.save"); saveControl = save; actions.addArrangedSubview(save)
        let clear = QuotaSettingsStyle.button(text("Clear", "清除", "清除"), target: self, action: #selector(clear)); clear.identifier = .init("bark.clear"); actions.addArrangedSubview(clear)
        let test = testButton(); actions.addArrangedSubview(test); QuotaSettingsStyle.fill(actions, in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Official server: https://api.day.app · Key stored in Keychain", "官方服务器：https://api.day.app · Key 安全保存在钥匙串", "官方伺服器：https://api.day.app · Key 安全儲存在鑰匙圈"), size: 11, secondary: true), in: connection)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(connection), in: stack)
        let guide = QuotaSettingsStyle.column(10)
        let guideTitle = QuotaSettingsStyle.label(text("Connection guide", "连接向导", "連線指南"), size: 14); guideTitle.font = .systemFont(ofSize: 14, weight: .semibold); QuotaSettingsStyle.fill(guideTitle, in: guide)
        let strip = BarkGuideStepStrip(text: text); strip.heightAnchor.constraint(equalToConstant: 32).isActive = true; QuotaSettingsStyle.fill(strip, in: guide)
        let diagram = BarkGuideDiagram(text: text); diagram.heightAnchor.constraint(equalToConstant: 168).isActive = true; QuotaSettingsStyle.fill(diagram, in: guide)
        let steps = NSStackView(); steps.distribution = .fillEqually; steps.alignment = .top; steps.spacing = 14
        func step(_ title: String, body: String, action: NSView) {
            let col = QuotaSettingsStyle.column(7); let label = QuotaSettingsStyle.label(title, size: 12); label.font = .systemFont(ofSize: 12, weight: .semibold); QuotaSettingsStyle.fill(label, in: col)
            let bodyLabel = QuotaSettingsStyle.label(body, size: 11, secondary: true); QuotaSettingsStyle.fill(bodyLabel, in: col)
            col.addArrangedSubview(action); steps.addArrangedSubview(col)
        }
        let download = SettingsLinkButton(text("Get Bark ↗", "获取 Bark ↗", "取得 Bark ↗"), destination: SettingsLinks.barkDownload); download.identifier = .init("bark.download"); download.usesAccentFill = true; download.fillColor = NSColor(srgbRed: 0, green: 101.0 / 255, blue: 216.0 / 255, alpha: 1); download.heightAnchor.constraint(equalToConstant: 30).isActive = true; download.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        step(text("① Install Bark", "① 安装 Bark", "① 安裝 Bark"), body: text("On iPhone, find Bark in the App Store. Install and allow notifications.", "在 iPhone 的 App Store 搜索 Bark，安装并允许通知。", "在 iPhone 的 App Store 搜尋 Bark，安裝並允許通知。"), action: download)
        step(text("② Get Device Key", "② 获取 Device Key", "② 取得 Device Key"), body: text("Open Bark. Copy only the Key from its test URL, not the whole URL.", "打开 Bark，只复制测试链接中的 Key，不要复制整个网址。", "開啟 Bark，只複製測試連結中的 Key，不要複製整個網址。"), action: QuotaSettingsStyle.label("api.day.app / Key / test", size: 10, secondary: true))
        step(text("③ Connect & test", "③ 连接并测试", "③ 連線並測試"), body: text("Paste Key → Save → Enable push → Send test.", "粘贴 Key → 保存 → 开启推送 → 发送测试。", "貼上 Key → 儲存 → 開啟推播 → 傳送測試。"), action: testButton())
        QuotaSettingsStyle.fill(steps, in: guide); QuotaSettingsStyle.fill(QuotaSettingsStyle.card(guide), in: stack)
        let tutorial = SettingsLinkButton(text("View official tutorial ↗", "查看官方教程 ↗", "查看官方教學 ↗"), destination: SettingsLinks.barkTutorial); tutorial.identifier = .init("bark.tutorial"); stack.addArrangedSubview(tutorial)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Independent of desktop bubbles. When enabled, titles and bodies go over HTTPS to Bark and APNs. Keys are not logged. Test sends sample data only; acceptance does not confirm phone display.", "独立于桌面气泡。启用后，提醒标题和正文经 HTTPS 发送至 Bark 与 APNs，Key 不写日志。测试仅发送示例数据；服务接受不代表手机已展示。", "獨立於桌面氣泡。啟用後，提醒標題和內文經 HTTPS 傳送至 Bark 與 APNs，Key 不寫入日誌。測試僅傳送範例資料；服務接受不代表手機已顯示。"), size: 11, secondary: true), in: stack)
        NotificationCenter.default.addObserver(self, selector: #selector(conceal), name: NSWindow.didResignKeyNotification, object: nil)
        controller?.onChange = { [weak self] in self?.refresh() }; refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func testButton() -> NSButton { let b = QuotaSettingsStyle.button(text("Send test push", "发送测试推送", "傳送測試推播"), target: self, action: #selector(test)); testButtons.append(b); return b }
    func controlTextDidChange(_ obj: Notification) {
        showingSaved = false
        let value = revealed ? plain.stringValue : keyField.stringValue
        controller?.draft = value; keyField.stringValue = value
    }
    @objc private func reveal() {
        if revealed { conceal(); return }
        let draft = keyField.stringValue
        let value = draft.isEmpty ? controller?.keyForExplicitReveal() : draft
        guard let value, !value.isEmpty else { return }
        showingSaved = draft.isEmpty; plain.isEditable = !showingSaved; plain.stringValue = value; keyField.isHidden = true; plain.isHidden = false; revealed = true
        saveControl?.isEnabled = !showingSaved && controller?.testing != true
        eye.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        eye.setAccessibilityLabel(text("Hide Key", "隐藏 Key", "隱藏 Key")); eye.toolTip = text("Hide Key", "隐藏 Key", "隱藏 Key")
    }
    @objc func conceal() {
        if revealed { keyField.stringValue = showingSaved ? "" : plain.stringValue }
        plain.stringValue = ""; plain.isHidden = true; keyField.isHidden = false; revealed = false; showingSaved = false
        saveControl?.isEnabled = controller?.testing != true
        eye.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        eye.setAccessibilityLabel(text("Show Key", "显示 Key", "顯示 Key")); eye.toolTip = text("Show Key", "显示 Key", "顯示 Key")
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { conceal() }; super.viewWillMove(toWindow: newWindow) }
    @objc private func toggleChanged() { _ = controller?.setEnabled(toggle.state == .on); refresh() }
    @objc private func save() { guard !showingSaved else { return }; let value = revealed ? plain.stringValue : keyField.stringValue; if controller?.saveKey(value) == true { conceal(); keyField.stringValue = "" }; refresh() }
    @objc private func clear() { if controller?.clearKey() == true { conceal(); keyField.stringValue = "" }; refresh() }
    @objc private func test() { controller?.sendTest(title: text("QuotaBar test", "QuotaBar 测试", "QuotaBar 測試"), body: text("Example: quota recovered to 100%.", "示例：额度已恢复至 100%。", "範例：額度已恢復至 100%。")) }
    private func refresh() {
        toggle.state = controller?.preferences.enabled == true ? .on : .off
        toggle.isEnabled = controller?.configured == true
        saveControl?.isEnabled = !showingSaved && controller?.testing != true
        testButtons.forEach { $0.isEnabled = controller?.configured == true && controller?.testing != true }
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
        case .capacity: value = text("Push capacity reached", "推送容量已满", "推播容量已滿")
        case .historyRecovery: value = text("History recovered; enable to resume", "提醒记录已恢复；请重新开启", "提醒記錄已恢復；請重新啟用")
        case .persistenceFailure: value = text("Receipt storage unavailable", "收据存储不可用", "收據儲存無法使用")
        }
        statusField.stringValue = value + (controller?.lastOperation.map { " · " + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "")
        needsLayout = true; onLayoutChange?()
    }
}
