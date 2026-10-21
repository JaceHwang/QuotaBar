public struct QuotaDetailInteractionState: Equatable, Sendable {
    public private(set) var isPinned = false
    public private(set) var isLockedOpen = false
    private var isPointerInside = false
    private var suppressHoverUntilExit = false

    public init() {}

    public var shouldShowDetail: Bool {
        isLockedOpen || isPinned || (isPointerInside && !suppressHoverUntilExit)
    }

    public mutating func updatePointerInside(_ inside: Bool) {
        if !inside {
            suppressHoverUntilExit = false
        }
        isPointerInside = inside
    }

    public mutating func togglePinned(pointerInside: Bool) {
        isPointerInside = pointerInside
        if isPinned {
            isPinned = false
            suppressHoverUntilExit = pointerInside
        } else {
            isPinned = true
            suppressHoverUntilExit = false
        }
    }

    public mutating func toggleLockedOpen(pointerInside: Bool) {
        isPointerInside = pointerInside
        if isLockedOpen {
            isLockedOpen = false
        } else {
            isLockedOpen = true
            isPinned = false
        }
        suppressHoverUntilExit = false
    }

    public mutating func dismissForOutsideInteraction() {
        isPinned = false
        isPointerInside = false
        suppressHoverUntilExit = false
    }

    public mutating func dismissForContextMenu() {
        isPinned = false; isLockedOpen = false
        isPointerInside = true; suppressHoverUntilExit = true
    }

    public mutating func reset() {
        self = QuotaDetailInteractionState()
    }
}
