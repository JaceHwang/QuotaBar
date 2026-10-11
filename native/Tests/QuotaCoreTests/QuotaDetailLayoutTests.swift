import CoreGraphics
import XCTest
@testable import QuotaCore

final class QuotaDetailLayoutTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

    func testCardOpensBelowHeaderIndicatorAndAlignsLeadingEdges() {
        let indicator = CGRect(x: 886, y: 1_026, width: 148, height: 46)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: indicator,
            rowCount: 6,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.width, 360)
        XCTAssertEqual(frame.minX, indicator.minX)
        XCTAssertEqual(frame.maxY, indicator.minY - 8)
    }

    func testCardMovesAboveIndicatorWhenThereIsNotEnoughRoomBelow() {
        let indicator = CGRect(x: 260, y: 100, width: 148, height: 46)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: indicator,
            rowCount: 6,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.minX, indicator.minX)
        XCTAssertEqual(frame.minY, indicator.maxY + QuotaDetailLayout.controlGap)
        XCTAssertGreaterThanOrEqual(frame.minY, indicator.maxY)
    }

    func testCardUsesIndicatorTrailingEdgeWhenLeadingAlignmentWouldOverflow() {
        let indicator = CGRect(x: 1_760, y: 900, width: 120, height: 46)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: indicator,
            rowCount: 3,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.maxX, indicator.maxX)
        XCTAssertFalse(frame.intersects(indicator))
    }

    func testReferenceGeometryOrdersHeaderTiboTokenBandAndScrollableRows() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 580)
        let header = QuotaDetailLayout.headerFrames(
            in: bounds,
            titleWidth: 180,
            versionBadgeWidth: 48
        )
        let information = QuotaDetailLayout.informationFrames(
            in: bounds,
            tokenUsageVisible: true
        )

        XCTAssertEqual(header.title.height, 22)
        XCTAssertGreaterThan(header.title.minY, information.topDivider.maxY)
        XCTAssertGreaterThan(header.remaining.minY, information.topDivider.maxY)
        XCTAssertLessThan(information.tokenBand.maxY, information.topDivider.minY)
        XCTAssertLessThan(information.rowArea.maxY, information.tokenBand.minY)
        XCTAssertGreaterThan(information.tokenDivider.minY, information.rowArea.maxY)
        XCTAssertGreaterThan(information.rowArea.minY, information.footer.maxY)
        XCTAssertEqual(information.tokenBand.width / 7, 46.3, accuracy: 0.5)
    }

    func testClampsCardToVisibleHorizontalMargins() {
        let nearRight = CGRect(x: 1_850, y: 900, width: 60, height: 46)
        let nearLeft = CGRect(x: -20, y: 900, width: 60, height: 46)
        let rightFrame = QuotaDetailLayout.frame(
            indicatorFrame: nearRight,
            rowCount: 1,
            visibleFrame: visibleFrame
        )
        let leftFrame = QuotaDetailLayout.frame(
            indicatorFrame: nearLeft,
            rowCount: 1,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(rightFrame.maxX, nearRight.maxX)
        XCTAssertEqual(leftFrame.minX, visibleFrame.minX + 8)
    }

    func testNarrowsReferenceCardOnlyWhenVisibleFrameCannotFitIt() {
        let visibleFrame = CGRect(x: 100, y: 100, width: 400, height: 800)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: CGRect(x: 460, y: 700, width: 30, height: 30),
            rowCount: 6,
            visibleFrame: visibleFrame,
            tokenUsageVisible: true
        )

        XCTAssertEqual(frame.width, 360)
        XCTAssertEqual(frame.minX, 130)
        XCTAssertEqual(frame.maxX, 490)
    }

    func testManyRowsHaveNoProductHeightCapButStillFitTheVisibleScreen() {
        XCTAssertEqual(QuotaDetailLayout.contentHeight(rowCount: 100), 3_374)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: CGRect(x: 205, y: 390, width: 148, height: 46),
            rowCount: 100,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 420)
        )

        XCTAssertEqual(frame.height, 374)
        XCTAssertEqual(frame.minY, 8)
    }

    func testUserRequestedHeightCanExceedTheFormerProductCap() {
        let indicator = CGRect(x: 300, y: 1_100, width: 164, height: 46)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: indicator,
            rowContentHeight: 360,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 1_200),
            tokenUsageVisible: true,
            secondaryQuotaVisible: true,
            requestedHeight: 900
        )

        XCTAssertEqual(frame.height, 900)
        XCTAssertEqual(frame.maxY, indicator.minY - QuotaDetailLayout.controlGap)
    }

    func testDefaultDualQuotaTokenViewportShowsEightRows() {
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: CGRect(x: 300, y: 760, width: 164, height: 46),
            rowContentHeight: QuotaDetailLayout.rowHeight,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            tokenUsageVisible: true,
            secondaryQuotaVisible: true
        )
        let frames = QuotaDetailLayout.informationFrames(
            in: CGRect(origin: .zero, size: frame.size),
            tokenUsageVisible: true,
            secondaryQuotaVisible: true
        )

        XCTAssertEqual(
            frames.rowArea.height,
            QuotaDetailLayout.rowHeight * 8
        )
    }

    func testUserRequestedHeightKeepsPopoverTopAnchoredAndClampsToUsableRange() {
        let indicator = CGRect(x: 300, y: 760, width: 164, height: 46)
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: indicator,
            rowContentHeight: 360,
            visibleFrame: visible,
            tokenUsageVisible: true,
            secondaryQuotaVisible: true,
            requestedHeight: 680
        )

        XCTAssertEqual(frame.width, QuotaDetailLayout.width)
        XCTAssertEqual(frame.height, 680)
        XCTAssertEqual(frame.maxY, indicator.minY - QuotaDetailLayout.controlGap)

        let minimum = QuotaDetailLayout.frame(
            indicatorFrame: indicator,
            rowContentHeight: 360,
            visibleFrame: visible,
            tokenUsageVisible: true,
            secondaryQuotaVisible: true,
            requestedHeight: 1
        )
        XCTAssertEqual(
            minimum.height,
            QuotaDetailLayout.minimumResizableHeight(
                tokenUsageVisible: true,
                secondaryQuotaVisible: true
            )
        )
    }

    func testAccountsForWrappedDetailRows() {
        XCTAssertEqual(QuotaDetailLayout.contentHeight(rowContentHeight: 210), 430)
        let frame = QuotaDetailLayout.frame(
            indicatorFrame: CGRect(x: 100, y: 600, width: 148, height: 46),
            rowContentHeight: 210,
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 700)
        )

        XCTAssertEqual(frame.height, 430)
    }

    func testInformationBandSeparatesProgressTiboTokenBandAndRows() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 580)
        let frames = QuotaDetailLayout.informationFrames(
            in: bounds,
            tokenUsageVisible: true
        )

        XCTAssertEqual(frames.topDivider.minY, 460)
        XCTAssertEqual(
            frames.tokenBand,
            CGRect(x: 18, y: 304, width: 324, height: 150)
        )
        XCTAssertEqual(frames.footer, CGRect(x: 0, y: 0, width: 360, height: 44))
        XCTAssertEqual(frames.footerDivider.minY, 44)
        XCTAssertEqual(frames.tokenDivider, CGRect(x: 18, y: 301, width: 324, height: 1))
        XCTAssertLessThan(frames.rowArea.maxY, frames.tokenBand.minY)
        XCTAssertGreaterThan(frames.rowArea.minY, frames.footer.maxY)
        XCTAssertTrue(bounds.contains(frames.tokenBand))
        XCTAssertTrue(bounds.contains(frames.rowArea))
    }

    func testTokenBandAddsFixedHeightWithoutChangingCardWidth() {
        XCTAssertEqual(
            QuotaDetailLayout.contentHeight(
                rowContentHeight: 240,
                tokenUsageVisible: true
            ),
            592
        )
        XCTAssertEqual(
            QuotaDetailLayout.contentHeight(
                rowContentHeight: 240,
                tokenUsageVisible: false
            ),
            430
        )
    }

    func testHeaderPlacesCompactVersionBadgeAfterAndAboveTitle() {
        let frames = QuotaDetailLayout.headerFrames(
            in: CGRect(x: 0, y: 0, width: 360, height: 300),
            titleWidth: 104,
            versionBadgeWidth: 48
        )

        XCTAssertEqual(frames.title, CGRect(x: 60, y: 258, width: 104, height: 22))
        XCTAssertEqual(frames.versionBadge, CGRect(x: 294, y: 258, width: 48, height: 22))
        XCTAssertEqual(frames.versionBadge.midY, frames.title.midY)
        XCTAssertLessThan(frames.remaining.maxY, frames.versionBadge.minY)
    }

    func testHeaderPlacesLockButtonImmediatelyBeforeVersionBadge() {
        let frames = QuotaDetailLayout.headerFrames(
            in: CGRect(x: 0, y: 0, width: 360, height: 300),
            titleWidth: 220,
            versionBadgeWidth: 48,
            lockButtonWidth: 26
        )

        XCTAssertEqual(frames.lockButton, CGRect(x: 262, y: 256, width: 26, height: 26))
        XCTAssertEqual(frames.versionBadge, CGRect(x: 294, y: 258, width: 48, height: 22))
        XCTAssertEqual(frames.lockButton.midY, frames.versionBadge.midY)
        XCTAssertLessThanOrEqual(frames.title.maxX, frames.lockButton.minX - 8)
    }

    func testCompactHeaderKeepsContentDividerCloseToProgressBar() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 580)
        let header = QuotaDetailLayout.headerFrames(
            in: bounds,
            titleWidth: 180,
            versionBadgeWidth: 48
        )
        let information = QuotaDetailLayout.informationFrames(
            in: bounds,
            tokenUsageVisible: true
        )

        XCTAssertLessThanOrEqual(
            header.progress.minY - information.topDivider.maxY,
            20
        )
    }

    func testDualQuotaHeaderStacksPrimaryAndSecondaryProgressBars() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 320)
        let header = QuotaDetailLayout.headerFrames(
            in: bounds,
            titleWidth: 180,
            versionBadgeWidth: 48,
            secondaryQuotaVisible: true
        )

        XCTAssertEqual(header.secondaryRemaining.height, 28)
        XCTAssertEqual(header.remaining.height, header.secondaryRemaining.height)
        XCTAssertEqual(header.primaryLabel.midY, header.remaining.midY)
        XCTAssertEqual(header.secondaryLabel.midY, header.secondaryRemaining.midY)
        XCTAssertGreaterThan(header.remaining.minX, header.primaryLabel.minX)
        XCTAssertGreaterThan(header.secondaryRemaining.minX, header.secondaryLabel.minX)
        XCTAssertLessThan(header.secondaryProgress.minY, header.progress.minY)
        XCTAssertLessThan(header.secondaryProgress.maxY, header.progress.minY)
        XCTAssertGreaterThanOrEqual(
            header.progress.minY - header.secondaryLabel.maxY,
            10,
            "The paired quota rows keep a visible breathing gap between the first bar and the second label."
        )
        XCTAssertLessThan(header.secondaryProgress.maxY, header.title.minY)
    }

    func testHeaderTruncatesLongTitleBeforeVersionAndRemaining() {
        let frames = QuotaDetailLayout.headerFrames(
            in: CGRect(x: 0, y: 0, width: 360, height: 300),
            titleWidth: 220,
            versionBadgeWidth: 52
        )

        XCTAssertEqual(frames.title.width, 220)
        XCTAssertEqual(frames.versionBadge.maxX, 342)
        XCTAssertEqual(frames.remaining.minX, 180)
    }

    func testLocalizedHeadersNeverOverlapBadgeOrPercentage() {
        for titleWidth in [82.0, 104.0, 132.0] {
            let frames = QuotaDetailLayout.headerFrames(
                in: CGRect(x: 0, y: 0, width: 360, height: 300),
                titleWidth: titleWidth,
                versionBadgeWidth: 42
            )

            XCTAssertLessThanOrEqual(frames.title.maxX, frames.versionBadge.minX)
            XCTAssertLessThanOrEqual(frames.versionBadge.maxX, 342)
            XCTAssertLessThan(frames.remaining.maxY, frames.title.minY)
        }
    }

    func testHeaderTitleMeasurementKeepsAppKitFittingAllowance() {
        XCTAssertEqual(
            QuotaDetailLayout.titleWidth(
                intrinsicWidth: 95.5,
                fittingWidth: 100
            ),
            100
        )
    }

    func testHoverBridgeCoversGapBelowIndicator() {
        let indicator = CGRect(x: 886, y: 1_026, width: 148, height: 46)
        let detail = CGRect(x: 886, y: 780, width: 220, height: 238)

        XCTAssertEqual(
            QuotaDetailLayout.hoverBridgeFrame(
                indicatorFrame: indicator,
                detailFrame: detail
            ),
            CGRect(x: 886, y: 1_018, width: 148, height: 8)
        )
    }
}
