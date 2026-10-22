import AppKit
import QuotaCore

@MainActor final class NotificationUnreadPanel: NSObject {
    private var window: NSPanel?
    private var callbacks: [Int: () -> Void] = [:]
    func show(router: AppNotificationRouter, language: CodexDisplayLanguage) {
        window?.close(); callbacks = [:]
        let copy = ExperienceCopy(language)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 460, height: 420), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = copy.text("Unread reminders · this run only", "未读提醒 · 仅本次运行", "未讀提醒 · 僅本次執行")
        panel.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: panel.contentView!.bounds); scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let items = router.unread
        if items.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: copy.text("No unread reminders", "暂无未读提醒", "目前沒有未讀提醒"))) }
        for (i, item) in items.enumerated() {
            let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = 6
            let title = NSTextField(labelWithString: item.message.title); title.font = .systemFont(ofSize: 13, weight: .semibold); column.addArrangedSubview(title)
            let formatter = DateFormatter(); formatter.timeStyle = .short
            column.addArrangedSubview(NSTextField(labelWithString: formatter.string(from: item.message.createdAt)))
            let body = item.stale ? copy.text("Earlier observation. View current quota for the latest status.", "此前观测的提醒，请查看最新额度状态。", "先前觀測的提醒，請查看最新額度狀態。") : item.message.body
            let text = NSTextField(wrappingLabelWithString: body); text.preferredMaxLayoutWidth = 400; text.widthAnchor.constraint(equalToConstant: 400).isActive = true; column.addArrangedSubview(text)
            let row = NSStackView(); row.spacing = 8
            for (offset, label) in [copy.text("View latest", "查看最新", "查看最新"), copy.text("Got it", "知道了", "知道了")].enumerated() {
                let key = i * 2 + offset; let button = NSButton(title: label, target: self, action: #selector(invoke(_:))); button.tag = key; button.bezelStyle = .rounded
                callbacks[key] = { [weak self, weak router] in
                    guard let self, let router else { return }
                    if offset == 0 { router.activateLatest(id: item.message.id) } else { router.dismiss(id: item.message.id, read: true) }
                    self.window?.close()
                }; row.addArrangedSubview(button)
            }
            column.addArrangedSubview(row); stack.addArrangedSubview(column)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = stack
        stack.widthAnchor.constraint(equalToConstant: 440).isActive = true
        panel.contentView?.addSubview(scroll); window = panel; panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func close() { window?.close(); window = nil; callbacks = [:] }
    @objc private func invoke(_ sender: NSButton) { callbacks[sender.tag]?() }
}
