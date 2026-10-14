import Foundation
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaResourceBundleTests: XCTestCase {
    func testPackagedAppResourcesDoNotEvaluateBuildTreeFallback() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let app = temporary.appendingPathComponent("QuotaBar.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        let package = resources.appendingPathComponent("CodexQuota_CodexQuota.bundle")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "example.quotabar", "CFBundlePackageType": "APPL", "CFBundleExecutable": "QuotaBar"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("resource".utf8).write(to: package.appendingPathComponent("Resources/icon.txt"))
        let main = try XCTUnwrap(Bundle(url: app))
        var fallbackUsed = false
        let result = try XCTUnwrap(QuotaResourceBundle.resolve(main: main, module: { fallbackUsed = true; return main }))
        XCTAssertEqual(result.bundleURL.standardizedFileURL, package.standardizedFileURL)
        XCTAssertNotNil(result.url(forResource: "icon", withExtension: "txt", subdirectory: "Resources"))
        XCTAssertFalse(fallbackUsed, "Installed apps must not execute a toolchain-generated build-path fallback")
    }

    func testIncompleteAppDoesNotInvokeFatalModuleAccessor() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let app = temporary.appendingPathComponent("QuotaBar.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "example.quotabar", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let main = try XCTUnwrap(Bundle(url: app))
        var fallbackUsed = false
        XCTAssertNil(QuotaResourceBundle.resolve(main: main, module: { fallbackUsed = true; return main }))
        XCTAssertFalse(fallbackUsed)
    }

    func testDevelopmentHostStillLoadsModuleThemeResources() throws {
        let host = Bundle(for: QuotaResourceBundleTests.self)
        let package = try XCTUnwrap(QuotaResourceBundle.resolve(main: host))
        XCTAssertNotNil(package.url(forResource: "quota-icon-light", withExtension: "png", subdirectory: "Resources"))
        XCTAssertNotNil(package.url(forResource: "quota-icon-dark", withExtension: "png", subdirectory: "Resources"))
    }
}
