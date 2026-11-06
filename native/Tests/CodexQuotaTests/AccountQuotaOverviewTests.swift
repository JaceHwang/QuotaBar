import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota

@MainActor final class AccountQuotaOverviewTests: XCTestCase {
    private func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
    private func snapshot(bankCount: Int = 3, secondary: Bool = true) -> AllowanceSnapshot {
        let now = Date()
        return AllowanceSnapshot(usedPercent: 28, remainingPercent: 72, resetsAt: now.addingTimeInterval(12000), receivedAt: now, windowDurationMins: 300, planType: "plus", credits: CreditBalance(hasCredits: false, unlimited: false, balance: nil), bank: BankResetSummary(availableCount: bankCount, credits: (0..<bankCount).map { index in
            BankResetCredit(status: "available", grantedAt: now, expiresAt: now.addingTimeInterval(Double(index + 1) * 86400), title: nil, description: nil)
        }), secondary: secondary ? QuotaWindowSnapshot(usedPercent: 36, remainingPercent: 64, resetsAt: now.addingTimeInterval(6 * 86400), windowDurationMins: 10080) : nil)
    }
    private func content(_ language: CodexDisplayLanguage, bankCount: Int = 3, secondary: Bool = true) -> QuotaDetailContent {
        let now = Date()
        let tokens = TokenUsageSnapshot(receivedAt: now, dailyBuckets: (0..<7).map { TokenUsageDay(date: now.addingTimeInterval(Double($0 - 6) * 86400), tokens: Int64(($0 + 1) * 42000)) }, summary: nil, availability: .available)
        return QuotaDetailFormatter().content(snapshot: snapshot(bankCount: bankCount, secondary: secondary), tokenUsage: tokens, now: now, language: language, timeZone: .current)
    }
    func testResponsiveGroupsRemainInsideTheirCardsInThreeLanguagesAndThemes() throws {
        for language in [CodexDisplayLanguage.english, .simplifiedChinese, .traditionalChinese] {
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                let view = AccountQuotaOverviewView(language: language)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = view; window.appearance = NSAppearance(named: theme)
                defer { window.close() }
                view.update(content: content(language), stateText: "", current: true)
                for width in [540.0, 850.0] {
                    window.setContentSize(NSSize(width: width, height: 1000)); view.layoutSubtreeIfNeeded()
                    let token = try XCTUnwrap(tree(view).first { $0.identifier?.rawValue == "account.tokens" })
                    let bank = try XCTUnwrap(tree(view).first { $0.identifier?.rawValue == "account.bank" })
                    if width < 760 { XCTAssertGreaterThanOrEqual(bank.frame.minY, token.frame.maxY) }
                    else { XCTAssertGreaterThanOrEqual(bank.frame.minX, token.frame.maxX) }
                    XCTAssertEqual(tree(view).filter { $0.identifier?.rawValue == "account.quota.percent" }.count, 2)
                    for label in tree(view).compactMap({ $0 as? NSTextField }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
                        guard let parent = label.superview else { continue }
                        XCTAssertGreaterThanOrEqual(label.frame.minX, -1)
                        XCTAssertLessThanOrEqual(label.frame.maxX, parent.bounds.width + 1, label.stringValue)
                    }
                }
                if let directory = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    window.setContentSize(NSSize(width: 850, height: 900)); view.layoutSubtreeIfNeeded()
                    let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    window.appearance?.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: image) }
                    try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("account-\(language.rawValue)-\(theme.rawValue).png"))
                }
            }
        }
    }
    func testSingleWindowAndEveryBankEntrySurviveThenClearOnSignOut() throws {
        let view = AccountQuotaOverviewView(language: .english)
        view.setFrameSize(NSSize(width: 540, height: 2000))
        view.update(content: content(.english, bankCount: 20, secondary: false), stateText: "Offline", current: false)
        XCTAssertEqual(tree(view).filter { $0.identifier?.rawValue == "account.quota.percent" }.count, 1)
        let bank = try XCTUnwrap(tree(view).first { $0.identifier?.rawValue == "account.bank" })
        XCTAssertEqual(tree(bank).compactMap { $0 as? NSTextField }.count, 45)
        XCTAssertTrue(tree(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Offline" })
        view.update(content: nil, stateText: "Sign in required", current: false)
        XCTAssertFalse(tree(view).contains { $0.identifier?.rawValue == "account.bank" })
        XCTAssertFalse(tree(view).contains { $0.identifier?.rawValue == "account.quota.percent" })
    }
    func testNormalSettingsEntryUpdatesWithoutOpeningFloatingDetail() throws {
        let defaults = UserDefaults(suiteName: "AccountOverview.\(UUID())")!
        defaults.set(true, forKey: "updates.autoDisabled"); defaults.set(false, forKey: "standalone.floating.enabled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let coordinator = StandaloneCoordinator(defaults: defaults, root: root)
        let window = coordinator.makeSettingsWindow(); defer { window.close(); try? FileManager.default.removeItem(at: root) }
        let shell = try XCTUnwrap(window.contentView as? QuotaSettingsShellView); shell.selectPage(0)
        coordinator.receive(.identity(AccountIdentity(displayName: "Example account")))
        coordinator.receive(.quota(snapshot()))
        coordinator.receive(.tokenUsage(TokenUsageSnapshot(receivedAt: Date(), dailyBuckets: [TokenUsageDay(date: Date(), tokens: 1284000)], summary: nil, availability: .available)))
        let percentages = tree(shell.pageContents[0]).compactMap { $0 as? NSTextField }.filter { $0.identifier?.rawValue == "account.quota.percent" }.map(\.stringValue)
        XCTAssertEqual(percentages, ["72%", "64%"])
        if let directory = ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
            window.setContentSize(NSSize(width: 1100, height: 900)); window.makeKeyAndOrderFront(nil); shell.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(shell.bitmapImageRepForCachingDisplay(in: shell.bounds))
            shell.cacheDisplay(in: shell.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("account-settings-integrated.png"))
        }
    }
}
