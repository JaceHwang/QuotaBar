import AppKit
import XCTest
@testable import CodexQuota

@MainActor
final class FloatingQuotaButtonTests: XCTestCase {
    func testHoverCloseRoutesSeparatelyAndHidesPersistently() {
        let name = "FloatingQuotaButtonTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = FloatingQuotaPreferences(defaults: defaults)
        let button = FloatingQuotaButton(preferences: preferences)
        defer { button.hide() }
        var clicks = 0; var closes = 0
        button.onClick = { clicks += 1 }
        button.onClose = { closes += 1 }
        button.show(summary: nil, theme: .light, tooltip: "Loading", fallback: "Loading", dimmed: false)
        XCTAssertTrue(button.closeButton.isHidden)
        let frame = button.frame
        button.interaction.onHover?(true)
        XCTAssertFalse(button.closeButton.isHidden)
        XCTAssertEqual(button.frame, frame)
        let point = CGPoint(x: button.closeButton.frame.midX, y: button.closeButton.frame.midY)
        XCTAssertTrue(button.interaction.hitTest(point) === button.closeButton)
        button.closeButton.performClick(nil)
        XCTAssertEqual(closes, 1); XCTAssertEqual(clicks, 0)
        XCTAssertNil(button.frame)
        XCTAssertFalse(FloatingQuotaPreferences(defaults: defaults).enabled)
        preferences.enabled = true
        button.show(summary: nil, theme: .dark, tooltip: "", fallback: "Loading", dimmed: false)
        XCTAssertTrue(button.closeButton.isHidden)
        button.interaction.onHover?(true)
        button.interaction.onHover?(false)
        XCTAssertTrue(button.closeButton.isHidden)
        XCTAssertTrue(button.interaction.hitTest(point) === button.interaction)
    }
    func testDefaultEnabledAndExplicitDisabledSurvivesRecreation() {
        let name = "FloatingQuotaButtonTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = FloatingQuotaPreferences(defaults: defaults)
        XCTAssertTrue(preferences.enabled)
        preferences.enabled = false
        XCTAssertFalse(FloatingQuotaPreferences(defaults: defaults).enabled)
        preferences.enabled = true
        XCTAssertTrue(FloatingQuotaPreferences(defaults: defaults).enabled)
    }
    func testSavedPositionAndRemovedDisplayRecoverIntoVisibleScreen() {
        let name = "FloatingQuotaButtonTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = FloatingQuotaPreferences(defaults: defaults)
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        preferences.origin = CGPoint(x: 350, y: 120)
        let restored = FloatingQuotaPreferences(defaults: defaults)
        XCTAssertEqual(restored.frame(size: CGSize(width: 200, height: 30), screens: [screen]).origin, CGPoint(x: 350, y: 120))
        restored.origin = CGPoint(x: -1500, y: 1000)
        XCTAssertTrue(screen.contains(restored.frame(size: CGSize(width: 200, height: 30), screens: [screen])))
    }
    func testToggleControlsActualPanelVisibilityAndScreenBounds() {
        let name = "FloatingQuotaButtonTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = FloatingQuotaPreferences(defaults: defaults)
        let button = FloatingQuotaButton(preferences: preferences)
        button.show(summary: nil, theme: .light, tooltip: "Loading", fallback: "Loading", dimmed: true)
        XCTAssertNotNil(button.frame)
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(button.frame!) })
        XCTAssertEqual(button.frame?.height, 30)
        preferences.enabled = false
        button.show(summary: nil, theme: .dark, tooltip: "", fallback: "Loading", dimmed: true)
        XCTAssertNil(button.frame)
        preferences.enabled = true
        button.show(summary: nil, theme: .dark, tooltip: "", fallback: "Loading", dimmed: false)
        XCTAssertNotNil(button.frame)
        button.hide(); XCTAssertNil(button.frame)
    }
    func testNegativeDisplayCoordinatesAndInvalidStoredPosition() {
        let name = "FloatingQuotaButtonTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = FloatingQuotaPreferences(defaults: defaults)
        let left = CGRect(x: -800, y: 0, width: 800, height: 600)
        preferences.origin = CGPoint(x: -500, y: 100)
        XCTAssertEqual(preferences.frame(size: CGSize(width: 200, height: 30), screens: [CGRect(x: 0, y: 0, width: 800, height: 600), left]).origin, CGPoint(x: -500, y: 100))
        preferences.origin = CGPoint(x: CGFloat.nan, y: 10)
        XCTAssertNil(preferences.origin)
    }
    func testDragThresholdSeparatesClickAndDrag() {
        let view = FloatingQuotaInteractionView(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
        var point = CGPoint(x: 40, y: 40)
        view.screenPointResolver = { _ in point }
        var clicks = 0; var drags = 0; var ends = 0
        view.onPrimaryClick = { clicks += 1 }
        view.onDrag = { _ in drags += 1 }
        view.onDragEnded = { ends += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event); point.x += 1; view.mouseDragged(with: event); view.mouseUp(with: event)
        XCTAssertEqual(clicks, 1); XCTAssertEqual(drags, 0)
        view.mouseDown(with: event); point.x += 20; view.mouseDragged(with: event); view.mouseUp(with: event)
        XCTAssertEqual(clicks, 1); XCTAssertEqual(drags, 1); XCTAssertEqual(ends, 1)
    }
}
