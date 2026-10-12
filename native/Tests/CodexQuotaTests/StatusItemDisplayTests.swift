import AppKit
import XCTest
@testable import CodexQuota

@MainActor
final class StatusItemDisplayTests: XCTestCase {
    func testQuotaDisplayDefaultsOnAndIconChoicePersistsIndependently() {
        let suite = "StatusItemDisplayTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = StatusItemDisplayPreferences(defaults: defaults)
        XCTAssertTrue(preferences.showsQuotaInformation)
        preferences.showsQuotaInformation = false
        XCTAssertFalse(StatusItemDisplayPreferences(defaults: defaults).showsQuotaInformation)
        XCTAssertTrue(FloatingQuotaPreferences(defaults: defaults).enabled)
    }
    func testImageModesKeepQuotaSizingAndUseTemplateIcons() {
        let quota = QuotaStatusItemImage.make(showQuotaInformation: true, text: "5 hours 85% · 19:33\n7 days 78% · Oct 18", theme: .light)
        XCTAssertTrue(quota.isTemplate)
        XCTAssertGreaterThan(quota.size.width, 18)
        let icon = QuotaStatusItemImage.make(showQuotaInformation: false, text: "unused", theme: .light)
        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(icon.isTemplate)
    }
    func testMenuIconHasTransparentCornersAndVisibleArtwork() throws {
        let image = QuotaStatusItemImage.make(showQuotaInformation: false, text: "", theme: .dark)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)).alphaComponent, 0, accuracy: 0.01)
        let visible = (0..<bitmap.pixelsWide).reduce(0) { count, x in
            count + (0..<bitmap.pixelsHigh).filter { (bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.5 }.count
        }
        XCTAssertGreaterThan(visible, 20)
    }

}
