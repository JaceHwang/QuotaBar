import AppKit
import QuotaCore
import ServiceManagement
import Network
nonisolated(unsafe) private var standaloneSignalWriteFD: Int32 = -1

/// Owns only the application's status item and official runtime; never discovers host windows.
@MainActor
final class StandaloneCoordinator: NSObject, NSApplicationDelegate {
    private let detail = QuotaDetailPanel()
    private let notificationBubble = CharacterNotificationBubble()
    private let messagePanel = MessageCenterPanel()
    private var notificationDragging = false
    private var screenLocked = false
    private let floating: FloatingQuotaButton
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
    private var experience: QuotaExperienceController?
    private var updates: QuotaUpdateController?
    private var bark: BarkNotificationController?
    private var settings: NSWindow?
    private var statusLabel: NSTextField?
    private weak var accountIdentityLabel: NSTextField?
    private weak var accountPlanLabel: NSTextField?
    private var accountActions: [NSButton] = []
    private weak var troubleshooting: NSView?
    private weak var settingsShell: QuotaSettingsShellView?
    private var showingDetail = false
    private var floatingMenuVisible = false
    private var menuRequiresPointerExit = false
    private var settingsPage = 2
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
    private let defaults: UserDefaults
    private let statusDisplay: StatusItemDisplayPreferences
    private let root: URL

    init(updateController: QuotaUpdateController? = nil, experienceController: QuotaExperienceController? = nil, barkController: BarkNotificationController? = nil, defaults: UserDefaults = .standard, root: URL? = nil) {
        self.defaults = defaults; self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsageSidebar")
        floating = FloatingQuotaButton(preferences: FloatingQuotaPreferences(defaults: defaults)); statusDisplay = StatusItemDisplayPreferences(defaults: defaults)
        updates = updateController; experience = experienceController; bark = barkController; super.init()
    }

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
        floating.onDragStarted = { [weak self] in self?.notificationDragging = true; AppNotificationRouter.shared.updateEnvironment(canPresent: false) }
        floating.onDragFinished = { [weak self] in self?.notificationDragging = false; self?.render() }
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
        let notificationRouter = AppNotificationRouter.shared
        if notificationRouter.messageStore == nil { notificationRouter.bindMessageCenter(MessageCenterStore(url: root.appendingPathComponent("message-center.json"))) }
        let hasLegacySettings = ["notifications.presentation", "experience.preferences", "bark.preferences", "updates.reminders"].contains { defaults.object(forKey: $0) != nil } || FileManager.default.fileExists(atPath: root.appendingPathComponent("experience-state.json").path)
        let legacyExperience = defaults.data(forKey: "experience.preferences").flatMap { try? JSONDecoder().decode(QuotaExperiencePreferences.self, from: $0) } ?? QuotaExperiencePreferences()
        let legacyPresentation = notificationRouter.preferences
        let legacyBark = defaults.data(forKey: "bark.preferences").flatMap { try? JSONDecoder().decode(BarkPreferences.self, from: $0) } ?? BarkPreferences()
        notificationRouter.loadPolicy(store: NotificationPolicyStore(url: root.appendingPathComponent("notification-policy.json")), legacy: hasLegacySettings ? LegacyNotificationPreferences(mode: legacyPresentation.mode, recovery: legacyExperience.recovery, celebration: legacyExperience.celebration, bank: legacyExperience.bank, updatesReminders: defaults.bool(forKey: "updates.reminders"), barkEnabled: legacyBark.enabled, pausedUntil: legacyPresentation.pausedUntil) : nil)
        if updates == nil {
            updates = QuotaUpdateController(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0") { [weak self] en, zh, tw in self?.text(en, zh, tw) ?? en }
        }
        if experience == nil {
            let experience = QuotaExperienceController(root: root, language: { [weak self] in self?.language ?? .english })
            self.experience = experience
            experience.onCelebrate = { [weak self] in self?.floating.celebrate() }
            experience.onCancelCelebration = { [weak self] in self?.floating.cancelCelebration() }
            experience.onChange = { [weak self] in self?.render() }
            experience.floatingVisible = { [weak self] in self?.floating.frame != nil }
            experience.onShowUnread = { [weak self] in self?.showUnreadReminders() }
            experience.onEnableFloating = { [weak self] in self?.setFloatingEnabled(true); self?.settings?.close(); self?.settings = nil; self?.showSettings() }
        }
        AppNotificationRouter.shared.openDetails = { [weak self] in
            guard let self else { return }
            if snapshot == nil { showSettings() } else { detailFromFloating = false; showingDetail = true; render(); refresh() }
        }
        let router = AppNotificationRouter.shared
        router.openUpdates = { [weak self] in self?.showSettings(); (self?.settings?.contentView as? QuotaSettingsShellView)?.selectPage(4) }
        // LaunchServices' isolated-home smoke host must never open the login Keychain.
        if bark == nil, ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] == nil {
            bark = BarkNotificationController(defaults: defaults, secrets: KeychainBarkSecretStore(), transport: BarkPushClient(), deliveries: BarkDeliveryStore(url: root.appendingPathComponent("bark-deliveries.json")))
        }
        router.bark = bark
        bark?.onConfigurationChange = { [weak self] in
            guard let self else { return }
            bark?.suppress(updates?.currentMobileIdentities ?? [], valid: { [weak self] identity in self?.updates?.currentMobileIdentities.contains(identity) == true })
        }
        router.openBank = { [weak self] in router.openDetails?(); self?.detail.focusBank() }
        router.presentBubble = { [weak self] message in
            guard let self, let anchor = floating.frame, floating.isOnActiveSpace else { return false }
            return notificationBubble.show(message: message, anchor: anchor, dark: theme == .dark, language: language)
        }
        router.hideBubble = { [weak self] in self?.notificationBubble.dismiss() }
        router.onUnreadChange = { [weak self] in self?.floating.hasUnread = AppNotificationRouter.shared.messageUnreadCount > 0 }
        notificationBubble.onAction = { router.activate(id: $0, token: $1) }
        notificationBubble.onAcknowledge = { router.dismiss(id: $0, read: true, token: $1) }
        notificationBubble.onInteractionChanged = { router.setInteracting($0) }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(notificationScreenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(notificationScreenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(notificationSpaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(notificationSpaceChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            let unread = NSMenuItem(title: text("Messages", "消息提醒", "消息提醒"), action: #selector(showUnreadReminders), keyEquivalent: "u"); unread.target = self; appMenu.insertItem(unread, at: 1)
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

    func receive(_ event: AppServerEvent) {
        switch event {
        case .failure(let method, let message):
            state.receiveError(method: method, message: message)
            if state.phase != .ready { experience?.resetBaseline() }
            if method == "account/login/start" { state.loginCompleted(success: false) }
            if method == "account/rateLimits/read" { requestInFlight = false }
        case .loginURL(let url): NSWorkspace.shared.open(url)
        case .loginCompleted(let success): state.loginCompleted(success: success)
        case .loggedOut:
            snapshot = nil; tokens = nil; identity = nil
            state.loginCompleted(success: false)
        case .accountCleared:
            experience?.accountCleared()
            snapshot = nil; tokens = nil; identity = nil; requestInFlight = false
        case .quotaRead(let raw, let bank): experience?.receive(raw, bank: bank)
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
    @objc private func sleep() { sleeping = true; experience?.resetBaseline(); AppNotificationRouter.shared.updateEnvironment(canPresent: false) }
    @objc private func notificationScreenLocked() { screenLocked = true; AppNotificationRouter.shared.updateEnvironment(canPresent: false) }
    @objc private func notificationScreenUnlocked() { screenLocked = false; render() }
    @objc private func notificationSpaceChanged() { AppNotificationRouter.shared.suspend(); render() }
    @objc private func showUnreadReminders() { AppNotificationRouter.shared.suspend(); messagePanel.show(router: .shared, language: language) }
    private func dismissOutsideClick() {
        if notificationBubble.contains(NSEvent.mouseLocation) { return }
        if notificationBubble.isVisible { AppNotificationRouter.shared.suspend() }
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
        statusLabel?.stringValue = freshness + "\n" + updated + (startupNotice.map { "\n" + $0 } ?? "")
        updateAccountSettings()
        synchronizeSettingsControls()
        updates?.onChange?()
        floating.setExperience(mood: QuotaMood.resolve(snapshot, ready: state.phase == .ready, now: Date()), enabled: experience?.preferences.moods == true, description: ExperienceCopy(language).moodLabel(QuotaMood.resolve(snapshot, ready: state.phase == .ready, now: Date())))
        floating.show(summary: snapshot.map { ResetFormatter().indicatorSummary(snapshot: $0, language: language, timeZone: .autoupdatingCurrent, maxWidth: 236) }, theme: theme, tooltip: freshness + "\n" + updated, fallback: phaseText, dimmed: isStale || state.phase != .ready)
        let statusAnchor = statusItem?.button.flatMap { button in button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } }
        let anchor = detailFromFloating ? (floating.frame ?? statusAnchor) : statusAnchor
        if showingDetail || floatingInteraction.shouldShowDetail, let snapshot, let anchor {
            detail.show(content: QuotaDetailFormatter().content(snapshot: snapshot, tokenUsage: tokens, footerName: identity?.preferredName, footerAvatarURL: identity?.avatarURL, now: Date(), language: language, timeZone: .current), relativeTo: anchor, theme: theme, isLockedOpen: detailFromFloating ? floatingInteraction.isLockedOpen : detailLocked)
        } else { detail.hide() }
        let detailVisible = detail.frame != nil
        AppNotificationRouter.shared.updateEnvironment(canPresent: floating.frame != nil && floating.isOnActiveSpace && !detailVisible && !sleeping && !screenLocked && !notificationDragging && !floatingMenuVisible && !stopping)
        floating.hasUnread = AppNotificationRouter.shared.messageUnreadCount > 0
        let detailFits = detail.frame.map { frame in NSScreen.screens.contains { $0.visibleFrame.contains(frame) } } ?? false
        let diagnostic = "pid=\(ProcessInfo.processInfo.processIdentifier) mode=standalone phase=\(state.phase.rawValue) has_quota=\(snapshot != nil) host_ui=false status_quota=\(statusDisplay.showsQuotaInformation) floating_visible=\(floating.frame != nil) floating_enabled=\(floating.preferences.enabled) detail_visible=\(detailVisible) detail_fits_screen=\(detailFits)\n"
        try? diagnostic.write(to: root.appendingPathComponent("standalone-state.txt"), atomically: true, encoding: .utf8)
    }
    private func showMenu() {
        floatingMenuVisible = true; AppNotificationRouter.shared.updateEnvironment(canPresent: false)
        defer { floatingMenuVisible = false; render() }
        let menu = NSMenu()
        for (title, action) in [(text("Quota details", "额度详情", "額度詳情"), #selector(clicked)), (text("Refresh", "刷新", "重新整理"), #selector(refreshClicked)), (text("Check for Updates…", "检查更新…", "檢查更新…"), #selector(checkUpdates)), (text("Settings…", "设置…", "設定…"), #selector(settingsClicked)), (text("Quit", "退出", "結束"), #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        let unread = NSMenuItem(title: text("Messages", "消息提醒", "消息提醒") + " (\(AppNotificationRouter.shared.messageUnreadCount))", action: #selector(showUnreadReminders), keyEquivalent: ""); unread.target = self; menu.insertItem(unread, at: 0)
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
            experience?.resetBaseline(); timer?.invalidate(); floating.hide(); floatingInteraction.reset(); floatingHoverTimer?.invalidate(); floatingHoverTimer = nil
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
        if let settings { settings.makeKeyAndOrderFront(nil); updates?.onChange?(); NSApp.activate(ignoringOtherApps: true); return }
        let window = makeSettingsWindow()
        settings = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); render()
    }
    func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = text("QuotaBar — Settings", "QuotaBar — 设置", "QuotaBar — 設定"); window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 840, height: 560)
        func column() -> NSStackView { QuotaSettingsStyle.column(22) }
        func button(_ title: String, _ action: Selector) -> NSButton { QuotaSettingsStyle.button(title, target: self, action: action) }
        let account = column()
        let identityCard = QuotaSettingsStyle.column(6)
        let identityTitle = QuotaSettingsStyle.label(identity?.preferredName ?? text("No account", "暂无账户", "尚無帳號"), size: 16)
        identityTitle.font = .systemFont(ofSize: 16, weight: .semibold); accountIdentityLabel = identityTitle
        let identityRow = NSStackView(); identityRow.spacing = 12
        let accountIcon = NSImageView(image: NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)!)
        accountIcon.contentTintColor = .secondaryLabelColor; accountIcon.imageScaling = .scaleProportionallyUpOrDown
        accountIcon.widthAnchor.constraint(equalToConstant: 32).isActive = true; accountIcon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        identityRow.addArrangedSubview(accountIcon); identityRow.addArrangedSubview(identityTitle)
        QuotaSettingsStyle.fill(identityRow, in: identityCard)
        let planLabel = QuotaSettingsStyle.label("", size: 12, secondary: true); planLabel.isHidden = true; accountPlanLabel = planLabel
        QuotaSettingsStyle.fill(planLabel, in: identityCard)
        let label = QuotaSettingsStyle.label(phaseText, size: 12, secondary: true); statusLabel = label
        QuotaSettingsStyle.fill(label, in: identityCard)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.card(identityCard), in: account)
        let auth = NSStackView(); auth.spacing = 8
        accountActions = []
        for (title, selector) in [(text("Sign in", "登录", "登入"), #selector(loginClicked)), (text("Cancel", "取消"), #selector(cancelClicked)), (text("Sign out", "退出账号", "登出"), #selector(logoutClicked)), (text("Refresh", "刷新", "重新整理"), #selector(refreshClicked)), (text("Quota details", "额度详情", "額度詳情"), #selector(statusDetailsClicked))] {
            let action = button(title, selector); accountActions.append(action)
        }
        // Primary and routine actions precede the separate sign-out group.
        for index in [0, 1, 4, 3] { auth.addArrangedSubview(accountActions[index]) }
        accountActions[0].bezelColor = .controlAccentColor; accountActions[4].bezelColor = .controlAccentColor
        account.addArrangedSubview(auth)
        let signOut = QuotaSettingsStyle.column(0); signOut.addArrangedSubview(accountActions[2])
        QuotaSettingsStyle.fill(signOut, in: account)
        let maintenance = QuotaSettingsStyle.column(10)
        let disclosure = button(text("Troubleshooting", "故障排查", "疑難排解"), #selector(toggleTroubleshooting(_:)))
        disclosure.isBordered = false; disclosure.alignment = .left; disclosure.imagePosition = .imageLeading
        disclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        maintenance.addArrangedSubview(disclosure)
        let advanced = QuotaSettingsStyle.column(10); advanced.isHidden = true; troubleshooting = advanced
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Restart the bundled runtime if quota updates stop working.", "额度持续无法更新时，可重新加载内嵌运行时。", "額度持續無法更新時，可重新載入內嵌執行環境。"), secondary: true), in: advanced)
        advanced.addArrangedSubview(button(text("Reload runtime", "重新加载运行时", "重新載入執行環境"), #selector(reloadClicked)))
        QuotaSettingsStyle.fill(advanced, in: maintenance); QuotaSettingsStyle.fill(QuotaSettingsStyle.card(maintenance), in: account)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Account credentials stay in the isolated local directory.", "凭据保存在本机隔离账户目录。", "憑證儲存在本機隔離帳號目錄。"), secondary: true), in: account)
        let display = column()
        let appearance = QuotaSettingsStyle.column(0)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Theme", "主题", "主題"), control: makeThemePicker()), in: appearance)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: appearance)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Language", "语言", "語言"), control: makeLanguagePicker()), in: appearance)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.section(text("Appearance", "外观", "外觀"), content: appearance), in: display)
        QuotaSettingsStyle.fill(QuotaSettingsStyle.section(text("Everyday behavior", "常驻入口", "常駐入口"), content: makeGeneralSettings()), in: display)
        let experiences = column()
        QuotaSettingsStyle.fill(QuotaSettingsStyle.label(text("Manage quota moods, notifications and celebrations.", "管理额度相关的表情、提醒和互动效果。", "管理額度相關的表情、提醒和互動效果。"), secondary: true), in: experiences)
        if let experience { QuotaSettingsStyle.fill(experience.makeSettingsView(), in: experiences) }
        let bundleVersion = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String : nil
        let about = AboutSettingsView(version: bundleVersion ?? updates?.currentVersion ?? "—", updates: updates?.makeSettingsView(), text: { [weak self] en, zh, tw in self?.text(en, zh, tw) ?? en })
        let mobile = BarkSettingsView(controller: bark, enableMobile: { AppNotificationRouter.shared.setChannelEnabled(.mobile, enabled: $0) }, text: { [weak self] en, zh, tw in self?.text(en, zh, tw) ?? en })
        let pages = [QuotaSettingsPage(title: text("Account", "账户", "帳號"), symbol: "person", content: account), QuotaSettingsPage(title: text("Display", "显示", "顯示"), symbol: "display", content: display), QuotaSettingsPage(title: text("Reminder settings", "提醒设置", "提醒設定"), symbol: "bell", content: experiences, navigationTitle: text("Reminders", "提醒", "提醒")), QuotaSettingsPage(title: text("Mobile push", "手机推送", "手機推播"), symbol: "iphone", content: mobile), QuotaSettingsPage(title: text("About app", "关于应用", "關於應用程式"), symbol: "info.circle", content: about)]
        let shell = QuotaSettingsShellView(pages: pages, version: bundleVersion ?? updates?.currentVersion ?? "—", updateTitle: text("Check for updates", "检查更新", "檢查更新"))
        shell.onCheckUpdates = { [weak self] in self?.updates?.check(manual: true) }
        settingsShell = shell
        mobile.onLayoutChange = { [weak shell] in shell?.refreshDocumentSize() }
        shell.onSelection = { [weak self, weak mobile] in if $0 != 3 { mobile?.conceal() }; self?.settingsPage = $0; self?.synchronizeSettingsControls() }; shell.selectPage(settingsPage)
        window.contentView = shell
        window.setContentSize(NSSize(width: min(900, (NSScreen.main?.visibleFrame.width ?? 1200) - 60), height: min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 90)))
        updates?.onChange = { [weak shell] in shell?.refreshDocumentSize() }
        settings = window
        updateAccountSettings()
        return window
    }
    private func updateAccountSettings() {
        accountIdentityLabel?.stringValue = identity?.preferredName ?? text("No account", "暂无账户", "尚無帳號")
        accountPlanLabel?.stringValue = snapshot?.planType.map { text("Plan: ", "套餐：", "方案：") + $0 } ?? ""
        accountPlanLabel?.isHidden = snapshot?.planType?.isEmpty != false
        guard accountActions.count == 5 else { return }
        let signingIn = state.phase == .signingIn
        let signedIn = identity != nil && state.phase != .needsLogin && !signingIn
        accountActions[0].isHidden = signedIn || signingIn || state.phase == .loading
        accountActions[1].isHidden = !signingIn
        accountActions[2].isHidden = !signedIn
        accountActions[3].isHidden = !signedIn
        accountActions[4].isHidden = !signedIn
        accountActions[3].isEnabled = !requestInFlight
        settingsShell?.refreshDocumentSize()
    }
    @objc private func toggleTroubleshooting(_ sender: NSButton) {
        guard let troubleshooting else { return }
        troubleshooting.isHidden.toggle()
        sender.image = NSImage(systemSymbolName: troubleshooting.isHidden ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        sender.setAccessibilityValue(troubleshooting.isHidden ? 0 : 1)
        settingsShell?.refreshDocumentSize()
    }
    private func synchronizeSettingsControls() {
        guard let shell = settingsShell else { return }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let all = shell.pageContents.flatMap(descendants)
        for control in all.compactMap({ $0 as? QuotaSettingsSwitch }) where control.identifier?.rawValue.hasPrefix("settings.general.") == true {
            control.state = [floating.preferences.enabled, statusDisplay.showsQuotaInformation, SMAppService.mainApp.status == .enabled][control.tag] ? .on : .off
        }
        let selected = ["system", "light", "dark"].firstIndex(of: defaults.string(forKey: "standalone.theme") ?? "system") ?? 0
        for control in all.compactMap({ $0 as? NSPopUpButton }) where control.identifier?.rawValue == "settings.theme" { control.selectItem(at: selected) }
    }
    private func makeThemePicker() -> NSPopUpButton {
        let picker = NSPopUpButton(); picker.addItems(withTitles: [text("System theme", "跟随系统", "跟隨系統"), text("Light", "浅色", "淺色"), text("Dark", "深色")]); picker.target = self; picker.action = #selector(themeChanged)
        picker.identifier = NSUserInterfaceItemIdentifier("settings.theme")
        picker.selectItem(at: ["system", "light", "dark"].firstIndex(of: defaults.string(forKey: "standalone.theme") ?? "system") ?? 0); return picker
    }
    private func makeLanguagePicker() -> NSPopUpButton {
        let picker = NSPopUpButton(); picker.addItems(withTitles: [text("System language", "跟随系统语言", "跟隨系統語言"), "简体中文", "繁體中文", "English"]); picker.target = self; picker.action = #selector(languageChanged)
        picker.selectItem(at: ["system", "simplifiedChinese", "traditionalChinese", "english"].firstIndex(of: defaults.string(forKey: "standalone.language") ?? "system") ?? 0); return picker
    }
    private func makeGeneralSettings() -> NSView {
        let stack = QuotaSettingsStyle.column(0)
        let titles = [text("Show floating button", "显示悬浮按钮", "顯示懸浮按鈕"), text("Menu bar quota", "菜单栏显示额度", "選單列顯示額度"), text("Launch at login", "登录时启动", "登入時啟動")]
        for i in 0..<3 {
            let toggle = QuotaSettingsSwitch(); toggle.tag = i; toggle.identifier = NSUserInterfaceItemIdentifier("settings.general.\(i)")
            toggle.state = [floating.preferences.enabled, statusDisplay.showsQuotaInformation, SMAppService.mainApp.status == .enabled][i] ? .on : .off
            toggle.target = self; toggle.action = #selector(generalSettingChanged(_:)); toggle.setAccessibilityLabel(titles[i])
            QuotaSettingsStyle.fill(QuotaSettingsStyle.row(titles[i], control: toggle), in: stack)
            if i < 2 { QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: stack) }
        }
        QuotaSettingsStyle.fill(QuotaSettingsStyle.line(), in: stack)
        let slider = NSSlider(value: floating.preferences.backgroundTransparency, minValue: 0, maxValue: 100, target: self, action: #selector(floatingTransparencyChanged(_:)))
        slider.identifier = .init("settings.floatingTransparency"); slider.isContinuous = true
        slider.setAccessibilityLabel(text("Background transparency", "背景透明度", "背景透明度"))
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let value = QuotaSettingsStyle.label("\(Int(slider.doubleValue))%", size: 12)
        value.identifier = .init("settings.floatingTransparency.value"); value.widthAnchor.constraint(equalToConstant: 42).isActive = true
        let controls = NSStackView(views: [slider,value]); controls.spacing = 10
        QuotaSettingsStyle.fill(QuotaSettingsStyle.row(text("Background transparency", "背景透明度", "背景透明度"), control: controls), in: stack)
        return stack
    }
    @objc private func floatingTransparencyChanged(_ sender: NSSlider) {
        floating.preferences.backgroundTransparency = sender.doubleValue.rounded()
        if let row = sender.superview as? NSStackView,
           let value = row.arrangedSubviews.compactMap({ $0 as? NSTextField }).first { value.stringValue = "\(Int(floating.preferences.backgroundTransparency))%" }
        render()
    }
    @objc private func generalSettingChanged(_ sender: QuotaSettingsSwitch) {
        switch sender.tag {
        case 0: setFloatingEnabled(sender.state == .on)
        case 1: statusDisplay.showsQuotaInformation = sender.state == .on; render()
        default:
            let proxy = NSButton(); proxy.state = sender.state; startupChanged(proxy); sender.state = proxy.state
        }
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
        if notificationBubble.isVisible { return }
        if !entered, menuRequiresPointerExit, !floatingMenuVisible {
            floatingInteraction.updatePointerInside(false); menuRequiresPointerExit = false
        }
        guard entered, !showingDetail, !floatingMenuVisible else { return }
        floatingInteraction.updatePointerInside(true); detailFromFloating = true; render()
        floatingHoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFloatingHover() }
        }
        floatingHoverTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func updateFloatingHover() {
        guard !floatingMenuVisible else { return }
        let point = NSEvent.mouseLocation
        let inside = floating.frame?.contains(point) == true || (detailFromFloating && detail.frame?.contains(point) == true)
        let previous = floatingInteraction
        floatingInteraction.updatePointerInside(inside)
        if !inside { floatingHoverTimer?.invalidate(); floatingHoverTimer = nil }
        if previous != floatingInteraction { render() }
    }
    private func showFloatingMenu() {
        AppNotificationRouter.shared.updateEnvironment(canPresent: false)
        floatingMenuVisible = true; menuRequiresPointerExit = true
        floatingInteraction.dismissForContextMenu(); showingDetail = false; detailLocked = false
        detail.hide(); floatingHoverTimer?.invalidate(); floatingHoverTimer = nil
        defer {
            floatingMenuVisible = false
            if floating.frame?.contains(NSEvent.mouseLocation) != true { floatingInteraction.updatePointerInside(false); menuRequiresPointerExit = false }
            render()
        }
        let menu = NSMenu()
        for (title, action) in [(text("Refresh", "刷新", "重新整理"), #selector(refreshClicked)), (text("Check for Updates…", "检查更新…", "檢查更新…"), #selector(checkUpdates)), (text("Settings…", "设置…", "設定…"), #selector(settingsClicked)), (text("Quit", "退出", "結束"), #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        let unread = NSMenuItem(title: text("Messages", "消息提醒", "消息提醒") + " (\(AppNotificationRouter.shared.messageUnreadCount))", action: #selector(showUnreadReminders), keyEquivalent: ""); unread.target = self; menu.insertItem(unread, at: 0)
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
        AppNotificationRouter.shared.stop(); messagePanel.close(); DistributedNotificationCenter.default().removeObserver(self)
        experience?.stop()
        updates?.stop()
        stopping = true; timer?.invalidate(); floatingHoverTimer?.invalidate(); floating.hide(); detail.hide(); statusItem = nil
        networkMonitor?.cancel(); networkMonitor = nil
        removeMouseMonitors()
        for task in tasks { task.cancel() }
        Task { await updates?.waitForUpdateCleanup(); if let client { await client.stop() }; sender.reply(toApplicationShouldTerminate: true) }
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
