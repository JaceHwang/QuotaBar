import QuotaCore
import XCTest

final class QuotaColorScaleTests: XCTestCase {
    func testHitsRequestedGreenOrangeAndRedAnchors() {
        XCTAssertEqual(
            QuotaColorScale.components(remainingPercent: 100),
            QuotaColorComponents(
                hue: 0.36,
                saturation: 0.78,
                brightness: 0.82
            )
        )
        XCTAssertEqual(
            QuotaColorScale.components(remainingPercent: 49),
            QuotaColorComponents(
                hue: 0.078,
                saturation: 0.96,
                brightness: 1
            )
        )
        XCTAssertEqual(
            QuotaColorScale.components(remainingPercent: 10),
            QuotaColorComponents(
                hue: 0,
                saturation: 0.86,
                brightness: 1
            )
        )
    }

    func testProgressGradientStopsMatchRequestedPaletteLocations() {
        XCTAssertEqual(
            QuotaColorScale.progressGradientStops.map(\.location),
            [0, 0.10, 0.49, 1]
        )
        XCTAssertEqual(
            QuotaColorScale.progressGradientStops.map(\.components),
            [0, 10, 49, 100].map {
                QuotaColorScale.components(remainingPercent: $0)
            }
        )
    }

    func testHueChangesContinuouslyAcrossTheWholeTransition() {
        let hues = [100, 80, 60, 49, 30, 10].map {
            QuotaColorScale.components(remainingPercent: $0).hue
        }

        for pair in zip(hues, hues.dropFirst()) {
            XCTAssertGreaterThan(pair.0, pair.1)
        }
        XCTAssertNotEqual(
            QuotaColorScale.components(remainingPercent: 99),
            QuotaColorScale.components(remainingPercent: 100)
        )
        XCTAssertNotEqual(
            QuotaColorScale.components(remainingPercent: 48),
            QuotaColorScale.components(remainingPercent: 49)
        )
        XCTAssertNotEqual(
            QuotaColorScale.components(remainingPercent: 9),
            QuotaColorScale.components(remainingPercent: 10)
        )
    }

    func testClampsValuesOutsidePercentageRange() {
        XCTAssertEqual(
            QuotaColorScale.components(remainingPercent: 120),
            QuotaColorScale.components(remainingPercent: 100)
        )
        XCTAssertEqual(
            QuotaColorScale.components(remainingPercent: -5),
            QuotaColorScale.components(remainingPercent: 0)
        )
    }
}
