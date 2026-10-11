import CoreGraphics

public enum AttachedPanelLayout {
    public static func frame(
        indicatorFrame: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        screenMargin: CGFloat = 8,
        controlGap: CGFloat = 8
    ) -> CGRect {
        let width = min(
            max(0, panelSize.width),
            max(0, visibleFrame.width - screenMargin * 2)
        )
        let maximumPanelHeight = max(0, visibleFrame.height - screenMargin * 2)
        let desiredHeight = min(max(0, panelSize.height), maximumPanelHeight)
        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = visibleFrame.maxX - width - screenMargin
        let leadingX = indicatorFrame.minX
        let trailingX = indicatorFrame.maxX - width
        let x: CGFloat
        if leadingX >= minimumX, leadingX <= maximumX {
            x = leadingX
        } else if trailingX >= minimumX, trailingX <= maximumX {
            x = trailingX
        } else {
            x = min(maximumX, max(minimumX, leadingX))
        }

        let minimumY = visibleFrame.minY + screenMargin
        let maximumY = visibleFrame.maxY - screenMargin
        let belowAvailable = max(0, indicatorFrame.minY - controlGap - minimumY)
        let aboveAvailable = max(0, maximumY - indicatorFrame.maxY - controlGap)
        let placeBelow = belowAvailable >= desiredHeight || aboveAvailable == 0
        let sideAvailableHeight = placeBelow ? belowAvailable : aboveAvailable
        let height = min(desiredHeight, sideAvailableHeight)
        let y = placeBelow
            ? indicatorFrame.minY - controlGap - height
            : indicatorFrame.maxY + controlGap
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

