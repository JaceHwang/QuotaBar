import AppKit
import QuotaCore

/// A: stable category rows and channel columns, with native keyboard-accessible controls.
@MainActor final class NotificationMatrixSettingsView: NSStackView {
    private var permissionRevision = 0
    private let router: AppNotificationRouter
    private let copy: ExperienceCopy
    private let categories: [NotificationCategory] = [.quotaLow, .quotaExhausted, .quotaRecovered, .bankExpiring72h, .bankExpiring24h, .updateAvailable]
    private var cells: [NSButton] = []
    private var masters: [NSButton] = []
    private let threshold = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let systemStatus = NSTextField(wrappingLabelWithString: "")
    private let mobileStatus = NSTextField(wrappingLabelWithString: "")
    private let pause = SettingsAccentButton(frame: .zero)
    private let preview: () -> Void
    private let unread: () -> Void
    init(router: AppNotificationRouter, language: CodexDisplayLanguage, preview: @escaping () -> Void, unread: @escaping () -> Void) {
        self.router = router; copy = ExperienceCopy(language); self.preview = preview; self.unread = unread
        super.init(frame: .zero); orientation = .vertical; alignment = .leading; spacing = 12
        let channels = NSStackView(); channels.orientation = .horizontal; channels.spacing = 16; channels.distribution = .fillEqually
        for (i, channel) in NotificationChannel.allCases.enumerated() {
            let column = QuotaSettingsStyle.column(5)
            let button = NSButton(checkboxWithTitle: channelTitle(channel), target: self, action: #selector(masterChanged(_:)))
            button.tag = i; button.identifier = .init("notification.master.\(channel.rawValue)"); button.setAccessibilityLabel(channelTitle(channel))
            masters.append(button); column.addArrangedSubview(button)
            let label = channel == .system ? systemStatus : channel == .mobile ? mobileStatus : QuotaSettingsStyle.label(copy.text("Independent channel", "独立接收渠道", "獨立接收管道"), size: 11, secondary: true)
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor; QuotaSettingsStyle.fill(label, in: column)
            channels.addArrangedSubview(column)
        }
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(channels), in: self)
        let heading = QuotaSettingsStyle.column(4)
        heading.addArrangedSubview(QuotaSettingsStyle.label(copy.text("Reminder content", "提醒内容", "提醒內容"), size: 14))
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(copy.text("Choose a channel for each reminder. All unchecked means off.", "为每类提醒选择渠道，全部取消即关闭。", "為每類提醒選擇管道，全部取消即關閉。"), size: 11, secondary: true), in: heading)
        let grid = NSGridView(); grid.columnSpacing = 12; grid.rowSpacing = 14
        grid.addRow(with: [heading] + NotificationChannel.allCases.map { QuotaSettingsStyle.label(channelTitle($0), size: 12, secondary: true) })
        for (i, category) in categories.enumerated() {
            let title = QuotaSettingsStyle.column(3)
            let name = QuotaSettingsStyle.label(categoryTitle(category), size: 13)
            let hint = QuotaSettingsStyle.label(categoryHint(category), size: 11, secondary: true)
            hint.identifier = .init("notification.hint.\(category.rawValue)")
            name.preferredMaxLayoutWidth = 240; hint.preferredMaxLayoutWidth = 240
            QuotaSettingsStyle.fill(name, in: title); QuotaSettingsStyle.fill(hint, in: title)
            if category == .quotaLow {
                threshold.addItems(withTitles: ["10%", "20%", "30%"]); threshold.identifier = .init("notification.threshold")
                threshold.target = self; threshold.action = #selector(thresholdChanged)
                threshold.setAccessibilityLabel(copy.text("Low remaining quota threshold", "剩余额度偏低阈值", "剩餘額度偏低閾值")); title.addArrangedSubview(threshold)
            }
            var row: [NSView] = [title]
            for (j, channel) in NotificationChannel.allCases.enumerated() {
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(ruleChanged(_:)))
                box.tag = i * 3 + j; box.identifier = .init("notification.rule.\(category.rawValue).\(channel.rawValue)")
                box.setAccessibilityLabel(categoryTitle(category) + " · " + channelTitle(channel)); cells.append(box); row.append(box)
            }
            grid.addRow(with: row)
        }
        for i in 1...3 { grid.column(at: i).width = 64; grid.column(at: i).xPlacement = .center }
        grid.column(at: 0).width = 240; grid.column(at: 0).xPlacement = .fill
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(grid), in: self)
        let actions = NSStackView(); actions.spacing = 8
        pause.target = self; pause.action = #selector(pauseTapped); pause.identifier = .init("notification.pause"); actions.addArrangedSubview(pause)
        actions.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Preview bubble", "预览气泡", "預覽氣泡"), target: self, action: #selector(previewTapped)))
        actions.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Unread reminders", "未读提醒", "未讀提醒"), target: self, action: #selector(unreadTapped)))
        addArrangedSubview(actions)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(copy.text("Pause affects bubbles only. Enabling a channel does not replay past reminders. Mobile setup is on the Mobile Push page.", "暂停仅影响气泡，开启渠道不补发历史提醒。手机推送请在手机推送页配置。", "暫停僅影響氣泡，開啟管道不補發歷史提醒。手機推播請在手機推播頁設定。"), size: 11, secondary: true), in: self)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; QuotaSettingsStyle.fill(status, in: self)
        systemStatus.stringValue = copy.text("Checking permission…", "正在读取权限…", "正在讀取權限…")
        refresh()
        let initialRevision = permissionRevision
        Task { [weak self] in
            guard let self else { return }
            let permission = await router.center?.notificationSettings().authorizationStatus
            guard permissionRevision == initialRevision else { return }
            systemStatus.stringValue = permission == .authorized || permission == .provisional ? copy.text("Authorized", "已授权", "已授權") : copy.text("Not authorized", "未授权", "未授權")
        }
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { refresh() } }

    private func channelTitle(_ c: NotificationChannel) -> String {
        switch c { case .bubble: copy.text("Bubble", "气泡", "氣泡"); case .system: copy.text("System", "系统", "系統"); case .mobile: copy.text("Mobile", "手机", "手機") }
    }
    private func categoryTitle(_ c: NotificationCategory) -> String {
        switch c {
        case .quotaLow: copy.text("Quota low", "额度偏低", "額度偏低")
        case .quotaExhausted: copy.text("Quota depleted", "额度耗尽", "額度耗盡")
        case .quotaRecovered: copy.text("Quota restored", "额度恢复", "額度恢復")
        case .bankExpiring72h: copy.text("Bank · 72 hours", "Bank · 提前72小时", "Bank · 提前72小時")
        case .bankExpiring24h: copy.text("Bank · 24 hours", "Bank · 提前24小时", "Bank · 提前24小時")
        case .updateAvailable: copy.text("Software update", "软件有新版本", "軟體有新版本")
        }
    }
    private func categoryHint(_ c: NotificationCategory) -> String {
        switch c {
        case .quotaLow: copy.text("When remaining quota crosses this threshold.", "剩余额度跨过阈值时提醒。", "剩餘額度跨過閾值時提醒。")
        case .quotaExhausted: copy.text("When either quota window runs out.", "任一额度周期耗尽时提醒。", "任一額度週期耗盡時提醒。")
        case .quotaRecovered: copy.text("After confirmed recovery; animation is separate.", "确认恢复后提醒，庆祝动画独立。", "確認恢復後提醒，慶祝動畫獨立。")
        case .bankExpiring72h, .bankExpiring24h: copy.text("Known reset credits expiring soon.", "已知重置权益即将到期。", "已知重置權益即將到期。")
        case .updateAvailable: copy.text("Respects skipped versions and remind later.", "遵循跳过版本和稍后提醒设置。", "遵循略過版本與稍後提醒設定。")
        }
    }
    private func refresh() {
        let p = router.policyPreferences
        for (i, box) in cells.enumerated() { box.state = p.rules[categories[i/3]]?.contains(NotificationChannel.allCases[i%3]) == true ? .on : .off }
        for (i, box) in masters.enumerated() { box.state = p.enabledChannels.contains(NotificationChannel.allCases[i]) ? .on : .off }
        threshold.selectItem(at: [10, 20, 30].firstIndex(of: p.lowRemainingThreshold) ?? 1)
        pause.title = (p.bubblePausedUntil.map { $0 > Date() } ?? false) ? copy.text("Resume bubbles", "恢复气泡", "恢復氣泡") : copy.text("Pause bubbles 1 hour", "暂停气泡1小时", "暫停氣泡1小時")
        mobileStatus.stringValue = router.bark?.configured == true ? copy.text("Configured", "已配置", "已設定") : copy.text("Not configured", "未配置", "未設定")
        if router.policyError { status.stringValue = copy.text("Reminder settings could not be read or saved. Check storage access.", "提醒设置读取或保存失败，请检查存储权限。", "提醒設定讀取或儲存失敗，請檢查儲存權限。") }
    }
    @objc private func ruleChanged(_ sender: NSButton) {
        let category = categories[sender.tag/3], channel = NotificationChannel.allCases[sender.tag%3]
        let enabled = sender.state == .on
        var p = router.policyPreferences; var selected = p.rules[category] ?? []
        if enabled { selected.insert(channel) } else { selected.remove(channel) }
        p.rules[category] = selected; let saved = router.configurePolicy(p); refresh()
        if saved && enabled && channel == .system { permission() }
    }
    @objc private func masterChanged(_ sender: NSButton) {
        let channel = NotificationChannel.allCases[sender.tag]
        let enabled = sender.state == .on
        let saved = router.setChannelEnabled(channel, enabled: enabled)
        if !saved { status.stringValue = copy.text("Could not enable this channel. Check its configuration or storage.", "无法启用该渠道，请检查配置或存储权限。", "無法啟用此管道，請檢查設定或儲存權限。") }
        refresh(); if saved && enabled && channel == .system { permission() }
    }
    private func permission() {
        guard router.policyPreferences.enabledChannels.contains(.system) else { return }
        permissionRevision += 1; let revision = permissionRevision
        router.requestPermission { [weak self] result in
            guard let self, permissionRevision == revision else { return }
            systemStatus.stringValue = result.isEmpty ? copy.text("Authorized", "已授权", "已授權") : copy.text("Not authorized", "未授权", "未授權")
        }
    }
    @objc private func thresholdChanged() { var p = router.policyPreferences; p.lowRemainingThreshold = [10, 20, 30][threshold.indexOfSelectedItem]; _ = router.configurePolicy(p); refresh() }
    @objc private func pauseTapped() { var p = router.policyPreferences; p.bubblePausedUntil = (p.bubblePausedUntil.map { $0 > Date() } ?? false) ? nil : Date().addingTimeInterval(3600); _ = router.configurePolicy(p); refresh() }
    @objc private func previewTapped() { preview() }
    @objc private func unreadTapped() { unread() }
}
