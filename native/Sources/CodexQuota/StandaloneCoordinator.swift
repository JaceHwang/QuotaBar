import AppKit
import QuotaCore
import ServiceManagement
import Network
nonisolated(unsafe) private var standaloneSignalWriteFD: Int32 = -1

/// Owns only the application's status item and official runtime; never discovers host windows.
@MainActor
final class StandaloneCoordinator: NSObject, NSApplicationDelegate {
    private let detail = QuotaDetailPanel()
    private let floating = FloatingQuotaButton()
    private var detailFromFloating = false
    private var floatingInteraction = QuotaDetailInteractionState()
    private var floatingHoverTimer: Timer?
    private var statusItem: NSStatusItem?
    private var client: AppServerClient?
    private var tasks: [Task<Void, Never>] = []
    private var timer: Timer?
    private var state = StandaloneState()
    private var snapshot: AllowanceSnapshot?
    private var tokens: TokenUsageSnapshot?
    private var identity: AccountIdentity?
    private var updates: QuotaUpdateController?
    private var settings: NSWindow?
    private var statusLabel: NSTextField?
    private var showingDetail = false
    private var detailLocked = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var stopping = false
    private var requestInFlight = false
    private var sleeping = false
    private var lastRequest = Date.distantPast
    private var instanceLock: StandaloneInstanceLock?
    private var signalReadFD: Int32 = -1
    private var networkMonitor: NWPathMonitor?
    private var startupNotice: String?
    private let defaults = UserDefaults.standard
    private let statusDisplay = StatusItemDisplayPreferences()
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexUsageSidebar")

    init(updateController: QuotaUpdateController? = nil) { updates = updateController; super.init() }

    private var language: CodexDisplayLanguage {
        if let value = defaults.string(forKey: "standalone.language"), let language = CodexDisplayLanguage(rawValue: value) { return language }
        return CodexLanguageResolver.map(Locale.preferredLanguages.first ?? "en")
    }
    private func text(_ en: String, _ zh: String, _ tw: String? = nil) -> String {
        switch language {
        case .english: return en
        case .simplifiedChinese: return zh
        case .traditionalChinese: return tw ?? zh
        }
    }
    private var theme: CodexInterfaceTheme {
        let value = defaults.string(forKey: "standalone.theme") ?? "system"
        if value == "dark" { return .dark }
        if value == "light" { return .light }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    func applicationDidFinishLaunching(_ notification: Notification) { start() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func start() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do { instanceLock = try StandaloneInstanceLock(url: root.appendingPathComponent("standalone.lock")) }
        catch { NSApp.terminate(nil); return }
        // The signal handler uses only async-signal-safe write; AppKit shutdown runs on the timer.
        if signalReadFD < 0 {
            var descriptors: [Int32] = [-1, -1]
            guard pipe(&descriptors) == 0 else { NSApp.terminate(nil); return }
            signalReadFD = descriptors[0]; standaloneSignalWriteFD = descriptors[1]
            _ = fcntl(signalReadFD, F_SETFL, O_NONBLOCK)
            _ = fcntl(standaloneSignalWriteFD, F_SETFL, O_NONBLOCK)
            _ = fcntl(signalReadFD, F_SETFD, FD_CLOEXEC)
            _ = fcntl(standaloneSignalWriteFD, F_SETFD, FD_CLOEXEC)
        }
        signal(SIGTERM) { _ in
            var byte: UInt8 = 1
            _ = Darwin.write(standaloneSignalWriteFD, &byte, 1)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let detailsItem = NSMenuItem(title: text("Quota details", "额度详情", "額度詳情"), action: #selector(statusDetailsClicked), keyEquivalent: "d")
        detailsItem.target = self; appMenu.addItem(detailsItem)
        let preferences = NSMenuItem(title: text("Settings…", "设置…", "設定…"), action: #selector(settingsClicked), keyEquivalent: ",")
        preferences.target = self; appMenu.addItem(preferences)
        let updateItem = NSMenuItem(title: text("Check for Updates…", "检查更新…", "檢查更新…"), action: #selector(checkUpdates), keyEquivalent: "")
        updateItem.target = self; appMenu.addItem(updateItem)
        let quitItem = NSMenuItem(title: text("Quit QuotaBar", "退出 QuotaBar", "結束 QuotaBar"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem); appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        detail.onOpenURL = { NSWorkspace.shared.open($0) }
        detail.onSettingsButtonTapped = { [weak self] _ in self?.showSettings() }
        floating.onClick = { [weak self] in
            guard let self else { return }
            guard snapshot != nil else { showSettings(); return }
            detailFromFloating = true; showingDetail = false; detailLocked = false
            floatingInteraction.togglePinned(pointerInside: true)
            render(); refresh()
        }
        floating.onMenu = { [weak self] in self?.showFloatingMenu() }
        floating.onMove = { [weak self] in self?.render() }
        floating.onClose = { [weak self] in self?.setFloatingEnabled(false) }
        floating.onHover = { [weak self] entered in self?.floatingHoverChanged(entered) }
        detail.onLockOpenToggle = { [weak self] in
            guard let self else { return }
            if detailFromFloating { floatingInteraction.toggleLockedOpen(pointerInside: true); floatingHoverChanged(true) }
            else { detailLocked.toggle() }
            render()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissOutsideClick(); return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissOutsideClick() }
        }
        if updates == nil {
            updates = QuotaUpdateController(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0") { [weak self] en, zh, tw in self?.text(en, zh, tw) ?? en }
        }
        render()
        let refreshTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
        let runtime = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codex")
        guard FileManager.default.isExecutableFile(atPath: runtime.path) else {
            state.receiveError(method: "initialize", message: "Method not found")
            render(); showSettings(); return
        }
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("CodexHome"), withIntermediateDirectories: true)
        let client = AppServerClient(executableURL: runtime, environmentOverrides: ["CODEX_HOME": root.appendingPathComponent("CodexHome").path])
        self.client = client
        // A single ordered event stream prevents stale cross-stream data restoring a logged-out account.
        tasks.append(Task { [weak self] in
            for await event in client.events { self?.receive(event) }
        })
        tasks.append(Task { [weak self] in
            do { try await client.start(); try await client.readAccount() }
            catch { self?.state.receiveError(method: "initialize", message: "Runtime unavailable"); self?.render() }
        })
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                if self?.state.phase == .offline { self?.refresh() }; self?.updates?.check()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.jace.codex-quota.network"))
        networkMonitor = monitor
    }

    private func receive(_ event: AppServerEvent) {
        switch event {
        case .failure(let method, let message):
            state.receiveError(method: method, message: message)
            if method == "account/login/start" { state.loginCompleted(success: false) }
            if method == "account/rateLimits/read" { requestInFlight = false }
        case .loginURL(let url): NSWorkspace.shared.open(url)
        case .loginCompleted(let success): state.loginCompleted(success: success)
        case .loggedOut:
            snapshot = nil; tokens = nil; identity = nil
            state.loginCompleted(success: false)
        case .accountCleared:
            snapshot = nil; tokens = nil; identity = nil; requestInFlight = false
        case .quota(let value):
            snapshot = value; state.receivedQuota(at: Date()); requestInFlight = false
        case .tokenUsage(let value): tokens = value
        case .identity(let value): identity = value
        }
        render()
        if state.phase == .needsLogin && settings == nil { showSettings() }
    }

    private func tick() {
        var signalByte: UInt8 = 0
        if signalReadFD >= 0 && Darwin.read(signalReadFD, &signalByte, 1) > 0 { NSApp.terminate(nil); return }
        guard !stopping, !sleeping else { return }
        if let client { Task { await client.expireRequests(before: Date().addingTimeInterval(-20)) } }
        if requestInFlight && Date().timeIntervalSince(lastRequest) > 20 {
            requestInFlight = false
            state.receiveError(method: "account/rateLimits/read", message: "Request timeout")
        }
        if state.shouldRefresh(at: Date()) { refresh() }
        render()
    }
    private func refresh() {
        guard state.phase != .needsLogin, state.phase != .signingIn else { return }
        guard !requestInFlight, let client else { return }
        requestInFlight = true; lastRequest = Date()
        Task { [weak self] in
            do {
                try await client.refresh()
                if self?.identity == nil { try await client.readAccount() }
            }
            catch {
                self?.requestInFlight = false
                self?.state.receiveError(method: "account/rateLimits/read", message: "Runtime transport unavailable")
                self?.render()
            }
        }
    }
    @objc private func wake() { sleeping = false; refresh(); updates?.check() }
    @objc private func sleep() { sleeping = true }
    private func dismissOutsideClick() {
        guard showingDetail || floatingInteraction.shouldShowDetail, !(detailFromFloating ? floatingInteraction.isLockedOpen : detailLocked) else { return }
        let point = NSEvent.mouseLocation
        if detail.frame?.contains(point) == true || floating.frame?.contains(point) == true || statusItem?.button?.window?.frame.contains(point) == true { return }
        showingDetail = false; floatingInteraction.dismissForOutsideInteraction(); render()
    }
    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        statusDetailsClicked()
    }
    @objc private func statusDetailsClicked() {
        detailFromFloating = false; floatingInteraction.reset()
        floatingHoverTimer?.invalidate(); floatingHoverTimer = nil
        detailsClicked()
    }
    private func detailsClicked() {
        if snapshot == nil { showSettings(); return }
        showingDetail.toggle(); render()
        if showingDetail { refresh() }
    }
    private var phaseText: String {
        switch state.phase {
        case .loading: return text("Loading quota…", "正在加载额度…", "正在載入額度…")
        case .ready: return text("Quota is up to date", "额度已更新", "額度已更新")
        case .offline: return text("Offline or request failed; retrying", "离线或请求失败，正在重试", "離線或請求失敗，正在重試")
        case .needsLogin: return text("Sign in again to read quota", "请重新登录以读取额度", "請重新登入以讀取額度")
        case .signingIn: return text("Complete sign-in in your browser", "请在浏览器完成登录", "請在瀏覽器完成登入")
        case .unsupported: return text("Runtime missing or protocol unsupported", "运行时缺失或协议不支持", "執行環境缺失或協議不支援")
        }
    }
    private func render() {
        if let menu = NSApp.mainMenu?.items.first?.submenu, menu.items.count == 3 {
            menu.items[0].title = text("Quota details", "额度详情", "額度詳情")
            menu.items[1].title = text("Settings…", "设置…", "設定…")
            menu.items[2].title = text("Quit QuotaBar", "退出 QuotaBar", "結束 QuotaBar")
        }
        switch defaults.string(forKey: "standalone.theme") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
        let isStale = state.lastSuccess.map { Date().timeIntervalSince($0) > 120 } ?? false
        let indicatorText = snapshot.map {
            let summary = ResetFormatter().indicatorSummary(
                snapshot: $0, language: language, timeZone: .autoupdatingCurrent,
                maxWidth: 236
            )
            return [summary.primary, summary.secondary].compactMap { $0 }.joined(separator: "\n")
                + (isStale || state.phase != .ready ? " !" : "")
        } ?? "◉ —"
        let image = QuotaStatusItemImage.make(showQuotaInformation: statusDisplay.showsQuotaInformation, text: indicatorText, theme: theme)
        statusItem?.button?.attributedTitle = NSAttributedString(string: "")
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.imageScaling = .scaleNone
        statusItem?.button?.image = image
        let freshness = isStale ? text("Last data is stale", "上次数据已过期", "上次資料已過期") : phaseText
        let updated = state.lastSuccess.map { text("Updated: ", "更新时间：", "更新時間：") + DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? ""
        statusItem?.button?.toolTip = freshness + "\n" + updated
        statusItem?.button?.setAccessibilityLabel(text("Codex remaining quota", "Codex 剩余额度", "Codex 剩餘額度") + "\n" + indicatorText)
        statusLabel?.stringValue = freshness + "\n" + (identity?.preferredName ?? text("No account", "暂无账户", "尚無帳號")) + "\n" + updated + (startupNotice.map { "\n" + $0 } ?? "")
        floating.show(summary: snapshot.map { ResetFormatter().indicatorSummary(snapshot: $0, language: language, timeZone: .autoupdatingCurrent, maxWidth: 236) }, theme: theme, tooltip: freshness + "\n" + updated, fallback: phaseText, dimmed: isStale || state.phase != .ready)
        let statusAnchor = statusItem?.button.flatMap { button in button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } }
        let anchor = detailFromFloating ? (floating.frame ?? statusAnchor) : statusAnchor
        if showingDetail || floatingInteraction.shouldShowDetail, let snapshot, let anchor {
            detail.show(content: QuotaDetailFormatter().content(snapshot: snapshot, tokenUsage: tokens, footerName: identity?.preferredName, footerAvatarURL: identity?.avatarURL, now: Date(), language: language, timeZone: .current), relativeTo: anchor, theme: theme, isLockedOpen: detailFromFloating ? floatingInteraction.isLockedOpen : detailLocked)
        } else { detail.hide() }
        let detailVisible = detail.frame != nil
        let detailFits = detail.frame.map { frame in NSScreen.screens.contains { $0.visibleFrame.contains(frame) } } ?? false
        let diagnostic = "pid=\(ProcessInfo.processInfo.processIdentifier) mode=standalone phase=\(state.phase.rawValue) has_quota=\(snapshot != nil) host_ui=false status_quota=\(statusDisplay.showsQuotaInformation) floating_visible=\(floating.frame != nil) floating_enabled=\(floating.preferences.enabled) detail_visible=\(detailVisible) detail_fits_screen=\(detailFits)\n"
        try? diagnostic.write(to: root.appendingPathComponent("standalone-state.txt"), atomically: true, encoding: .utf8)
    }
    private func showMenu() {
        let menu = NSMenu()
        for (title, action) in [(text("Quota details", "额度详情", "額度詳情"), #selector(clicked)), (text("Refresh", "刷新", "重新整理"), #selector(refreshClicked)), (text("Check for Updates…", "检查更新…", "檢查更新…"), #selector(checkUpdates)), (text("Settings…", "设置…", "設定…"), #selector(settingsClicked)), (text("Quit", "退出", "結束"), #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        let floatingToggle = NSMenuItem(title: text("Show floating button", "显示悬浮按钮", "顯示懸浮按鈕"), action: #selector(floatingChanged), keyEquivalent: "")
        floatingToggle.target = self; floatingToggle.state = floating.preferences.enabled ? .on : .off
        menu.insertItem(floatingToggle, at: 2)
        statusItem?.menu = menu; statusItem?.button?.performClick(nil); statusItem?.menu = nil
    }
    @objc private func refreshClicked() { refresh() }
    @objc private func checkUpdates() { showSettings(); updates?.check(manual: true) }
    @objc private func settingsClicked() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func loginClicked() {
        guard let client else { return }
        Task { [weak self] in
            do { try await client.login(); self?.state.beginLogin(); self?.render() }
            catch { self?.state.loginCompleted(success: false); self?.render() }
        }
    }
    @objc private func cancelClicked() { if let client { Task { try? await client.cancelLogin() } } }
    @objc private func logoutClicked() { if let client { Task { try? await client.logout() } } }
    @objc private func reloadClicked() {
        Task { [weak self] in
            guard let self else { return }
            timer?.invalidate(); floating.hide(); floatingInteraction.reset(); floatingHoverTimer?.invalidate(); floatingHoverTimer = nil
            networkMonitor?.cancel(); networkMonitor = nil
            for task in tasks { task.cancel() }
            tasks.removeAll()
            if let client { await client.stop() }
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            removeMouseMonitors()
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil; instanceLock = nil; client = nil
            state = StandaloneState(); requestInFlight = false
            start()
        }
    }

    private func showSettings() {
        if let settings { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = makeSettingsWindow()
        settings = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); render()
    }
    func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = text("QuotaBar — Settings", "QuotaBar — 设置", "QuotaBar — 設定")
        window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        let label = NSTextField(wrappingLabelWithString: phaseText); statusLabel = label; stack.addArrangedSubview(label)
        let buttons = NSStackView(); buttons.spacing = 8
        for (title, selector) in [(text("Sign in", "登录", "登入"), #selector(loginClicked)), (text("Cancel", "取消"), #selector(cancelClicked)), (text("Sign out", "退出账号", "登出"), #selector(logoutClicked)), (text("Refresh", "刷新", "重新整理"), #selector(refreshClicked))] {
            buttons.addArrangedSubview(NSButton(title: title, target: self, action: selector))
        }
        stack.addArrangedSubview(buttons)
        let actions = NSStackView(); actions.spacing = 8
        actions.addArrangedSubview(NSButton(title: text("Quota details", "额度详情", "額度詳情"), target: self, action: #selector(statusDetailsClicked)))
        actions.addArrangedSubview(NSButton(title: text("Reload runtime", "重新加载运行时", "重新載入執行環境"), target: self, action: #selector(reloadClicked)))
        stack.addArrangedSubview(actions)
        let theme = NSPopUpButton(); theme.addItems(withTitles: [text("System theme", "跟随系统主题", "跟隨系統主題"), text("Light", "浅色", "淺色"), text("Dark", "深色")]); theme.target = self; theme.action = #selector(themeChanged)
        theme.selectItem(at: ["system", "light", "dark"].firstIndex(of: defaults.string(forKey: "standalone.theme") ?? "system") ?? 0); stack.addArrangedSubview(theme)
        let language = NSPopUpButton(); language.addItems(withTitles: [text("System language", "跟随系统语言", "跟隨系統語言"), "简体中文", "繁體中文", "English"]); language.target = self; language.action = #selector(languageChanged)
        language.selectItem(at: ["system", "simplifiedChinese", "traditionalChinese", "english"].firstIndex(of: defaults.string(forKey: "standalone.language") ?? "system") ?? 0); stack.addArrangedSubview(language)
        let quotaToggle = NSButton(checkboxWithTitle: text("Show quota information in menu bar", "任务栏显示额度信息", "工作列顯示額度資訊"), target: self, action: #selector(statusDisplayChanged))
        quotaToggle.state = statusDisplay.showsQuotaInformation ? .on : .off
        stack.addArrangedSubview(quotaToggle)
        let startup = NSButton(checkboxWithTitle: text("Launch at login", "登录时启动", "登入時啟動"), target: self, action: #selector(startupChanged)); startup.state = SMAppService.mainApp.status == .enabled ? .on : .off; stack.addArrangedSubview(startup)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: text("Quota is read by the bundled official runtime. Account credentials stay in the isolated local account directory.", "通过内嵌官方运行时读取额度，凭据保存在本机隔离账户目录。", "透過內嵌官方執行環境讀取額度，憑證儲存在本機隔離帳號目錄。")))
        if let updates {
            let updateView = updates.makeSettingsView(); stack.addArrangedSubview(updateView)
            updateView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let document = QuotaSettingsDocumentView(frame: NSRect(x: 0, y: 0, width: 510, height: 730))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        document.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24)])
        stack.layoutSubtreeIfNeeded()
        document.setFrameSize(NSSize(width: 510, height: max(430, ceil(stack.fittingSize.height) + 48)))
        window.setContentSize(NSSize(width: 510, height: min(document.frame.height, (NSScreen.main?.visibleFrame.height ?? 800) - 80)))
        scroll.frame = window.contentView!.bounds; scroll.autoresizingMask = [.width, .height]; scroll.documentView = document
        window.contentView?.addSubview(scroll)
        updates?.onChange = { [weak stack, weak document, weak window] in
            guard let stack, let document, let window else { return }
            stack.layoutSubtreeIfNeeded()
            let height = max(430, ceil(stack.fittingSize.height) + 48)
            document.setFrameSize(NSSize(width: 510, height: height))
            window.setContentSize(NSSize(width: 510, height: min(height, (NSScreen.main?.visibleFrame.height ?? 800) - 80)))
        }
        return window
    }
    @objc private func statusDisplayChanged(_ sender: NSButton) {
        statusDisplay.showsQuotaInformation = sender.state == .on; render()
    }
    @objc private func floatingChanged(_ sender: NSMenuItem) {
        setFloatingEnabled(!floating.preferences.enabled)
        sender.state = floating.preferences.enabled ? .on : .off
    }
    private func setFloatingEnabled(_ enabled: Bool) {
        floating.preferences.enabled = enabled
        if !enabled {
            floating.hide(); floatingInteraction.reset(); floatingHoverTimer?.invalidate(); floatingHoverTimer = nil
            if detailFromFloating { showingDetail = false; detailLocked = false }
        }
        render()
    }
    private func floatingHoverChanged(_ entered: Bool) {
        guard entered, !showingDetail else { return }
        floatingInteraction.updatePointerInside(true); detailFromFloating = true; render()
        floatingHoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFloatingHover() }
        }
        floatingHoverTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func updateFloatingHover() {
        let point = NSEvent.mouseLocation
        let inside = floating.frame?.contains(point) == true || (detailFromFloating && detail.frame?.contains(point) == true)
        let previous = floatingInteraction
        floatingInteraction.updatePointerInside(inside)
        if !inside { floatingHoverTimer?.invalidate(); floatingHoverTimer = nil }
        if previous != floatingInteraction { render() }
    }
    private func showFloatingMenu() {
        let menu = NSMenu()
        for (title, action) in [(text("Refresh", "刷新", "重新整理"), #selector(refreshClicked)), (text("Check for Updates…", "检查更新…", "檢查更新…"), #selector(checkUpdates)), (text("Settings…", "设置…", "設定…"), #selector(settingsClicked)), (text("Quit", "退出", "結束"), #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        floating.showMenu(menu)
    }
    @objc private func themeChanged(_ sender: NSPopUpButton) { defaults.set(["system", "light", "dark"][sender.indexOfSelectedItem], forKey: "standalone.theme"); render() }
    @objc private func languageChanged(_ sender: NSPopUpButton) { defaults.set(["system", "simplifiedChinese", "traditionalChinese", "english"][sender.indexOfSelectedItem], forKey: "standalone.language"); settings?.close(); settings = nil; showSettings(); render() }
    @objc private func startupChanged(_ sender: NSButton) {
        startupNotice = nil
        do { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { startupNotice = text("Unable to change login item; check System Settings", "无法更改登录启动，请检查系统设置", "無法更改登入項目，請檢查系統設定") }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { startupNotice = text("Approve the login item in System Settings", "请在系统设置批准登录启动项", "請在系統設定核准登入項目") }
        render()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !stopping else { return .terminateNow }
        updates?.stop()
        stopping = true; timer?.invalidate(); floatingHoverTimer?.invalidate(); floating.hide(); detail.hide(); statusItem = nil
        networkMonitor?.cancel(); networkMonitor = nil
        removeMouseMonitors()
        for task in tasks { task.cancel() }
        Task { if let client { await client.stop() }; sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func removeMouseMonitors() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil; globalMouseMonitor = nil
    }
}

@MainActor
final class QuotaSettingsDocumentView: NSView { override var isFlipped: Bool { true } }
