import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaUpdateViewTests: XCTestCase {
    func testStartupIgnoresRecentSuccessAndSuccessfulChecksWaitADay() async throws {
        let suite = "QuotaUpdateScheduleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 100000)
        defaults.set(now, forKey: "updates.lastSuccess")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AvailableFeedProtocol.self]
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", transport: URLSession(configuration: config), now: { now }, text: { en, _, _ in en })
        defer { controller.stop() }
        now = now.addingTimeInterval(31)
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
        now = now.addingTimeInterval(31); controller.check()
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
        let viewButton = try XCTUnwrap(descendants(document).compactMap { $0 as? NSButton }.first { $0.title == "查看更新" })
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
