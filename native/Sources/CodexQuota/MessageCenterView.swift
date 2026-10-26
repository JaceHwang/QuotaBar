import AppKit
import QuotaCore

private final class MessageDetailDocument: NSView { override var isFlipped: Bool { true } }

@MainActor final class MessageCenterView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let router: AppNotificationRouter
    private let copy: ExperienceCopy
    private let dates = DateFormatter()
    private let logo = QuotaThemeIconView(frame: .zero)
    private let brand = NSTextField(labelWithString: "QuotaBar")
    private let heading = NSTextField(labelWithString: "")
    private let tabs = NSSegmentedControl(labels: ["", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let allRead = SettingsAccentButton(frame: .zero)
    private let back = SettingsAccentButton(frame: .zero)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let retry = SettingsAccentButton(frame: .zero)
    private let footer = NSTextField(wrappingLabelWithString: "")
    private let listScroll = NSScrollView()
    private let table = NSTableView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let detailScroll = NSScrollView()
    private let detail = MessageDetailDocument()
    private let divider = NSBox()
    private var detailParts: [NSView] = []
    private var renderedKey: MessageCenterKey?
    private var pendingDetailOrigin: NSPoint?
    private var rows: [MessageCenterRecord] = []
    private var observer: UUID?
    private var rendering = false
    private var showingDetail = false
    private(set) var selectedKey: MessageCenterKey?
    override var isFlipped: Bool { true }

    init(router: AppNotificationRouter, language: CodexDisplayLanguage) {
        self.router = router; copy = ExperienceCopy(language)
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        autoresizingMask = [.width, .height]
        dates.locale = Locale(identifier: language == .english ? "en_US" : language == .simplifiedChinese ? "zh_CN" : "zh_TW")
        dates.dateStyle = .medium; dates.timeStyle = .short
        heading.stringValue = copy.text("Messages", "消息提醒", "消息提醒"); heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.alignment = .center; brand.font = .systemFont(ofSize: 15, weight: .semibold)
        tabs.target = self; tabs.action = #selector(tabChanged); tabs.selectedSegment = 0; tabs.segmentStyle = .rounded
        tabs.identifier = .init("messages.tabs"); tabs.setAccessibilityLabel(copy.text("Message tabs", "消息页签", "消息頁籤"))
        configure(allRead, title: copy.text("Mark all read", "全部已读", "全部已讀"), id: "messages.allRead", action: #selector(allReadTapped))
        configure(back, title: copy.text("Back to list", "返回列表", "返回列表"), id: "messages.back", action: #selector(backTapped))
        configure(retry, title: copy.text("Retry saving", "重试本地存储", "重試本機儲存"), id: "messages.retry", action: #selector(retryTapped))
        errorLabel.identifier = .init("messages.storageError"); errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .systemRed; errorLabel.isSelectable = true
        footer.identifier = .init("messages.localStatus"); footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        let column = NSTableColumn(identifier: .init("message")); column.minWidth = 150; column.resizingMask = .autoresizingMask; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 84; table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self; table.delegate = self; table.allowsEmptySelection = true; table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.identifier = .init("messages.list")
        table.setAccessibilityLabel(copy.text("Messages", "消息列表", "消息列表"))
        listScroll.documentView = table; listScroll.hasVerticalScroller = true; listScroll.autohidesScrollers = true
        listScroll.identifier = .init("messages.listScroll"); listScroll.borderType = .lineBorder
        detailScroll.documentView = detail; detailScroll.hasVerticalScroller = true; detailScroll.autohidesScrollers = true
        detailScroll.identifier = .init("messages.detailScroll"); detailScroll.borderType = .lineBorder
        divider.boxType = .separator
        empty.font = .systemFont(ofSize: 13); empty.textColor = .secondaryLabelColor; empty.alignment = .center; empty.identifier = .init("messages.empty")
        for child in [logo, brand, heading, tabs, allRead, back, errorLabel, retry, listScroll, empty, detailScroll, divider, footer] { addSubview(child) }
        observer = router.observeMessages { [weak self] in self?.refresh() }
        refresh(); refreshColors()
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let observer { MainActor.assumeIsolated { router.removeMessageObserver(observer) } } }
    func detach() { if let observer { router.removeMessageObserver(observer); self.observer = nil } }
    private func configure(_ button: NSButton, title: String, id: String, action: Selector) {
        button.title = title; button.target = self; button.action = action; button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.identifier = .init(id); button.setAccessibilityLabel(title)
        // SettingsAccentButton requires its natural width and 30pt height. Match
        // those before attaching to this manually framed window to avoid mask conflicts.
        button.setFrameSize(button.intrinsicContentSize)
    }
    func refresh() {
        guard !rendering else { return }; rendering = true; defer { rendering = false }
        let history = router.messageHistory
        rows = tabs.selectedSegment == 0 ? history.filter { $0.readAtMilliseconds == nil } : history
        tabs.setLabel(copy.text("Unread", "未读提醒", "未讀提醒") + " (\(router.messageUnreadCount))", forSegment: 0)
        tabs.setLabel(copy.text("History", "历史消息", "歷史訊息"), forSegment: 1)
        for i in 0...1 { tabs.setWidth(max(130, ceil((tabs.label(forSegment: i)! as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width) + 30), forSegment: i) }
        table.reloadData()
        if let selectedKey, let index = rows.firstIndex(where: { $0.key == selectedKey }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        allRead.isEnabled = router.messageUnreadCount > 0 && router.messageStorageError == nil
        empty.stringValue = tabs.selectedSegment == 0 ? copy.text("No unread messages", "暂无未读提醒", "目前沒有未讀提醒") : copy.text("No message history yet", "暂无历史消息", "目前沒有歷史訊息")
        empty.isHidden = !rows.isEmpty
        let error = router.messageStorageError
        errorLabel.stringValue = error.map { copy.text("Local message storage is unavailable. Changes are not saved.\n", "消息本地存储异常，更改尚未保存。\n", "訊息本機儲存異常，變更尚未儲存。\n") + $0 } ?? ""
        errorLabel.isHidden = error == nil; retry.isHidden = error == nil
        footer.stringValue = error != nil || router.messageHasUnpersistedMessages ? copy.text("Unsaved messages are available for this run only. Retry local storage.", "未保存的消息仅本次可见，请重试本地存储。", "未儲存的訊息僅本次可見，請重試本機儲存。") : copy.text("Messages are saved on this device and remain after restart.", "消息保存在本机，重启后仍可查看。", "訊息儲存在本機，重新啟動後仍可查看。")
        renderDetail(); needsLayout = true
        layoutSubtreeIfNeeded()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("message.cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? MessageListCell ?? MessageListCell(frame: NSRect(x: 0, y: 0, width: max(150, tableView.bounds.width), height: tableView.rowHeight))
        cell.identifier = id; cell.render(rows[row], date: dates.string(from: rows[row].createdAt), unread: copy.text("Unread", "未读", "未讀"), read: copy.text("Read", "已读", "已讀")); return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rendering, rows.indices.contains(table.selectedRow) else { return }
        let record = rows[table.selectedRow]; selectedKey = record.key; showingDetail = true
        // Filtering this row out must not programmatically select/read its successor.
        _ = router.markMessageRead(record.key); refresh()
    }
    private func addDetail(_ text: String, size: CGFloat = 12, secondary: Bool = false, id: String? = nil) -> NSTextField {
        let label = QuotaSettingsStyle.label(text, size: size, secondary: secondary)
        if let id { label.identifier = .init(id) }
        detail.addSubview(label); detailParts.append(label)
        return label
    }
    private func renderDetail() {
        pendingDetailOrigin = renderedKey == selectedKey ? detailScroll.contentView.bounds.origin : .zero
        renderedKey = selectedKey
        detail.subviews.forEach { $0.removeFromSuperview() }; detailParts = []
        guard let key = selectedKey, let record = router.messageHistory.first(where: { $0.key == key }) else {
            _ = addDetail(copy.text("Select a message to read its details", "选择一条消息查看详情", "選擇一則訊息查看詳細內容"), size: 14, secondary: true); return
        }
        let title = addDetail(record.title, size: 20, id: "messages.detail.title"); title.font = .systemFont(ofSize: 20, weight: .semibold)
        _ = addDetail(dates.string(from: record.createdAt) + " · " + (record.readAtMilliseconds == nil ? copy.text("Unread", "未读", "未讀") : copy.text("Read", "已读", "已讀")), size: 11, secondary: true)
        if record.key.epoch != nil && record.key.epoch != router.currentMessageEpoch { _ = addDetail(copy.text("Earlier session · recorded quota snapshot", "历史会话 · 以下为当时的额度记录", "歷史工作階段 · 以下為當時的額度記錄"), size: 11, secondary: true) }
        let channels = NotificationChannel.allCases.filter { record.channels.contains($0) }.map { c in
            switch c { case .bubble: return copy.text("Bubble", "气泡通知", "氣泡通知"); case .system: return copy.text("System", "系统通知", "系統通知"); case .mobile: return copy.text("Mobile", "手机推送", "手機推播") }
        }.joined(separator: "  ·  ")
        _ = addDetail(copy.text("Configured channels: ", "提醒渠道：", "提醒管道：") + channels, size: 11, secondary: true)
        _ = addDetail(record.body, size: 14, id: "messages.detail.body")
        _ = addDetail(copy.text("This is the message as recorded at the time. View current quota for the latest status.", "以上为消息产生时的记录，最新状态请查看当前额度。", "以上為訊息產生時的記錄，最新狀態請查看目前額度。"), size: 11, secondary: true)
        if !router.isMessagePersisted(record.key) { _ = addDetail(copy.text("Not saved to disk yet", "尚未保存到磁盘", "尚未儲存至磁碟"), size: 11, secondary: true) }
        let latest = SettingsAccentButton(frame: .zero)
        configure(latest, title: record.category == .updateAvailable ? copy.text("View update", "查看更新", "查看更新") : copy.text("View current quota", "查看当前额度", "查看目前額度"), id: "messages.latest", action: #selector(latestTapped))
        latest.isEnabled = record.category == .updateAvailable ? router.openUpdates != nil : router.openDetails != nil
        let read = SettingsAccentButton(frame: .zero); configure(read, title: copy.text("Mark as read", "标为已读", "標為已讀"), id: "messages.markRead", action: #selector(readTapped))
        read.isEnabled = record.readAtMilliseconds == nil && router.messageStorageError == nil
        for button in [latest, read] { detail.addSubview(button); detailParts.append(button) }
    }
    @objc private func tabChanged() { showingDetail = false; refresh() }
    @objc private func allReadTapped() { _ = router.markAllMessagesRead(); refresh() }
    @objc private func backTapped() { showingDetail = false; needsLayout = true; layoutSubtreeIfNeeded() }
    @objc private func retryTapped() { _ = router.retryMessageStorage(); refresh() }
    @objc private func readTapped() { if let selectedKey { _ = router.markMessageRead(selectedKey) }; refresh() }
    @objc private func latestTapped() { if let selectedKey, let record = router.messageHistory.first(where: { $0.key == selectedKey }) { _ = router.openMessageLatest(record) } }
    override func layout() {
        let width = bounds.width, height = bounds.height, margin: CGFloat = 16
        logo.frame = NSRect(x: margin, y: 12, width: 28, height: 28); brand.frame = NSRect(x: 52, y: 15, width: 125, height: 24)
        brand.isHidden = width < 600; heading.frame = NSRect(x: width < 600 ? 58 : (width-240)/2, y: 13, width: width < 600 ? max(100,width-80) : 240, height: 28)
        let actionWidth = max(100, ceil(allRead.intrinsicContentSize.width))
        tabs.frame = NSRect(x: margin, y: 58, width: max(250, tabs.intrinsicContentSize.width), height: 30)
        allRead.frame = NSRect(x: width-margin-actionWidth, y: 58, width: actionWidth, height: 30)
        var top: CGFloat = 102
        if !errorLabel.isHidden {
            errorLabel.preferredMaxLayoutWidth = max(100,width-2*margin)
            let needed = errorLabel.cell?.cellSize(forBounds: NSRect(x: 0,y: 0,width: width-2*margin,height: 200)).height ?? 32
            let h = min(96,max(32,ceil(needed))); errorLabel.frame = NSRect(x:margin,y:top,width:width-2*margin,height:h)
            retry.frame = NSRect(x:margin,y:top+h+4,width:retry.intrinsicContentSize.width,height:30); top += h+46
        }
        let compact = width < 760, detailVisible = !compact || (showingDetail && selectedKey != nil)
        back.isHidden = !compact || !detailVisible
        if !back.isHidden { back.frame = NSRect(x:margin,y:top,width:back.intrinsicContentSize.width,height:30); top += 36 }
        let bodyHeight = max(50,height-top-48), bodyWidth = max(100,width-2*margin)
        let leftWidth = compact ? bodyWidth : min(340,max(280,bodyWidth*0.38))
        listScroll.isHidden = compact && detailVisible; detailScroll.isHidden = !detailVisible; divider.isHidden = compact
        listScroll.frame = NSRect(x:margin,y:top,width:leftWidth,height:bodyHeight)
        table.tableColumns.first?.width = max(100,listScroll.contentSize.width)
        let rightX = compact ? margin : margin+leftWidth+14
        detailScroll.frame = NSRect(x:rightX,y:top,width:compact ? bodyWidth : max(100,width-margin-rightX),height:bodyHeight)
        divider.frame = NSRect(x:margin+leftWidth+6,y:top,width:1,height:bodyHeight)
        empty.isHidden = !rows.isEmpty || listScroll.isHidden
        empty.frame = NSRect(x:margin+10,y:top+30,width:leftWidth-20,height:60)
        let documentWidth = max(100,detailScroll.contentSize.width), textWidth = max(64,documentWidth-36)
        var y: CGFloat = 18
        for part in detailParts {
            let h: CGFloat, w: CGFloat
            if let label = part as? NSTextField {
                label.preferredMaxLayoutWidth = textWidth
                h = max(18,ceil(label.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:textWidth,height:100000)).height ?? 18)); w = textWidth
            } else { h = 30; w = min(textWidth,ceil(part.intrinsicContentSize.width)) }
            part.frame = NSRect(x:18,y:y,width:w,height:h); y += h+12
        }
        detail.setFrameSize(NSSize(width:documentWidth,height:max(detailScroll.contentSize.height,y+6)))
        if let origin = pendingDetailOrigin {
            detailScroll.contentView.scroll(to:NSPoint(x:0,y:min(origin.y,max(0,detail.bounds.height-detailScroll.contentSize.height))))
            detailScroll.reflectScrolledClipView(detailScroll.contentView); pendingDetailOrigin = nil
        }
        footer.frame = NSRect(x:margin,y:max(top+bodyHeight+12,height-28),width:bodyWidth,height:22)
        super.layout()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
    private func refreshColors() {
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        table.backgroundColor = .controlBackgroundColor
    }
}

@MainActor private final class MessageListCell: NSTableCellView {
    private let dot = NSTextField(labelWithString: "●")
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let summary = NSTextField(labelWithString: "")
    private let stamp = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = 4
        for field in [name,summary,stamp] { field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 1; field.translatesAutoresizingMaskIntoConstraints = false; column.addArrangedSubview(field); field.widthAnchor.constraint(equalTo:column.widthAnchor).isActive = true }
        name.font = .systemFont(ofSize:13,weight:.semibold); summary.font = .systemFont(ofSize:11); summary.textColor = .secondaryLabelColor
        stamp.font = .systemFont(ofSize:10); stamp.textColor = .secondaryLabelColor; dot.font = .systemFont(ofSize:10); dot.textColor = .systemBlue
        let row = NSStackView(views:[dot,icon,column]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8; row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),row.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-10),row.topAnchor.constraint(equalTo:topAnchor,constant:10),row.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-10),dot.widthAnchor.constraint(equalToConstant:8),icon.widthAnchor.constraint(equalToConstant:22),icon.heightAnchor.constraint(equalToConstant:22)])
    }
    required init?(coder: NSCoder) { nil }
    func render(_ record: MessageCenterRecord, date: String, unread: String, read: String) {
        name.stringValue = record.title; summary.stringValue = record.body.replacingOccurrences(of:"\n",with:" "); stamp.stringValue = date
        dot.stringValue = record.readAtMilliseconds == nil ? "●" : ""; dot.setAccessibilityLabel(record.readAtMilliseconds == nil ? unread : read)
        let symbol: String
        switch record.category { case .quotaLow,.quotaExhausted: symbol = "exclamationmark.circle"; case .quotaRecovered: symbol = "arrow.clockwise.circle"; case .bankExpiring72h,.bankExpiring24h: symbol = "calendar.badge.clock"; case .updateAvailable: symbol = "arrow.up.circle" }
        icon.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil); icon.contentTintColor = .systemBlue
        setAccessibilityLabel((record.readAtMilliseconds == nil ? unread : read) + ": " + record.title + ", " + date)
    }
}
