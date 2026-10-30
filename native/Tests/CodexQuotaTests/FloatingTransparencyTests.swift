import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota
@MainActor final class FloatingTransparencyTests: XCTestCase {
    func testBackgroundPercentagePersistsClampsAndKeepsPureThemeColorOnHover() throws {
        let name="Transparency.\(UUID())", defaults=UserDefaults(suiteName:"Transparency.temporary")!
        defer { defaults.removePersistentDomain(forName:"Transparency.temporary") }
        let prefs=FloatingQuotaPreferences(defaults:defaults)
        XCTAssertEqual(prefs.backgroundTransparency,20,name)
        prefs.backgroundTransparency=73
        XCTAssertEqual(FloatingQuotaPreferences(defaults:defaults).backgroundTransparency,73)
        prefs.backgroundTransparency = -4;XCTAssertEqual(prefs.backgroundTransparency,0)
        prefs.backgroundTransparency = 150;XCTAssertEqual(prefs.backgroundTransparency,100)
        let button=FloatingQuotaButton(preferences:prefs);defer { button.hide() }
        for theme in [CodexInterfaceTheme.light,.dark] { for value in [0,20,100] {
            prefs.backgroundTransparency=Double(value)
            button.show(summary:nil,theme:theme,tooltip:"",fallback:"Loading",dimmed:false)
            for hover in [false,true,false] {
                button.interaction.onHover?(hover)
                let color=try XCTUnwrap(button.interaction.layer?.backgroundColor)
                let rgba=try XCTUnwrap(NSColor(cgColor:color)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(rgba.alphaComponent,1-Double(value)/100,accuracy:0.01)
                XCTAssertEqual(rgba.redComponent,theme == .light ? 1:0,accuracy:0.01)
                XCTAssertEqual(button.interaction.alphaValue,1)
            }
        } }
    }
    func testSettingsHaveWorkingSliderAndMinimizeButton() throws {
        let name="TransparencySettings.\(UUID())",defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let coordinator=StandaloneCoordinator(defaults:defaults,root:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let window=coordinator.makeSettingsWindow();defer { window.close() }
        (window.contentView as? QuotaSettingsShellView)?.selectPage(1)
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isEnabled == true)
        func tree(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(tree) }
        let slider=try XCTUnwrap(tree(window.contentView!).compactMap { $0 as? NSSlider }.first { $0.identifier?.rawValue=="settings.floatingTransparency" })
        XCTAssertEqual(slider.minValue,0);XCTAssertEqual(slider.maxValue,100)
        slider.doubleValue=65;NSApp.sendAction(slider.action!,to:slider.target,from:slider)
        XCTAssertEqual(FloatingQuotaPreferences(defaults:defaults).backgroundTransparency,65)
        XCTAssertTrue(tree(window.contentView!).compactMap { $0 as? NSTextField }.contains { $0.stringValue=="65%" })
    }
}
