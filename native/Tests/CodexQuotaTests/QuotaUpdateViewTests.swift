import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaUpdateViewTests: XCTestCase {
    func testBetaSwitchNeedsBothConfirmationsAndPersistsOnlyAfterConsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UpdateChannelStore(url: root.appendingPathComponent("channel.json"))
        var answers = [false], steps: [Int] = []
        let controller = QuotaUpdateController(version: "1.6.0", channelStore: store, confirmBeta: { step in steps.append(step); return answers.removeFirst() }, text: { _, zh, _ in zh })
        defer { controller.stop() }
        let view = controller.makeSettingsView()
        let toggle = try XCTUnwrap(descendants(view).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.accessibilityLabel() == "内测体验" })
        XCTAssertEqual(toggle.state, .off); XCTAssertFalse(store.load())
        toggle.state = .on; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        XCTAssertEqual(steps, [1]); XCTAssertEqual(toggle.state, .off); XCTAssertFalse(store.load())
        answers = [true, false]; steps = []
        toggle.state = .on; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        XCTAssertEqual(steps, [1, 2]); XCTAssertEqual(toggle.state, .off); XCTAssertFalse(store.load())
        answers = [true, true]; steps = []
        toggle.state = .on; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        XCTAssertEqual(steps, [1, 2]); XCTAssertEqual(toggle.state, .on); XCTAssertTrue(store.load())
        toggle.state = .off; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        for _ in 0..<100 { if !store.load() { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.load()); XCTAssertEqual(toggle.state, .off)
    }
    func testBetaEnableSaveFailureLeavesSwitchOff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("blocked"); try Data("file".utf8).write(to: blocked)
        let store = UpdateChannelStore(url: blocked.appendingPathComponent("channel.json"))
        let controller = QuotaUpdateController(version: "1.6.0", channelStore: store, confirmBeta: { _ in true }, text: { _, zh, _ in zh })
        defer { controller.stop() }
        let view = controller.makeSettingsView()
        let toggle = try XCTUnwrap(descendants(view).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.accessibilityLabel() == "内测体验" })
        toggle.state = .on; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        XCTAssertEqual(toggle.state, .off); XCTAssertFalse(store.load()); XCTAssertTrue(controller.statusText.contains("无法保存"))
    }
    func testBetaDisableSaveFailureRemainsVisibleAfterAutomaticCheckAndClearsOnRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("settings"), backup = root.appendingPathComponent("backup")
        let store = UpdateChannelStore(url: folder.appendingPathComponent("channel.json")); try store.save(enabled: true)
        let suite = "BetaSaveFailure-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BetaFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "1.6.0", transport: URLSession(configuration: config), channelStore: store, text: { _, zh, _ in zh })
        defer { controller.stop() }
        let view = controller.makeSettingsView()
        let toggle = try XCTUnwrap(descendants(view).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.accessibilityLabel() == "内测体验" })
        try FileManager.default.moveItem(at: folder, to: backup); try Data("blocked".utf8).write(to: folder)
        toggle.state = .off; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(toggle.state, .on)
        XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("未能保存，重启后内测仍会开启") })
        try FileManager.default.removeItem(at: folder); try FileManager.default.moveItem(at: backup, to: folder)
        toggle.state = .off; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        for _ in 0..<100 { if !store.load() { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.load()); XCTAssertEqual(toggle.state, .off)
        XCTAssertFalse(descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("未能保存") })
    }
    func testDisablingBetaDoesNotCancelAnInProgressStableUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UpdateChannelStore(url: root.appendingPathComponent("channel.json")); try store.save(enabled: true)
        let controller = QuotaUpdateController(version: "1.6.0", updateExecute: { _, emit in
            emit(ApplicationUpdateProgress(.downloading)); try await Task.sleep(for: .seconds(30))
        }, channelStore: store, text: { _, zh, _ in zh })
        defer { controller.stop() }
        let view = controller.makeSettingsView()
        let toggle = try XCTUnwrap(descendants(view).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.accessibilityLabel() == "内测体验" })
        controller.installer.start(version: "1.7.0")
        for _ in 0..<100 { if controller.installer.progress.phase == .downloading { break }; try await Task.sleep(for: .milliseconds(10)) }
        toggle.state = .off; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        for _ in 0..<100 { if !store.load() { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.load()); XCTAssertEqual(controller.installer.progress.phase, .downloading)
    }
    func testInstalledBetaShowsItsChannelAndDoesNotSuggestAutomaticDowngrade() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = QuotaUpdateController(version: "1.8.0-beta.2", channelStore: UpdateChannelStore(url: root.appendingPathComponent("channel.json")), text: { _, zh, _ in zh })
        defer { controller.stop() }
        let labels = descendants(controller.makeSettingsView()).compactMap { $0 as? NSTextField }.map(\.stringValue)
        XCTAssertTrue(labels.contains { $0.contains("1.8.0-beta.2") && $0.contains("内测版") })
        XCTAssertTrue(labels.contains { $0.contains("正式版") && $0.contains("更新") })
    }
    func testBetaCardDescriptionUsesAvailableWidthInBothThemes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = QuotaUpdateController(version: "1.6.0", channelStore: UpdateChannelStore(url: root.appendingPathComponent("channel.json")), text: { _, zh, _ in zh })
        defer { controller.stop() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance)
            let view = controller.makeSettingsView(); view.frame = NSRect(x: 20, y: 20, width: 450, height: 440); window.contentView?.addSubview(view)
            window.orderFront(nil); view.layoutSubtreeIfNeeded()
            let hint = try XCTUnwrap(descendants(view).compactMap { $0 as? NSTextField }.first { $0.stringValue.contains("内测版本可能不稳定") })
            XCTAssertGreaterThan(hint.bounds.width, 200, "The description must not collapse into a narrow column")
            window.close()
        }
    }
    func testDisablingBetaCancelsLateUpdateAndPreventsHandoff() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BetaRace-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "updates.autoDisabled"); defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateChannelStore(url: root.appendingPathComponent("channel.json")); try store.save(enabled: true)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BetaFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "1.6.0", updateExecute: { _, emit in
            emit(ApplicationUpdateProgress(.downloading)); try? await Task.sleep(for: .milliseconds(150))
        }, transport: URLSession(configuration: config), channelStore: store, text: { _, zh, _ in zh })
        defer { controller.stop() }
        var ready = 0; controller.installer.onReady = { ready += 1 }
        controller.check(manual: true)
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.available?.version, "1.8.0-beta.1")
        let view = controller.makeSettingsView()
        let toggle = try XCTUnwrap(descendants(view).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.accessibilityLabel() == "内测体验" })
        controller.installUpdate()
        for _ in 0..<100 { if controller.installer.progress.phase == .downloading { break }; try await Task.sleep(for: .milliseconds(10)) }
        toggle.state = .off; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        for _ in 0..<100 { if !store.load() { break }; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(store.load()); XCTAssertNil(controller.available); XCTAssertEqual(ready, 0)
        XCTAssertEqual(controller.installer.progress.phase, .cancelled)
    }
    func testLateBetaFeedCannotReappearAfterOptOut() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BetaFeedRace-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "updates.autoDisabled"); defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateChannelStore(url: root.appendingPathComponent("channel.json")); try store.save(enabled: true)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DelayedBetaFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "1.6.0", transport: URLSession(configuration: config), channelStore: store, text: { _, zh, _ in zh })
        defer { controller.stop() }
        let view = controller.makeSettingsView()
        let toggle = try XCTUnwrap(descendants(view).compactMap { $0 as? QuotaSettingsSwitch }.first { $0.accessibilityLabel() == "内测体验" })
        let before = DelayedBetaFeedProtocol.requests.value
        controller.check(manual: true)
        for _ in 0..<100 { if DelayedBetaFeedProtocol.requests.value > before { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(DelayedBetaFeedProtocol.requests.value, before)
        toggle.state = .off; NSApp.sendAction(try XCTUnwrap(toggle.action), to: toggle.target, from: toggle)
        for _ in 0..<100 { if !store.load() && !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(store.load()); XCTAssertNil(controller.available)
    }
    func testExplicitInstallControlsAndProgressInAllLanguages() async throws {
        for language in 0..<3 {
            for phase in [ApplicationUpdatePhase.downloading, .verifying, .preparing, .failed] {
                let controller = QuotaUpdateController(version: "0.7.0", updateExecute: { version, emit in
                    guard version == "0.8.0" else { throw CocoaError(.fileReadCorruptFile) }
                    if phase == .failed { throw CocoaError(.fileReadCorruptFile) }
                    emit(ApplicationUpdateProgress(phase, received: 1024, total: 2048))
                    try await Task.sleep(for: .seconds(30))
                }, transport: { let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AvailableFeedProtocol.self]; return URLSession(configuration: config) }(), text: { en, zh, tw in [en, zh, tw][language] })
                defer { controller.stop() }
                controller.check(manual: true)
                for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(10)) }
                let view = controller.makeSettingsView()
                let buttons = descendants(view).compactMap { $0 as? NSButton }
                XCTAssertTrue(buttons.contains { $0.title == ["View release notes", "查看更新内容", "查看更新內容"][language] })
                let install = try XCTUnwrap(buttons.first { $0.title == ["Update now", "立即更新", "立即更新"][language] })
                XCTAssertEqual(controller.installer.progress.phase, .idle)
                XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(install.action), to: install.target, from: install))
                XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(install.action), to: install.target, from: install))
                try await Task.sleep(for: .milliseconds(30))
                XCTAssertEqual(controller.installer.progress.phase, phase)
                XCTAssertEqual(install.isEnabled, phase == .failed)
                XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains { !$0.stringValue.isEmpty })
                let window = StandaloneCoordinator(updateController: controller).makeSettingsWindow(); window.isReleasedWhenClosed = false
                window.setContentSize(NSSize(width: 840, height: 560)); (window.contentView as? QuotaSettingsShellView)?.selectPage(4)
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    window.appearance = NSAppearance(named: appearance); window.orderFront(nil); window.contentView?.layoutSubtreeIfNeeded()
                    if let path = ProcessInfo.processInfo.environment["CUS_UPDATE_VISUAL_OUTPUT_DIR"], let root = window.contentView {
                        root.displayIfNeeded(); let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                        window.appearance?.performAsCurrentDrawingAppearance { root.cacheDisplay(in: root.bounds, to: bitmap) }
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent("update-\(language)-\(phase.rawValue)-\(name).png"))
                    }
                }
                window.close(); controller.installer.cancel()
            }
        }
    }
    func testStartupIgnoresRecentSuccessAndSuccessfulChecksWaitADay() async throws {
        let suite = "QuotaUpdateScheduleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 100000)
        defaults.set(now, forKey: "updates.lastSuccess")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AvailableFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", transport: URLSession(configuration: config), now: { now }, text: { en, _, _ in en })
        defer { controller.stop() }
        now = now.addingTimeInterval(10)
        controller.check()
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(defaults.object(forKey: "updates.lastSuccess") as? Date, now, "Startup checks even after a recent success")
        let completed = now
        now = completed.addingTimeInterval(86399)
        controller.check()
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(defaults.object(forKey: "updates.lastSuccess") as? Date, completed)
        now = completed.addingTimeInterval(86400)
        controller.check()
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(defaults.object(forKey: "updates.lastSuccess") as? Date, now, "Checks again after exactly 24 hours")
    }
    func testFailureKeepsShortRetryAndDisabledAutomaticChecksStayOff() async throws {
        let suite = "QuotaUpdateRetryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 100000)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [UnavailableFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", transport: URLSession(configuration: config), now: { now }, text: { en, _, _ in en })
        defer { controller.stop() }
        let initial = UnavailableFeedProtocol.requests.value
        defaults.set(true, forKey: "updates.autoDisabled")
        now = now.addingTimeInterval(10); controller.check()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(UnavailableFeedProtocol.requests.value, initial)
        controller.check(manual: true)
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(UnavailableFeedProtocol.requests.value, initial + 1, "Manual check works with automatic checks disabled")
        defaults.set(false, forKey: "updates.autoDisabled")
        now = now.addingTimeInterval(299); controller.check()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(UnavailableFeedProtocol.requests.value, initial + 1)
        now = now.addingTimeInterval(1); controller.check()
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(UnavailableFeedProtocol.requests.value, initial + 2, "Failure retries after 5 minutes instead of a day")
        now = now.addingTimeInterval(599); controller.check()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(UnavailableFeedProtocol.requests.value, initial + 2)
        now = now.addingTimeInterval(1); controller.check()
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(UnavailableFeedProtocol.requests.value, initial + 3, "Second failure backs off to 10 minutes")
    }
    func testNativeUpdateSettingsPreserveOptInAndRenderBothThemes() throws {
        let suite = "QuotaUpdateViewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", text: { _, zh, _ in zh })
        defer { controller.stop() }
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = controller.makeSettingsView()
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = appearance
            let root = try XCTUnwrap(window.contentView); root.wantsLayer = true
            appearance.performAsCurrentDrawingAppearance { root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
            view.frame = NSRect(x: 20, y: 20, width: 450, height: 420); root.addSubview(view)
            window.orderFront(nil); view.layoutSubtreeIfNeeded(); root.displayIfNeeded()
            defer { window.close() }
            XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("开发候选") })
            let controls = descendants(view).compactMap { $0 as? QuotaSettingsSwitch }
            XCTAssertEqual(controls.first { $0.accessibilityLabel() == "自动检查更新" }?.state, .on)
            XCTAssertEqual(controls.first { $0.accessibilityLabel() == "更新提醒" }?.state, .off)
            let automatic = try XCTUnwrap(controls.first { $0.accessibilityLabel() == "自动检查更新" })
            automatic.state = .off; NSApp.sendAction(automatic.action!, to: automatic.target, from: automatic)
            XCTAssertTrue(defaults.bool(forKey: "updates.autoDisabled"))
            defaults.set(false, forKey: "updates.autoDisabled")
            if let path = ProcessInfo.processInfo.environment["CUS_UPDATE_VISUAL_OUTPUT_DIR"] {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent("updates-\(name).png"))
            }
        }
    }
    func testConcurrentManualChecksCoalesceAndHTTPFailureIsRecoverable() async throws {
        let suite = "QuotaUpdateNetworkTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "updates.autoDisabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [UnavailableFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", transport: URLSession(configuration: config), text: { en, _, _ in en })
        defer { controller.stop() }
        controller.check(manual: true); controller.check(manual: true)
        for _ in 0..<100 {
            if !controller.isChecking { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(controller.isChecking)
        XCTAssertNil(controller.available)
        XCTAssertEqual(controller.statusText, "Could not check. Try again later.")
        XCTAssertNil(defaults.object(forKey: "updates.lastSuccess"))
    }
    func testAvailableUpdateInIntegratedShortSettingsWindow() async throws {
        let suite = "QuotaUpdateFullSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defaults.set(true, forKey: "updates.autoDisabled")
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AvailableFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", transport: URLSession(configuration: config), text: { _, zh, _ in zh })
        defer { controller.stop() }
        controller.check(manual: true)
        for _ in 0..<100 { if !controller.isChecking { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(controller.available?.version, "0.8.0")
        let notesView = controller.makeSettingsView()
        XCTAssertTrue(descendants(notesView).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("• 改善更新提醒") })
        let coordinator = StandaloneCoordinator(updateController: controller)
        let window = coordinator.makeSettingsWindow(); window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView?.wantsLayer = true
        window.appearance?.performAsCurrentDrawingAppearance { window.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        defer { window.close() }
        window.orderFront(nil); (window.contentView as? QuotaSettingsShellView)?.selectPage(4); window.contentView?.layoutSubtreeIfNeeded()
        let initialScroll = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        let initialDocument = try XCTUnwrap(initialScroll.documentView)
        let accountStatus = try XCTUnwrap(descendants(initialDocument).compactMap { $0 as? NSTextField }.first)
        accountStatus.stringValue = "Account ready\nExample account\nUpdated now"
        controller.onChange?(); window.contentView?.layoutSubtreeIfNeeded()
        let initialCheck = try XCTUnwrap(descendants(initialDocument).compactMap { $0 as? NSButton }.first { $0.title == "检查更新" })
        XCTAssertTrue(initialDocument.visibleRect.contains(initialCheck.convert(initialCheck.bounds, to: initialDocument)), "Automatically sized settings keep the check action fully visible")
        window.setContentSize(NSSize(width: 510, height: 340)); window.contentView?.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(document.isFlipped)
        XCTAssertEqual(document.visibleRect.minY, 0, accuracy: 1)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentSize.height)
        let viewButton = try XCTUnwrap(descendants(document).compactMap { $0 as? NSButton }.first { $0.title == "立即更新" })
        XCTAssertFalse(viewButton.superview?.isHidden ?? true)
        document.scrollToVisible(viewButton.convert(viewButton.bounds, to: document)); scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertTrue(document.visibleRect.intersects(viewButton.convert(viewButton.bounds, to: document)), "Update action remains reachable inside the longer About page")
        if let path = ProcessInfo.processInfo.environment["CUS_UPDATE_VISUAL_OUTPUT_DIR"], let root = window.contentView {
            root.displayIfNeeded()
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            window.appearance?.performAsCurrentDrawingAppearance { root.cacheDisplay(in: root.bounds, to: bitmap) }
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent("updates-full-short-available.png"))
        }
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}
private final class UnavailableFeedProtocol: URLProtocol, @unchecked Sendable {
    static let requests = RequestCounter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.increment()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class AvailableFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data("{\"schemaVersion\":1,\"stable\":{\"macos-arm64\":{\"version\":\"0.8.0\",\"minOS\":\"14.0\",\"summary\":\"改善更新提醒\",\"releaseNotes\":\"更新内容\\n• 改善更新提醒\\n• 修复额度刷新\",\"releaseNotesURL\":\"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.8.0\"}}}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BetaFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data("{\"schemaVersion\":1,\"stable\":{\"macos-arm64\":{\"version\":\"1.7.0\",\"minOS\":\"14.0\",\"releaseNotesURL\":\"https://github.com/JaceHwang/QuotaBar/releases/tag/v1.7.0\"}},\"beta\":{\"macos-arm64\":{\"version\":\"1.8.0-beta.1\",\"minOS\":\"14.0\",\"releaseNotesURL\":\"https://github.com/JaceHwang/QuotaBar/releases/tag/v1.8.0-beta.1\"}}}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class DelayedBetaFeedProtocol: URLProtocol, @unchecked Sendable {
    static let requests = RequestCounter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.increment()
        let data = Data("{\"schemaVersion\":1,\"stable\":{},\"beta\":{\"macos-arm64\":{\"version\":\"1.8.0-beta.1\",\"minOS\":\"14.0\",\"releaseNotesURL\":\"https://github.com/JaceHwang/QuotaBar/releases/tag/v1.8.0-beta.1\"}}}".utf8)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
