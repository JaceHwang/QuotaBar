import AppKit
import XCTest
@testable import CodexQuota

@MainActor final class SettingsDockTests: XCTestCase {
    func testSettingsKeepDockWhileMinimizedAndRestoreOnReopenThenHideOnClose() throws {
        let application = NSApplication.shared
        let previous = application.activationPolicy()
        XCTAssertTrue(NSApp.setActivationPolicy(.accessory))
        let suite = "SettingsDock.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let coordinator = StandaloneCoordinator(defaults: defaults, root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let window = coordinator.makeSettingsWindow()
        defer {
            for w in NSApp.windows where w.delegate === coordinator { w.close() }
            window.close(); defaults.removePersistentDomain(forName: suite)
            _ = NSApp.setActivationPolicy(previous)
        }
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "constructing a window alone does not show Dock")
        XCTAssertTrue(coordinator.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "opened settings must have a Dock icon")
        window.miniaturize(nil); RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(window.isMiniaturized)
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "minimized settings keep Dock entry")
        // A floating button can still be visible; AppKit's flag must not suppress reopening.
        XCTAssertTrue(coordinator.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(window.isMiniaturized); XCTAssertTrue(window.isVisible)
        window.close(); RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "closing settings hides Dock again")
        XCTAssertTrue(coordinator.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true))
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        let fresh = try XCTUnwrap(NSApp.windows.first { $0.delegate === coordinator && $0.isVisible })
        XCTAssertFalse(fresh === window, "closed settings are recreated cleanly")
        let unrelated = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        unrelated.isReleasedWhenClosed = false; unrelated.delegate = coordinator; unrelated.close()
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "other windows do not hide settings Dock entry")
        fresh.close()
        XCTAssertTrue(coordinator.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "queued close must not hide a reopened settings Dock entry")
        let replacement = try XCTUnwrap(NSApp.windows.first { $0.delegate === coordinator && $0.isVisible })
        replacement.close(); RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }
}
