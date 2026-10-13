import AppKit
import QuotaCore
import XCTest
@testable import CodexQuota

@MainActor
final class QuotaDetailCardVisualTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_800_000)
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private let referenceCardHeight: CGFloat = 720

    func testThemeIconAssetFollowsCodexAppearance() {
        XCTAssertEqual(
            QuotaThemeIconAsset.forAppearance(NSAppearance(named: .darkAqua)),
            .dark
        )
        XCTAssertEqual(
            QuotaThemeIconAsset.forAppearance(NSAppearance(named: .aqua)),
            .light
        )
    }

    func testThemeIconViewRendersTheBundledColoredAsset() throws {
        let icon = QuotaThemeIconView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        icon.updateAppearance(appearance)

        let representation = try XCTUnwrap(
            icon.bitmapImageRepForCachingDisplay(in: icon.bounds)
        )
        icon.cacheDisplay(in: icon.bounds, to: representation)

        let coloredPixelCount = (0 ..< Int(icon.bounds.width)).reduce(0) { count, x in
            count + (0 ..< Int(icon.bounds.height)).reduce(0) { count, y in
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else {
                    return count
                }
                let components = [color.redComponent, color.greenComponent, color.blueComponent]
                return components.max()! - components.min()! > 0.15 ? count + 1 : count
            }
        }

        XCTAssertGreaterThan(
            coloredPixelCount,
            80,
            "The visual fixture must render the shipped theme icon rather than the gray fallback ring."
        )
    }

    func testRendersEveryLocalizedThemeFixtureWithNaturalInformationBand() throws {
        let outputDirectory = ProcessInfo.processInfo.environment[
            "CUS_VISUAL_OUTPUT_DIR"
        ].map(URL.init(fileURLWithPath:))
        if let outputDirectory {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        for (language, languageName, _) in languages {
            let content = QuotaDetailFormatter().content(
                snapshot: longBankSnapshot,
                tokenUsage: tokenUsageSnapshot,
                footerName: "demo@example.com",
                now: now,
                language: language,
                timeZone: timeZone
            )
            let rowHeights = Array(
                repeating: QuotaDetailLayout.rowHeight,
                count: content.rows.count
            )
            let cardHeight = QuotaDetailLayout.contentHeight(
                rowContentHeight: rowHeights.reduce(0, +),
                tokenUsageVisible: true,
                secondaryQuotaVisible: content.quotaWindows.count > 1
            )

            for (appearanceName, appearance) in appearances {
                var renderedCard: QuotaDetailCardView?
                appearance.performAsCurrentDrawingAppearance {
                    renderedCard = QuotaDetailCardView(
                        frame: CGRect(
                            x: 0,
                            y: 0,
                            width: QuotaDetailLayout.width,
                            height: cardHeight
                        ),
                        content: content,
                        rowHeights: rowHeights,
                        version: ProcessInfo.processInfo.environment["CUS_VISUAL_VERSION"] ?? "0.3.3",
                        isLockedOpen: true,
                        lockAccessibilityLabel: QuotaLocalization(language: language).unlockDetailWindow,
                        onOpenURL: { _ in }
                    )
                    renderedCard?.appearance = appearance
                }
                let card = try XCTUnwrap(renderedCard)
                card.layoutSubtreeIfNeeded()

                let tokenView = try XCTUnwrap(
                    descendants(of: card)
                        .compactMap { $0 as? QuotaTokenUsageView }
                        .first
                )
                XCTAssertEqual(tokenView.barCount, 7)
                XCTAssertEqual(
                    descendants(of: tokenView)
                        .compactMap { $0 as? QuotaTokenUsageBarView }
                        .count,
                    7,
                    "The reference chart keeps exactly seven visible columns."
                )
                XCTAssertFalse(
                    descendants(of: tokenView)
                        .contains { $0 is NSScrollView },
                    "Seven reference columns fit directly in the token band."
                )
                XCTAssertFalse(
                    descendants(of: tokenView)
                        .contains { $0 is TokenUsageLegendView },
                    "The compact reference omits the chart legend."
                )
                XCTAssertFalse(
                    descendants(of: card)
                        .compactMap { $0 as? NSTextField }
                        .contains {
                            guard let summary = content.remainingSummary else {
                                return false
                            }
                            return $0.stringValue == summary
                        },
                    "The compact reference omits the duplicate remaining summary."
                )
                XCTAssertEqual(
                    descendants(of: card)
                        .compactMap { $0 as? QuotaDetailIconView }
                        .count,
                    content.rows.count,
                    "Every quota detail row receives its leading linear icon."
                )
                XCTAssertEqual(
                    descendants(of: card)
                        .compactMap { $0 as? NSButton }
                        .count,
                    4,
                    "The card includes the header lock control plus Tibo, GitHub and settings footer controls."
                )
                XCTAssertTrue(
                    descendants(of: card)
                        .compactMap { $0 as? NSTextField }
                        .contains { $0.stringValue == "demo@example.com" },
                    "The footer renders the account identity supplied by Codex."
                )
                XCTAssertFalse(
                    descendants(of: card)
                        .contains { $0 is QuotaInformationLinkButton },
                    "The approved reference image does not include the Tibo row."
                )

                let scrollView = try XCTUnwrap(
                    descendants(of: card)
                        .compactMap { $0 as? NSScrollView }
                        .first
                )
                XCTAssertFalse(
                    scrollView.hasVerticalScroller,
                    "The unconstrained reference card grows with its information rows instead of enforcing the former product height cap."
                )

                let png = try renderPNG(card)
                XCTAssertGreaterThan(png.count, 1_000)
                if let outputDirectory {
                    try png.write(
                        to: outputDirectory.appendingPathComponent(
                            "tibo-\(languageName)-\(appearanceName).png"
                        )
                    )
                }

                let hoverPNG = try renderPNG(card)
                if let outputDirectory {
                    try hoverPNG.write(
                        to: outputDirectory.appendingPathComponent(
                            "tibo-\(languageName)-\(appearanceName)-hover.png"
                        )
                    )
                }
            }
        }
    }

    func testLongBankRowsStayInsideScrollableViewport() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: longBankSnapshot,
            tokenUsage: tokenUsageSnapshot,
            now: now,
            language: .english,
            timeZone: timeZone
        )
        let rowHeights = Array(
            repeating: QuotaDetailLayout.rowHeight,
            count: content.rows.count
        )
        let card = QuotaDetailCardView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: QuotaDetailLayout.width,
                height: referenceCardHeight
            ),
            content: content,
            rowHeights: rowHeights,
            version: "0.3.3",
            onOpenURL: { _ in }
        )
        card.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(
            descendants(of: card)
                .compactMap { $0 as? NSScrollView }
                .first { $0.hasVerticalScroller }
        )
        let rowDocument = try XCTUnwrap(scrollView.documentView)
        let rightmostTextEdge = try XCTUnwrap(
            rowDocument.subviews
                .compactMap { ($0 as? NSTextField)?.frame.maxX }
                .max()
        )

        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertEqual(
            rowDocument.frame.width,
            scrollView.contentSize.width,
            accuracy: 0.5
        )
        XCTAssertLessThanOrEqual(
            rightmostTextEdge,
            scrollView.contentSize.width
        )
    }

    func testResetAndBankRowsShareTypographyButUseIndependentSemanticColors() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: longBankSnapshot,
            tokenUsage: tokenUsageSnapshot,
            now: now,
            language: .english,
            timeZone: timeZone
        )
        let rowHeights = Array(
            repeating: QuotaDetailLayout.rowHeight,
            count: content.rows.count
        )
        let card = QuotaDetailCardView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: QuotaDetailLayout.width,
                height: referenceCardHeight
            ),
            content: content,
            rowHeights: rowHeights,
            version: "0.3.3",
            onOpenURL: { _ in }
        )

        let resetValue = try XCTUnwrap(
            content.rows.first { $0.label == "Next reset (5 hours)" }?.value
        )
        let bankValue = try XCTUnwrap(
            content.rows.first { $0.label == "Bank 1 expires" }?.value
        )
        let resetField = try XCTUnwrap(
            descendants(of: card)
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == resetValue }
        )
        let bankField = try XCTUnwrap(
            descendants(of: card)
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == bankValue }
        )
        let resetDigitsRange = try XCTUnwrap(
            (resetValue as NSString).range(of: "1d").nonEmpty
        )
        let bankDigitsRange = try XCTUnwrap(
            (bankValue as NSString).range(of: "2d 6h").nonEmpty
        )

        let resetFont = try XCTUnwrap(
            resetField.attributedStringValue.attribute(
                .font,
                at: resetDigitsRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        let bankFont = try XCTUnwrap(
            bankField.attributedStringValue.attribute(
                .font,
                at: bankDigitsRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        let resetColor = try XCTUnwrap(
            resetField.attributedStringValue.attribute(
                .foregroundColor,
                at: resetDigitsRange.location,
                effectiveRange: nil
            ) as? NSColor
        )
        let bankColor = try XCTUnwrap(
            bankField.attributedStringValue.attribute(
                .foregroundColor,
                at: bankDigitsRange.location,
                effectiveRange: nil
            ) as? NSColor
        )

        let weeklyResetValue = try XCTUnwrap(
            content.rows.first { $0.label == "Next reset (7 days)" }?.value
        )
        let weeklyResetField = try XCTUnwrap(
            descendants(of: card)
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == weeklyResetValue }
        )
        let weeklyDigitsRange = try XCTUnwrap(
            (weeklyResetValue as NSString).range(of: "7d").nonEmpty
        )
        let weeklyColor = try XCTUnwrap(
            weeklyResetField.attributedStringValue.attribute(
                .foregroundColor,
                at: weeklyDigitsRange.location,
                effectiveRange: nil
            ) as? NSColor
        )

        XCTAssertEqual(resetFont, bankFont)
        XCTAssertEqual(
            bankColor.usingColorSpace(.deviceRGB),
            QuotaColorScale.components(remainingPercent: 10)
                .appKitColor
                .usingColorSpace(.deviceRGB)
        )
        let bankDateRange = try XCTUnwrap(
            (bankValue as NSString).range(of: "2026/").nonEmpty
        )
        let bankDateFont = try XCTUnwrap(
            bankField.attributedStringValue.attribute(
                .font, at: bankDateRange.location, effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertGreaterThan(bankFont.pointSize, bankDateFont.pointSize)
        XCTAssertEqual(
            resetColor.usingColorSpace(.deviceRGB),
            QuotaColorScale.components(remainingPercent: 32)
                .appKitColor
                .usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(
            weeklyColor.usingColorSpace(.deviceRGB),
            QuotaColorScale.components(remainingPercent: 80)
                .appKitColor
                .usingColorSpace(.deviceRGB)
        )
    }

    func testDualQuotaHeaderPlacesEachLabelAndPercentOnOneLine() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: longBankSnapshot,
            now: now,
            language: .english,
            timeZone: timeZone
        )
        let card = QuotaDetailCardView(
            frame: CGRect(x: 0, y: 0, width: QuotaDetailLayout.width, height: 420),
            content: content,
            rowHeights: Array(repeating: QuotaDetailLayout.rowHeight, count: content.rows.count),
            version: "0.3.3",
            onOpenURL: { _ in }
        )
        let fields = descendants(of: card).compactMap { $0 as? NSTextField }
        let primaryLabel = try XCTUnwrap(fields.first { $0.stringValue == "5 hours" })
        let primaryPercent = try XCTUnwrap(fields.first { $0.stringValue == "32%" })
        let weeklyLabel = try XCTUnwrap(fields.first { $0.stringValue == "7 days" })
        let weeklyPercent = try XCTUnwrap(fields.first { $0.stringValue == "80%" })

        XCTAssertEqual(primaryLabel.frame.midY, primaryPercent.frame.midY)
        XCTAssertEqual(weeklyLabel.frame.midY, weeklyPercent.frame.midY)
        XCTAssertEqual(primaryPercent.alignment, .right)
        XCTAssertEqual(weeklyPercent.alignment, .right)
        XCTAssertEqual(primaryPercent.font?.pointSize, weeklyPercent.font?.pointSize)
    }

    func testNarrowPanelMeasuresWrappedRowsUsingClampedCardWidth() {
        let content = QuotaDetailContent(
            title: "Codex usage",
            remainingPercent: 32,
            informationEntry: QuotaInformationEntry(
                title: "Tibo on X",
                accessibilityLabel: "Tibo on X",
                destination: URL(string: "https://x.com/thsottiaux")!
            ),
            rows: [
                QuotaDetailRow(
                    label: "Reset window",
                    value: String(repeating: "1234567890", count: 5)
                )
            ]
        )
        let layout = QuotaDetailPanelResolvedLayout.resolve(
            content: content,
            indicatorFrame: CGRect(x: 460, y: 700, width: 30, height: 30),
            visibleFrame: CGRect(x: 100, y: 100, width: 400, height: 800)
        )

        XCTAssertEqual(layout.frame.width, 360)
        XCTAssertGreaterThan(
            layout.rowHeights[0],
            QuotaDetailLayout.rowHeight
        )
    }

    func testResolvedPanelLayoutRetainsTheRequestedResizeHeight() {
        let content = QuotaDetailContent(
            title: "Codex usage",
            remainingPercent: 32,
            informationEntry: QuotaInformationEntry(
                title: "Tibo on X",
                accessibilityLabel: "Tibo on X",
                destination: URL(string: "https://x.com/thsottiaux")!
            ),
            rows: [
                QuotaDetailRow(label: "Plan", value: "Plus")
            ]
        )
        let indicator = CGRect(x: 300, y: 760, width: 164, height: 46)
        let layout = QuotaDetailPanelResolvedLayout.resolve(
            content: content,
            indicatorFrame: indicator,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            requestedHeight: 680
        )

        XCTAssertEqual(layout.frame.height, 680)
        XCTAssertEqual(
            layout.frame.maxY,
            indicator.minY - QuotaDetailLayout.controlGap
        )
    }

    func testCardMaterialResolvesAThemeShadow() {
        let material = QuotaCardMaterialView(frame: CGRect(x: 0, y: 0, width: 520, height: 680))

        XCTAssertEqual(material.shadowOpacity(for: .aqua), 0.03, accuracy: 0.001)
        XCTAssertEqual(material.shadowOpacity(for: .darkAqua), 0.08, accuracy: 0.001)
    }

    func testLightCardMaterialRendersAnOpaquePureWhiteSurface() throws {
        let material = QuotaCardMaterialView(
            frame: CGRect(x: 0, y: 0, width: 120, height: 120)
        )
        material.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let representation = try XCTUnwrap(
            material.bitmapImageRepForCachingDisplay(in: material.bounds)
        )

        material.cacheDisplay(in: material.bounds, to: representation)

        let center = try XCTUnwrap(
            representation.colorAt(x: 60, y: 60)?.usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(center.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(center.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(center.blueComponent, 1, accuracy: 0.001)
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.001)
    }

    func testResizeHandleUsesExpandedHitAreaAndGrowsTheScrollableRegion() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: longBankSnapshot,
            tokenUsage: tokenUsageSnapshot,
            footerName: "demo@example.com",
            now: now,
            language: .simplifiedChinese,
            timeZone: timeZone
        )
        let card = QuotaDetailCardView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: QuotaDetailLayout.width,
                height: referenceCardHeight
            ),
            content: content,
            rowHeights: Array(
                repeating: QuotaDetailLayout.rowHeight,
                count: content.rows.count
            ),
            version: "0.3.3",
            onOpenURL: { _ in }
        )
        card.layoutSubtreeIfNeeded()

        let handle = try XCTUnwrap(
            descendants(of: card).first {
                $0.accessibilityRole() == .slider
            }
        )
        let scrollView = try XCTUnwrap(
            descendants(of: card).compactMap { $0 as? NSScrollView }.first
        )
        let initialScrollHeight = scrollView.frame.height

        XCTAssertEqual(handle.frame.width, 44)
        XCTAssertEqual(handle.frame.height, 14)
        XCTAssertEqual(handle.accessibilityLabel(), "调整高度")

        card.setFrameSize(NSSize(
            width: QuotaDetailLayout.width,
            height: referenceCardHeight + 120
        ))
        card.layoutSubtreeIfNeeded()

        XCTAssertEqual(scrollView.frame.height, initialScrollHeight + 120)
    }

    func testResizeHintAppearsOnHoverAndHidesWhenThePointerLeaves() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: longBankSnapshot,
            tokenUsage: tokenUsageSnapshot,
            footerName: "demo@example.com",
            now: now,
            language: .simplifiedChinese,
            timeZone: timeZone
        )
        let card = QuotaDetailCardView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: QuotaDetailLayout.width,
                height: referenceCardHeight
            ),
            content: content,
            rowHeights: Array(
                repeating: QuotaDetailLayout.rowHeight,
                count: content.rows.count
            ),
            version: "0.4.0",
            onOpenURL: { _ in }
        )
        let handle = try XCTUnwrap(
            descendants(of: card).first {
                $0.accessibilityRole() == .slider
            }
        )
        let hint = try XCTUnwrap(
            descendants(of: card).first {
                $0.isHidden && $0.frame.height == 22 && $0.frame.width >= 74
            }
        )
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )

        handle.mouseEntered(with: event)
        XCTAssertFalse(hint.isHidden)

        handle.mouseExited(with: event)
        XCTAssertTrue(hint.isHidden)
    }

    func testColdPanelInstallsCardAtFinalSizeBeforeSubviewAutoresizing() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: longBankSnapshot,
            tokenUsage: tokenUsageSnapshot,
            footerName: "demo@example.com",
            now: now,
            language: .simplifiedChinese,
            timeZone: timeZone
        )
        let layout = QuotaDetailPanelResolvedLayout.resolve(
            content: content,
            indicatorFrame: CGRect(x: 700, y: 760, width: 164, height: 46),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900)
        )
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let card = QuotaDetailCardView(
            frame: CGRect(origin: .zero, size: layout.frame.size),
            content: content,
            rowHeights: layout.rowHeights,
            version: "0.4.0",
            onOpenURL: { _ in }
        )

        QuotaDetailPanel.install(card, into: panel, frame: layout.frame)

        let scrollView = try XCTUnwrap(
            descendants(of: card)
                .compactMap { $0 as? NSScrollView }
                .first { $0.hasVerticalScroller }
        )
        let rowDocument = try XCTUnwrap(scrollView.documentView)
        let informationFrames = QuotaDetailLayout.informationFrames(
            in: card.bounds,
            tokenUsageVisible: true,
            secondaryQuotaVisible: true
        )

        XCTAssertEqual(card.frame.size, layout.frame.size)
        XCTAssertEqual(scrollView.frame, informationFrames.rowArea)
        XCTAssertEqual(
            rowDocument.frame.width,
            scrollView.contentSize.width,
            accuracy: 0.5
        )
    }

    func testChromeOutlinesUseTheSharedSeparatorStyle() {
        XCTAssertEqual(QuotaChromeStyle.separatorLineWidth, 1)
        XCTAssertEqual(QuotaChromeStyle.cardBorderLineWidth, 0)
        let color = QuotaChromeStyle.separatorColor
            .usingColorSpace(.deviceRGB)
        XCTAssertEqual(color?.alphaComponent ?? 0, 0.28, accuracy: 0.01)
    }

    func testUnavailableTokenUsageRendersSevenEmptyBarsAndItsUnavailableNote() throws {
        let content = QuotaDetailFormatter().content(
            snapshot: AllowanceSnapshot(
                usedPercent: 68,
                remainingPercent: 32,
                resetsAt: now.addingTimeInterval(86_400),
                receivedAt: now,
                windowDurationMins: 10_080
            ),
            tokenUsage: TokenUsageSnapshot(
                receivedAt: now,
                dailyBuckets: [],
                summary: nil,
                availability: .unavailable
            ),
            now: now,
            language: .english,
            timeZone: timeZone
        )
        let card = QuotaDetailCardView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: QuotaDetailLayout.width,
                height: referenceCardHeight
            ),
            content: content,
            rowHeights: Array(
                repeating: QuotaDetailLayout.rowHeight,
                count: content.rows.count
            ),
            version: "0.3.3",
            onOpenURL: { _ in }
        )
        card.layoutSubtreeIfNeeded()

        let tokenView = try XCTUnwrap(
            descendants(of: card)
                .compactMap { $0 as? QuotaTokenUsageView }
                .first
        )
        let bars = descendants(of: tokenView)
            .compactMap { $0 as? QuotaTokenUsageBarView }

        XCTAssertEqual(tokenView.barCount, 7)
        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(
            tokenView.accessibilityValue() as? String,
            "Current-period token usage is unavailable"
        )
        XCTAssertTrue(bars.allSatisfy { ($0.accessibilityValue() as? String) == "0" })
    }



    private var languages: [
        (CodexDisplayLanguage, String, String)
    ] {
        [
            (
                .simplifiedChinese,
                "zh-cn",
                "在浏览器中打开 Tibo 的 X 主页"
            ),
            (
                .traditionalChinese,
                "zh-tw",
                "在瀏覽器中開啟 Tibo 的 X 主頁"
            ),
            (
                .english,
                "en",
                "Open Tibo's X profile in the browser"
            )
        ]
    }

    private var appearances: [(String, NSAppearance)] {
        [
            ("light", NSAppearance(named: .aqua)!),
            ("dark", NSAppearance(named: .darkAqua)!)
        ]
    }

    private var longBankSnapshot: AllowanceSnapshot {
        AllowanceSnapshot(
            usedPercent: 68,
            remainingPercent: 32,
            resetsAt: now.addingTimeInterval(86_400),
            receivedAt: now.addingTimeInterval(-20),
            windowDurationMins: 300,
            planType: "plus",
            credits: CreditBalance(
                hasCredits: true,
                unlimited: false,
                balance: "12.50"
            ),
            bank: BankResetSummary(
                availableCount: 12,
                credits: (1 ... 12).map { index in
                    BankResetCredit(
                        status: "available",
                        grantedAt: now.addingTimeInterval(
                            -Double(index) * 86_400
                        ),
                        expiresAt: now.addingTimeInterval(
                            Double(index + 1) * 86_400 + 6 * 3_600
                        ),
                        title: "Full reset",
                        description: nil
                    )
                }
            ),
            secondary: QuotaWindowSnapshot(
                usedPercent: 20,
                remainingPercent: 80,
                resetsAt: now.addingTimeInterval(7 * 86_400),
                windowDurationMins: 10_080
            )
        )
    }

    private var tokenUsageSnapshot: TokenUsageSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        return TokenUsageSnapshot(
            receivedAt: now,
            dailyBuckets: (0 ..< 7).map { offset in
                TokenUsageDay(
                    date: calendar.date(
                        byAdding: .day,
                        value: offset - 6,
                        to: today
                    )!,
                    tokens: Int64(80_000 + offset * 40_000),
                    timeZone: timeZone
                )
            },
            summary: nil,
            availability: .available
        )
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func renderPNG(_ view: NSView) throws -> Data {
        let representation = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds)
        )
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
    }
}

private extension NSRange {
    var nonEmpty: NSRange? { location == NSNotFound || length == 0 ? nil : self }
}
