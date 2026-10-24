import Foundation

/// BoxMaxxing 2.1.5 functions #27632–27635, offsets0x006abf1e–0x006abf86.
/// A recovered smoothing primitive; this does not substitute for the complete
/// landmark tracker, whose swap/weak-observation/scale logic must also agree.
struct BoxMaxxingOneEuro: Sendable {
    struct Configuration: Sendable {
        var minCutoffHz: Double
        var beta: Double
        var dCutoffHz: Double
        // DEFAULT_TRACKER, module#4771 literal offset62105.
        static let bundled = Configuration(minCutoffHz: 2.5, beta: 30, dCutoffHz: 4)
    }
    var configuration: Configuration
    private(set) var xHat: Double?
    private(set) var dxHat: Double = 0

    init(configuration: Configuration = .bundled) { self.configuration = configuration }

    static func alpha(cutoffHz: Double, dtS: Double) -> Double {
        1 / (1 + (1 / (2 * Double.pi * cutoffHz)) / dtS)
    }
    mutating func reset() { xHat = nil; dxHat = 0 }
    mutating func filter(_ value: Double, dtS: Double) -> Double {
        guard let previous = xHat else { xHat = value; dxHat = 0; return value }
        let derivative = (value - previous) / dtS
        let derivativeAlpha = Self.alpha(cutoffHz: configuration.dCutoffHz, dtS: dtS)
        dxHat = derivativeAlpha * derivative + (1 - derivativeAlpha) * dxHat
        let cutoff = configuration.minCutoffHz + configuration.beta * abs(dxHat)
        let valueAlpha = Self.alpha(cutoffHz: cutoff, dtS: dtS)
        let result = valueAlpha * value + (1 - valueAlpha) * previous
        xHat = result
        return result
    }
}
