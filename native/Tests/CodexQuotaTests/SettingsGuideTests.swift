import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class SettingsGuideTests: XCTestCase {
    func tree(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(tree) }
    func testSharedButtonUsesStandardTactileMetrics() {
        let button = SettingsAccentButton(frame: .zero)
        button.title = "Continue"
        XCTAssertEqual(button.intrinsicContentSize.height, 40, accuracy: 0.01)
        let labelWidth = NSAttributedString(string: button.title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]).size().width
        XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.width, labelWidth + 36)
    }
    func testPrimaryButtonFaceUsesNeutralSlate() throws {
        let button = SettingsAccentButton(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let color = try XCTUnwrap(bitmap.colorAt(x: 12, y: 20)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(abs(color.blueComponent - color.redComponent), 0.16, "Primary face should be neutral slate, not saturated blue")
        XCTAssertLessThan(color.redComponent, 0.4)
    }
    func testPrimaryButtonIsLitFromAbove() throws {
        let button = SettingsAccentButton(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let top = try XCTUnwrap(bitmap.colorAt(x: 12, y: 10)?.usingColorSpace(.sRGB))
        let bottom = try XCTUnwrap(bitmap.colorAt(x: 12, y: 30)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(top.redComponent, bottom.redComponent)
    }
    func testSecondaryButtonUsesQuietDarkSurfaceInDarkAppearance() throws {
        let button = SettingsAccentButton(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        button.usesAccentFill = false
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua)); button.appearance = appearance
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        appearance.performAsCurrentDrawingAppearance { button.cacheDisplay(in: button.bounds, to: bitmap) }
        let face = try XCTUnwrap(bitmap.colorAt(x: 12, y: 20)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(face.redComponent, 0.4, "Secondary controls should blend into a dark surface")
        XCTAssertLessThan(abs(face.redComponent - face.blueComponent), 0.03, "The face remains neutral")
    }
    func testLargeButtonScalesWithItsLabel() {
        let button = SettingsAccentButton(frame: .zero)
        button.buttonSize = .lg
        button.title = "Continue"
        XCTAssertEqual(button.intrinsicContentSize.height, 40 * 16.0 / 14.0, accuracy: 0.01)
    }
    func testPressedPrimaryReversesLight() throws {
        let button = SettingsAccentButton(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        button.highlight(true)
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let top = try XCTUnwrap(bitmap.colorAt(x: 12, y: 10)?.usingColorSpace(.sRGB))
        let bottom = try XCTUnwrap(bitmap.colorAt(x: 12, y: 30)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(top.redComponent, bottom.redComponent)
    }
    func testDisabledTextButtonRemainsReadableInDarkAppearance() throws {
        let button = SettingsAccentButton(frame: NSRect(x: 0, y: 0, width: 180, height: 40))
        button.variant = .text; button.title = "Unavailable"; button.isEnabled = false
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1).setFill(); button.bounds.fill()
        try XCTUnwrap(NSAppearance(named: .darkAqua)).performAsCurrentDrawingAppearance { button.draw(button.bounds) }
        context.flushGraphics()
        var brightest: CGFloat = 0
        for y in 0..<40 { for x in 0..<180 {
            if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) { brightest = max(brightest, pixel.redComponent) }
        } }
        XCTAssertGreaterThan(brightest, 0.55, "Disabled text must remain distinguishable on a dark surface")
    }
    func testSettingsActionsShareBarkMetricsAndDetailBrand() throws {
        let defaults = UserDefaults(suiteName: "Uniform.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let experience = QuotaExperienceController(root: root, defaults: defaults, language: { .english }, requestPermission: { $0("") })
        let coordinator = StandaloneCoordinator(experienceController: experience, defaults: defaults, root: root)
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
        XCTAssertEqual(tree(shell).filter { $0 is QuotaThemeIconView }.count, 1, "Sidebar must reuse the detail ring")
        XCTAssertEqual(tree(shell.pageContents[4]).filter { $0 is QuotaThemeIconView }.count, 1, "About must reuse the detail ring")
        for page in 0..<shell.pageContents.count {
            shell.selectPage(page); shell.layoutSubtreeIfNeeded()
            let actions = tree(shell.pageContents[page]).compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }
            for button in actions {
                XCTAssertTrue(button is SettingsAccentButton, "Unstyled settings action: \(button.title)")
                XCTAssertEqual(button.frame.height, 40, accuracy: 1, "Action height: \(button.title)")
                if !button.title.isEmpty {
                    let expected = NSAttributedString(string: button.title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]).size().width + 36
                    XCTAssertGreaterThanOrEqual(button.frame.width + 1, max(100, expected), "Label padding: \(button.title)")
                }
            }
        }
    }
    func testSavedKeyIsReadOnlyOnExplicitRevealAndClearedWhenHidden() throws {
        let fixture = BarkNotificationTests()
        let (controller, secrets, transport) = fixture.controller(); defer { controller.stop() }
        XCTAssertTrue(controller.saveKey("fake-saved-key"))
        let generation = controller.preferences.configurationGeneration
        let reads = secrets.reads
        let view = BarkSettingsView(controller: controller, text: { en, _, _ in en })
        XCTAssertEqual(secrets.reads, reads)
        let eye = try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "bark.reveal" })
        eye.performClick(nil)
        let plain = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "bark.deviceKey.plain" })
        XCTAssertFalse(plain.isHidden); XCTAssertEqual(plain.stringValue, "fake-saved-key")
        XCTAssertEqual(controller.draft, ""); XCTAssertEqual(controller.preferences.configurationGeneration, generation)
        XCTAssertFalse(controller.preferences.enabled); XCTAssertEqual(transport.sends, 0)
        try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "bark.save" }).performClick(nil)
        XCTAssertEqual(controller.preferences.configurationGeneration, generation, "Viewing a saved Key is not an editable draft")
        XCTAssertEqual(controller.draft, ""); XCTAssertEqual(secrets.key, "fake-saved-key")
        eye.performClick(nil)
        XCTAssertTrue(plain.isHidden); XCTAssertEqual(plain.stringValue, ""); XCTAssertEqual(view.keyField.stringValue, "")
    }
    func testDraftEditsAndAutomaticConcealKeepSavedSecretSeparate() throws {
        let (controller, secrets, _) = BarkNotificationTests().controller(); defer { controller.stop() }
        XCTAssertTrue(controller.saveKey("saved-key")); controller.draft = "new-draft"
        let view = BarkSettingsView(controller: controller, text: { en, _, _ in en })
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let eye = try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "bark.reveal" })
        let plain = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "bark.deviceKey.plain" })
        eye.performClick(nil); plain.stringValue = "edited-draft"; view.controlTextDidChange(Notification(name: NSText.didChangeNotification))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertTrue(plain.isHidden); XCTAssertEqual(plain.stringValue, "")
        XCTAssertEqual(controller.draft, "edited-draft"); XCTAssertEqual(secrets.key, "saved-key")
        eye.performClick(nil); window.contentView = NSView()
        XCTAssertTrue(plain.isHidden); XCTAssertEqual(plain.stringValue, "")
        let rebuilt = BarkSettingsView(controller: controller, text: { en, _, _ in en })
        XCTAssertEqual(rebuilt.keyField.stringValue, "edited-draft")
    }
    func testFailedExplicitRevealKeepsConfigurationAndReportsStorageFailure() throws {
        final class Unavailable: BarkSecretStore {
            func read() throws -> String? { throw BarkSecretError.unavailable }
            func save(_ key: String) throws {}
            func clear() throws {}
        }
        let transport = BarkNotificationTests.Transport()
        let controller = BarkNotificationController(defaults: UserDefaults(suiteName: "GuideFailure.\(UUID())")!, secrets: Unavailable(), transport: transport, deliveries: BarkDeliveryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        defer { controller.stop() }
        let generation = controller.preferences.configurationGeneration
        let view = BarkSettingsView(controller: controller, text: { en, _, _ in en })
        var layoutChanges = 0; view.onLayoutChange = { layoutChanges += 1 }
        try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "bark.reveal" }).performClick(nil)
        let plain = try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == "bark.deviceKey.plain" })
        XCTAssertTrue(plain.isHidden); XCTAssertEqual(plain.stringValue, "")
        XCTAssertEqual(controller.status, .unavailable); XCTAssertEqual(controller.draft, "")
        XCTAssertEqual(controller.preferences.configurationGeneration, generation); XCTAssertEqual(transport.sends, 0)
        XCTAssertGreaterThan(layoutChanges, 0, "Changing error text must notify the scroll layout consumer")
    }
    func testRenderSelectedCSettingsAtNormalSize() throws {
        guard let output = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        for language in [CodexDisplayLanguage.english, .simplifiedChinese, .traditionalChinese] {
            let suite = "GuideRender.\(UUID())", defaults = UserDefaults(suiteName: "GuideRender.temporary")!
            defaults.set(language.rawValue, forKey: "standalone.language"); defaults.set(true, forKey: "updates.autoDisabled")
            let update = QuotaUpdateController(defaults: defaults, version: "1.2.0", text: { en, zh, tw in language == .english ? en : language == .simplifiedChinese ? zh : tw }); defer { update.stop() }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            let experience = QuotaExperienceController(root: root, defaults: defaults, language: { language }, requestPermission: { $0("") })
            let coordinator = StandaloneCoordinator(updateController: update, experienceController: experience, defaults: defaults, root: root)
            let window = coordinator.makeSettingsWindow(); defer { window.close(); defaults.removePersistentDomain(forName: "GuideRender.temporary") }
            let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
            for dark in [false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for page in 0..<shell.pageContents.count {
                    window.setContentSize(NSSize(width: 900, height: 800)); shell.selectPage(page); shell.layoutSubtreeIfNeeded()
                    let scroll = try XCTUnwrap(shell.subviews.compactMap { $0 as? NSScrollView }.first)
                    let document = try XCTUnwrap(scroll.documentView)
                    XCTAssertLessThanOrEqual(shell.pageContents[page].frame.maxX, document.bounds.maxX + 1)
                    let bitmap = try XCTUnwrap(shell.bitmapImageRepForCachingDisplay(in: shell.bounds))
                    window.appearance?.performAsCurrentDrawingAppearance { shell.cacheDisplay(in: shell.bounds, to: bitmap) }
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("settings-c-\(language.rawValue)-\(dark)-\(page).png"))
                }
            }
        }
    }
    func testAboutIsLastAndUnavailableWebsiteCannotOpen() throws {
        let coordinator = StandaloneCoordinator(defaults: UserDefaults(suiteName: "Guide.\(UUID())")!, root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let window = coordinator.makeSettingsWindow(); defer { window.close() }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView)
        let navigation = tree(shell).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.hasPrefix("settings.nav.") == true }.sorted { $0.tag < $1.tag }
        XCTAssertEqual(navigation.count, 5)
        XCTAssertTrue(["About app", "关于应用", "關於應用程式"].contains(navigation.last!.title))
        shell.selectPage(4)
        let website = try XCTUnwrap(tree(shell).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "about.website" })
        XCTAssertFalse(website.isEnabled); XCTAssertNotNil(website.toolTip)
        XCTAssertNotNil(tree(shell).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "about.github" && $0.isEnabled })
        shell.selectPage(3)
        XCTAssertTrue(tree(shell).contains { $0 is BarkSettingsView })
    }
}
