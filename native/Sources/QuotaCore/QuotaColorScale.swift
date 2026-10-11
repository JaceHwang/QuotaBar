import Foundation

public struct QuotaColorComponents: Equatable, Sendable {
    public let hue: Double
    public let saturation: Double
    public let brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }
}

public struct QuotaGradientStop: Equatable, Sendable {
    public let location: Double
    public let components: QuotaColorComponents

    public init(location: Double, components: QuotaColorComponents) {
        self.location = location
        self.components = components
    }
}

public enum QuotaColorScale {
    private static let green = QuotaColorComponents(
        hue: 0.36,
        saturation: 0.78,
        brightness: 0.82
    )
    private static let orange = QuotaColorComponents(
        hue: 0.078,
        saturation: 0.96,
        brightness: 1
    )
    private static let red = QuotaColorComponents(
        hue: 0,
        saturation: 0.86,
        brightness: 1
    )
    private static let criticalRed = QuotaColorComponents(
        hue: 0,
        saturation: 0.96,
        brightness: 0.76
    )

    public static let progressGradientStops = [
        QuotaGradientStop(location: 0, components: criticalRed),
        QuotaGradientStop(location: 0.10, components: red),
        QuotaGradientStop(location: 0.49, components: orange),
        QuotaGradientStop(location: 1, components: green),
    ]

    public static func components(
        remainingPercent: Int
    ) -> QuotaColorComponents {
        let value = Double(min(100, max(0, remainingPercent)))
        if value >= 49 {
            return interpolate(
                from: orange,
                to: green,
                progress: (value - 49) / 51
            )
        }
        if value >= 10 {
            return interpolate(
                from: red,
                to: orange,
                progress: (value - 10) / 39
            )
        }
        return interpolate(
            from: criticalRed,
            to: red,
            progress: value / 10
        )
    }

    private static func interpolate(
        from start: QuotaColorComponents,
        to end: QuotaColorComponents,
        progress: Double
    ) -> QuotaColorComponents {
        let amount = min(1, max(0, progress))
        return QuotaColorComponents(
            hue: start.hue + (end.hue - start.hue) * amount,
            saturation: start.saturation +
                (end.saturation - start.saturation) * amount,
            brightness: start.brightness +
                (end.brightness - start.brightness) * amount
        )
    }
}
