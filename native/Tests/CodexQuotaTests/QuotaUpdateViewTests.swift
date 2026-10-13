import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaUpdateViewTests: XCTestCase {
    func testNativeUpdateSettingsPreserveOptInAndRenderBothThemes() throws {
        let suite = "QuotaUpdateViewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = QuotaUpdateController(defaults: defaults, version: "0.7.0", text: { _, zh, _ in zh })
        defer { controller.stop() }
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = controller.makeSettingsView()
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = appearance
            let root = try XCTUnwrap(window.contentView); root.wantsLayer = true
            appearance.performAsCurrentDrawingAppearance { root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
            view.frame = NSRect(x: 20, y: 20, width: 450, height: 220); root.addSubview(view)
            window.orderFront(nil); view.layoutSubtreeIfNeeded(); root.displayIfNeeded()
            defer { window.close() }
            XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("开发候选") })
            let controls = descendants(view).compactMap { $0 as? NSButton }
            XCTAssertEqual(controls.first { $0.title == "自动检查更新" }?.state, .on)
            XCTAssertEqual(controls.first { $0.title == "更新提醒" }?.state, .off)
            let automatic = try XCTUnwrap(controls.first { $0.title == "自动检查更新" })
            automatic.performClick(nil)
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
        let coordinator = StandaloneCoordinator(updateController: controller)
        let window = coordinator.makeSettingsWindow(); window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView?.wantsLayer = true
        window.appearance?.performAsCurrentDrawingAppearance { window.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        defer { window.close() }
        window.orderFront(nil); window.contentView?.layoutSubtreeIfNeeded()
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
        document.scroll(NSPoint(x: 0, y: document.bounds.maxY - scroll.contentSize.height)); scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertTrue(document.visibleRect.intersects(viewButton.convert(viewButton.bounds, to: document)))
        if let path = ProcessInfo.processInfo.environment["CUS_UPDATE_VISUAL_OUTPUT_DIR"], let root = window.contentView {
            root.displayIfNeeded()
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            window.appearance?.performAsCurrentDrawingAppearance { root.cacheDisplay(in: root.bounds, to: bitmap) }
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appendingPathComponent("updates-full-short-available.png"))
        }
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
}

private final class UnavailableFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class AvailableFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data("{\"schemaVersion\":1,\"stable\":{\"macos-arm64\":{\"version\":\"0.8.0\",\"minOS\":\"14.0\",\"releaseNotesURL\":\"https://github.com/JaceHwang/codex-usage-sidebar/releases/tag/v0.8.0\"}}}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
