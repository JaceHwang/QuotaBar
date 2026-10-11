import CoreGraphics

public struct QuotaDetailHeaderFrames: Equatable, Sendable {
    public let title: CGRect
    public let lockButton: CGRect
    public let versionBadge: CGRect
    public let primaryLabel: CGRect
    public let remaining: CGRect
    public let progress: CGRect
    public let secondaryLabel: CGRect
    public let secondaryRemaining: CGRect
    public let secondaryProgress: CGRect

    public init(
        title: CGRect,
        lockButton: CGRect = .zero,
        versionBadge: CGRect,
        primaryLabel: CGRect = .zero,
        remaining: CGRect,
        progress: CGRect,
        secondaryLabel: CGRect = .zero,
        secondaryRemaining: CGRect = .zero,
        secondaryProgress: CGRect = .zero
    ) {
        self.title = title
        self.lockButton = lockButton
        self.versionBadge = versionBadge
        self.primaryLabel = primaryLabel
        self.remaining = remaining
        self.progress = progress
        self.secondaryLabel = secondaryLabel
        self.secondaryRemaining = secondaryRemaining
        self.secondaryProgress = secondaryProgress
    }
}

public struct QuotaDetailInformationFrames: Equatable, Sendable {
    public let topDivider: CGRect
    public let tokenBand: CGRect
    public let tokenDivider: CGRect
    public let rowArea: CGRect
    public let footerDivider: CGRect
    public let footer: CGRect

    public init(
        topDivider: CGRect,
        tokenBand: CGRect,
        tokenDivider: CGRect,
        rowArea: CGRect,
        footerDivider: CGRect,
        footer: CGRect
    ) {
        self.topDivider = topDivider
        self.tokenBand = tokenBand
        self.tokenDivider = tokenDivider
        self.rowArea = rowArea
        self.footerDivider = footerDivider
        self.footer = footer
    }
}

public enum QuotaDetailLayout {
    /// Compact dimensions tuned to the native Codex popover scale.
    public static let width: CGFloat = 360
    public static let headerHeight: CGFloat = 120
    public static let dualQuotaHeaderHeight: CGFloat = 171
    public static let rowHeight: CGFloat = 32
    public static let verticalPadding: CGFloat = 16
    public static let screenMargin: CGFloat = 8
    public static let controlGap: CGFloat = 8
    public static let tokenBandHeight: CGFloat = 150
    public static let tokenBandGap: CGFloat = 6
    public static let tokenBandReservedHeight: CGFloat =
        tokenBandHeight + tokenBandGap * 2
    public static let contentHorizontalInset: CGFloat = 18
    public static let rowTopGap: CGFloat = 10
    public static let footerHeight: CGFloat = 44
    public static let minimumRowViewportHeight: CGFloat = rowHeight * 2
    /// The default table viewport mirrors eight native detail rows. Content
    /// shorter than that keeps the popover stable instead of collapsing.
    public static let defaultRowViewportHeight: CGFloat = rowHeight * 8

    public static func headerHeight(secondaryQuotaVisible: Bool) -> CGFloat {
        secondaryQuotaVisible ? dualQuotaHeaderHeight : headerHeight
    }

    public static func titleWidth(
        intrinsicWidth: CGFloat,
        fittingWidth: CGFloat
    ) -> CGFloat {
        ceil(max(0, max(intrinsicWidth, fittingWidth)))
    }

    public static func headerFrames(
        in bounds: CGRect,
        titleWidth: CGFloat,
        versionBadgeWidth: CGFloat,
        lockButtonWidth: CGFloat = 0,
        secondaryQuotaVisible: Bool = false
    ) -> QuotaDetailHeaderFrames {
        let badgeWidth = max(0, versionBadgeWidth)
        let resolvedLockButtonWidth = max(0, lockButtonWidth)
        let titleX = bounds.minX + contentHorizontalInset + 32 + 10
        let versionBadge = CGRect(
            x: bounds.maxX - contentHorizontalInset - badgeWidth,
            y: bounds.maxY - 42,
            width: badgeWidth,
            height: 22
        )
        let lockButton = resolvedLockButtonWidth > 0
            ? CGRect(
                x: versionBadge.minX - 6 - resolvedLockButtonWidth,
                y: versionBadge.midY - 13,
                width: resolvedLockButtonWidth,
                height: 26
            )
            : .zero
        let trailingControlMinX = resolvedLockButtonWidth > 0
            ? lockButton.minX
            : versionBadge.minX
        let maximumTitleWidth = max(
            0,
            trailingControlMinX - 8 - titleX
        )
        let title = CGRect(
            x: titleX,
            y: bounds.maxY - 42,
            width: min(max(0, titleWidth), maximumTitleWidth),
            height: 22
        )
        let quotaWidth = max(0, bounds.width - contentHorizontalInset * 2)
        let quotaLabelWidth = floor(quotaWidth * 0.5)
        let quotaValueX = bounds.minX + contentHorizontalInset + quotaLabelWidth
        let quotaValueWidth = max(0, quotaWidth - quotaLabelWidth)
        let primaryLabel = CGRect(
            x: bounds.minX + contentHorizontalInset,
            y: bounds.maxY - 82,
            width: quotaLabelWidth,
            height: 20
        )
        let remaining = CGRect(
            x: quotaValueX,
            y: bounds.maxY - 86,
            width: quotaValueWidth,
            height: 28
        )
        let progress = CGRect(
            x: bounds.minX + contentHorizontalInset,
            y: bounds.maxY - 99,
            width: quotaWidth,
            height: 6
        )
        let secondaryLabel = secondaryQuotaVisible
            ? CGRect(
                x: bounds.minX + contentHorizontalInset,
                y: bounds.maxY - 129,
                width: quotaLabelWidth,
                height: 20
            )
            : .zero
        let secondaryRemaining = secondaryQuotaVisible
            ? CGRect(
                x: quotaValueX,
                y: bounds.maxY - 133,
                width: quotaValueWidth,
                height: 28
            )
            : .zero
        let secondaryProgress = secondaryQuotaVisible
            ? CGRect(
                x: bounds.minX + contentHorizontalInset,
                y: bounds.maxY - 146,
                width: quotaWidth,
                height: 6
            )
            : .zero
        return QuotaDetailHeaderFrames(
            title: title,
            lockButton: lockButton,
            versionBadge: versionBadge,
            primaryLabel: primaryLabel,
            remaining: remaining,
            progress: progress,
            secondaryLabel: secondaryLabel,
            secondaryRemaining: secondaryRemaining,
            secondaryProgress: secondaryProgress
        )
    }

    public static func informationFrames(
        in bounds: CGRect,
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false
    ) -> QuotaDetailInformationFrames {
        let headerHeight = headerHeight(secondaryQuotaVisible: secondaryQuotaVisible)
        let tokenBand: CGRect
        if tokenUsageVisible {
            tokenBand = CGRect(
                x: bounds.minX + contentHorizontalInset,
                y: bounds.maxY - headerHeight - tokenBandGap - tokenBandHeight,
                width: max(0, bounds.width - contentHorizontalInset * 2),
                height: tokenBandHeight
            )
        } else {
            tokenBand = .zero
        }
        return QuotaDetailInformationFrames(
            topDivider: CGRect(
                x: bounds.minX,
                y: bounds.maxY - headerHeight,
                width: bounds.width,
                height: 1
            ),
            tokenBand: tokenBand,
            tokenDivider: tokenUsageVisible
                ? CGRect(
                    x: bounds.minX + contentHorizontalInset,
                    y: tokenBand.minY - tokenBandGap / 2,
                    width: max(0, bounds.width - contentHorizontalInset * 2),
                    height: 1
                )
                : .zero,
            rowArea: rowAreaFrame(
                in: bounds,
                tokenUsageVisible: tokenUsageVisible,
                secondaryQuotaVisible: secondaryQuotaVisible
            ),
            footerDivider: CGRect(
                x: bounds.minX,
                y: footerFrame(in: bounds).maxY,
                width: bounds.width,
                height: 1
            ),
            footer: footerFrame(in: bounds)
        )
    }

    public static func rowAreaFrame(
        in bounds: CGRect,
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false
    ) -> CGRect {
        let informationHeight = headerHeight(secondaryQuotaVisible: secondaryQuotaVisible)
        let reservedHeight = informationHeight + (
            tokenUsageVisible ? tokenBandReservedHeight : 0
        ) + footerHeight
        return CGRect(
            x: bounds.minX,
            y: bounds.minY + footerHeight + rowTopGap,
            width: bounds.width,
            height: max(0, bounds.height - rowTopGap - reservedHeight)
        )
    }

    public static func footerFrame(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: footerHeight
        )
    }

    public static func contentHeight(
        rowCount: Int,
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false
    ) -> CGFloat {
        contentHeight(
            rowContentHeight: CGFloat(max(0, rowCount)) * rowHeight,
            tokenUsageVisible: tokenUsageVisible,
            secondaryQuotaVisible: secondaryQuotaVisible
        )
    }

    public static func minimumResizableHeight(
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false
    ) -> CGFloat {
        headerHeight(secondaryQuotaVisible: secondaryQuotaVisible) +
            (tokenUsageVisible ? tokenBandReservedHeight : 0) +
            footerHeight + rowTopGap + minimumRowViewportHeight
    }

    public static func contentHeight(
        rowContentHeight: CGFloat,
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false
    ) -> CGFloat {
        headerHeight(secondaryQuotaVisible: secondaryQuotaVisible) + rowTopGap + max(
            defaultRowViewportHeight,
            max(0, rowContentHeight)
        ) +
            (tokenUsageVisible ? tokenBandReservedHeight : 0) + footerHeight
    }

    public static func frame(
        indicatorFrame: CGRect,
        rowCount: Int,
        visibleFrame: CGRect,
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false
    ) -> CGRect {
        frame(
            indicatorFrame: indicatorFrame,
            rowContentHeight: CGFloat(max(0, rowCount)) * rowHeight,
            visibleFrame: visibleFrame,
            tokenUsageVisible: tokenUsageVisible,
            secondaryQuotaVisible: secondaryQuotaVisible
        )
    }

    public static func frame(
        indicatorFrame: CGRect,
        rowContentHeight: CGFloat,
        visibleFrame: CGRect,
        tokenUsageVisible: Bool = false,
        secondaryQuotaVisible: Bool = false,
        requestedHeight: CGFloat? = nil
    ) -> CGRect {
        let availableHeight = max(0, visibleFrame.height - screenMargin * 2)
        let naturalHeight = contentHeight(
            rowContentHeight: rowContentHeight,
            tokenUsageVisible: tokenUsageVisible,
            secondaryQuotaVisible: secondaryQuotaVisible
        )
        let maximumHeight = availableHeight
        let minimumHeight = min(
            maximumHeight,
            minimumResizableHeight(
                tokenUsageVisible: tokenUsageVisible,
                secondaryQuotaVisible: secondaryQuotaVisible
            )
        )
        let desiredHeight = min(
            maximumHeight,
            max(minimumHeight, requestedHeight ?? naturalHeight)
        )
        let cardWidth = min(
            width,
            max(0, visibleFrame.width - screenMargin * 2)
        )
        return AttachedPanelLayout.frame(
            indicatorFrame: indicatorFrame,
            panelSize: CGSize(width: cardWidth, height: desiredHeight),
            visibleFrame: visibleFrame,
            screenMargin: screenMargin,
            controlGap: controlGap
        )
    }

    public static func hoverBridgeFrame(
        indicatorFrame: CGRect,
        detailFrame: CGRect
    ) -> CGRect {
        let minimumX = max(indicatorFrame.minX, detailFrame.minX)
        let maximumX = min(indicatorFrame.maxX, detailFrame.maxX)
        guard maximumX > minimumX else {
            return .null
        }

        if detailFrame.minY >= indicatorFrame.maxY {
            return CGRect(
                x: minimumX,
                y: indicatorFrame.maxY,
                width: maximumX - minimumX,
                height: detailFrame.minY - indicatorFrame.maxY
            )
        }
        if indicatorFrame.minY >= detailFrame.maxY {
            return CGRect(
                x: minimumX,
                y: detailFrame.maxY,
                width: maximumX - minimumX,
                height: indicatorFrame.minY - detailFrame.maxY
            )
        }
        return .null
    }
}
