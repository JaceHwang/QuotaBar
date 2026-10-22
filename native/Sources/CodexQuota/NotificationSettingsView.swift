import AppKit
import QuotaCore

@MainActor final class NotificationSettingsView: NSStackView {
    private let router: AppNotificationRouter
    private let copy: ExperienceCopy
    private let preview: () -> Void
    private let showUnread: () -> Void
    private let enableFloating: () -> Void
    private let pause = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    init(router: AppNotificationRouter, language: CodexDisplayLanguage, floatingVisible: Bool, preview: @escaping () -> Void, showUnread: @escaping () -> Void, enableFloating: @escaping () -> Void) {
        self.router = router; copy = ExperienceCopy(language); self.preview = preview; self.showUnread = showUnread; self.enableFloating = enableFloating
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 10
        let picker = NSPopUpButton(); picker.addItems(withTitles: [copy.text("Floating bubble", "悬浮气泡", "懸浮氣泡"), copy.text("System notification", "系统通知", "系統通知"), copy.text("Both", "两者", "兩者"), copy.text("Off", "关闭", "關閉")]); picker.selectItem(at: NotificationDeliveryMode.allCases.firstIndex(of: router.preferences.mode) ?? 0)
        picker.target = self; picker.action = #selector(channelChanged(_:)); picker.identifier = .init("notification.channel"); picker.setAccessibilityLabel(copy.text("Reminder display", "提醒展示方式", "提醒顯示方式"))
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(copy.text("Reminder display", "提醒展示方式", "提醒顯示方式"), control: picker), in: self)
        pause.bezelStyle = .rounded; pause.target = self; pause.action = #selector(pauseTapped); pause.identifier = .init("notification.pause"); updatePause()
        let actions = NSStackView(); actions.spacing = 8
        actions.addArrangedSubview(pause)
        actions.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Preview bubble", "预览气泡", "預覽氣泡"), target: self, action: #selector(previewTapped)))
        actions.addArrangedSubview(QuotaSettingsStyle.button(copy.text("Unread reminders", "未读提醒", "未讀提醒"), target: self, action: #selector(unreadTapped)))
        addArrangedSubview(actions)
        let note = copy.text("Bubbles stay quiet while hidden or locked. Unread reminders are kept for this run only. System Focus does not automatically mute bubbles; use Pause.", "浮窗隐藏或锁屏时不冒泡；未读仅保留本次运行。气泡不自动继承系统免打扰，可使用暂停。", "浮窗隱藏或鎖定時不冒泡；未讀僅保留本次執行。氣泡不自動繼承系統勿擾，可使用暫停。")
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(note, size: 11, secondary: true), in: self)
        if !floatingVisible {
            addArrangedSubview(QuotaSettingsStyle.label(copy.text("Enable the floating button to preview a bubble.", "开启悬浮按钮后可预览气泡。", "開啟懸浮按鈕後可預覽氣泡。"), size: 11, secondary: true))
            addArrangedSubview(QuotaSettingsStyle.button(copy.text("Enable floating button", "开启悬浮按钮", "開啟懸浮按鈕"), target: self, action: #selector(enableTapped)))
        }
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; QuotaSettingsStyle.fill(status, in: self)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func channelChanged(_ sender: NSPopUpButton) {
        var value = router.preferences; value.mode = NotificationDeliveryMode.allCases[sender.indexOfSelectedItem]; router.configure(value)
        router.requestPermission { [weak self] result in
            guard let self else { return }
            status.stringValue = result.isEmpty ? "" : copy.text("System notifications unavailable. Bubbles do not require permission.", "系统通知不可用；气泡不需要通知权限。", "系統通知無法使用；氣泡不需要通知權限。")
        }
    }
    @objc private func pauseTapped() {
        var value = router.preferences; value.pausedUntil = value.paused(now: Date()) ? nil : Date().addingTimeInterval(3600); router.configure(value); updatePause()
    }
    private func updatePause() { pause.title = router.preferences.paused(now: Date()) ? copy.text("Resume bubbles", "恢复气泡", "恢復氣泡") : copy.text("Pause for 1 hour", "暂停气泡 1 小时", "暫停氣泡 1 小時") }
    @objc private func previewTapped() { preview() }
    @objc private func unreadTapped() { showUnread() }
    @objc private func enableTapped() { enableFloating() }
}
