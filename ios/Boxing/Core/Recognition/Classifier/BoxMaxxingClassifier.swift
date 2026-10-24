import Foundation

/// Reference port of shipped Hermes functions 28403/28407–28409.
/// Numerical agreement does not establish recognition accuracy. This is not a punch-event detector.
struct BoxMaxxingClassifier: Sendable {
    static let classes = ["none", "straight_left", "straight_right", "hook_left", "hook_right",
                          "uppercut_left", "uppercut_right", "slip", "duck"]
    static let version = "clf-0.3.4-noupper+mask(face,lower)"
    struct Output: Sendable {
        let logits: [Float]
        let probabilities: [Float]
        let classIndex: Int
        var classification: String { BoxMaxxingClassifier.classes[classIndex] }
        var confidence: Float { probabilities[classIndex] }
    }
    enum Failure: Error { case missingWeights, invalidContract, invalidInput, parityFailed(Double) }
    struct Parity: Decodable, Sendable { let input: [Double]; let logits: [Double] }
    private struct Layer: Decodable, Sendable {
        let type: String
        let convolution: [[[Double]]]?
        let linear: [[Double]]?
        let b: [Double]
        enum CodingKeys: String, CodingKey { case type, w, b }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            b = try c.decode([Double].self, forKey: .b)
            if type == "conv1d" {
                convolution = try c.decode([[[Double]]].self, forKey: .w); linear = nil
            } else {
                convolution = nil; linear = try c.decode([[Double]].self, forKey: .w)
            }
        }
    }
    private struct Weights: Decodable, Sendable {
        let version: String; let t: Int; let f: Int; let classes: [String]
        let layers: [Layer]; let parity: Parity
    }
    private let weights: Weights
    let embeddedParityError: Double

    static func bundled() throws -> Self {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "boxmaxxing-classifier", withExtension: "json") else {
            throw Failure.missingWeights
        }
        return try Self(data: Data(contentsOf: url))
    }

    init(data: Data) throws {
        let w = try JSONDecoder().decode(Weights.self, from: data)
        guard w.version == Self.version, w.t == 24, w.f == 85, w.classes == Self.classes,
              w.layers.map(\.type) == ["conv1d", "conv1d", "linear"],
              w.parity.input.count == 24 * 85, w.parity.logits.count == 9,
              w.parity.input.allSatisfy(\.isFinite), w.parity.logits.allSatisfy(\.isFinite) else {
            throw Failure.invalidContract
        }
        for (index, inputChannels) in [85, 32].enumerated() {
            let layer = w.layers[index]
            guard let conv = layer.convolution, conv.count == 32, layer.b.count == 32,
                  layer.b.allSatisfy(\.isFinite), conv.allSatisfy({ channels in
                      channels.count == inputChannels && channels.allSatisfy {
                          $0.count == 5 && $0.allSatisfy(\.isFinite)
                      }
                  }) else { throw Failure.invalidContract }
        }
        guard let linear = w.layers[2].linear, linear.count == 9, w.layers[2].b.count == 9,
              w.layers[2].b.allSatisfy(\.isFinite),
              linear.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isFinite) }) else {
            throw Failure.invalidContract
        }
        weights = w
        let result = Self.logits(w.parity.input.map(Float.init), weights: w)
        let error = zip(result, w.parity.logits).map { abs(Double($0) - $1) }.max() ?? .infinity
        guard error.isFinite, error <= 0.001 else { throw Failure.parityFailed(error) }
        embeddedParityError = error
    }

    func classify(_ input: [Float]) throws -> Output {
        guard input.count == 24 * 85, input.allSatisfy(\.isFinite) else { throw Failure.invalidInput }
        let logits = Self.logits(input, weights: weights)
        let peak = Double(logits.max()!)
        // Preserve original Float32Array writes before summing/normalizing the exponents.
        var probabilities = logits.map { Float(exp(Double($0) - peak)) }
        let denominator = probabilities.reduce(0.0) { $0 + Double($1) }
        var best = 0
        for i in probabilities.indices {
            probabilities[i] = Float(Double(probabilities[i]) / denominator)
            if probabilities[i] > probabilities[best] { best = i }
        }
        return Output(logits: logits, probabilities: probabilities, classIndex: best)
    }

    private static func logits(_ input: [Float], weights: Weights) -> [Float] {
        var x = input
        var inputChannels = weights.f
        for layer in weights.layers {
            if let kernels = layer.convolution {
                let outputChannels = kernels.count
                let kernelSize = kernels[0][0].count
                let padding = (kernelSize - 1) >> 1
                var output = [Float](repeating: 0, count: weights.t * outputChannels)
                for oc in 0..<outputChannels {
                    for time in 0..<weights.t {
                        // JS Number accumulates in Double; Float32Array rounds once per output.
                        var sum = layer.b[oc]
                        for ic in 0..<inputChannels {
                            for k in 0..<kernelSize {
                                let sourceTime = time + k - padding
                                if sourceTime >= 0 && sourceTime < weights.t {
                                    let product = kernels[oc][ic][k] * Double(x[sourceTime * inputChannels + ic])
                                    sum = sum + product
                                }
                            }
                        }
                        output[time * outputChannels + oc] = Float(sum > 0 ? sum : 0)
                    }
                }
                x = output; inputChannels = outputChannels
            } else if let rows = layer.linear {
                var pooled = [Float](repeating: 0, count: inputChannels * 2)
                for channel in 0..<inputChannels {
                    var sum = 0.0
                    var maximum = -Double.infinity
                    for time in 0..<weights.t {
                        let value = Double(x[time * inputChannels + channel])
                        sum += value
                        if value > maximum { maximum = value }
                    }
                    pooled[channel] = Float(sum / Double(weights.t))
                    pooled[inputChannels + channel] = Float(maximum)
                }
                return rows.enumerated().map { index, row in
                    var sum = layer.b[index]
                    for i in row.indices {
                        let product = row[i] * Double(pooled[i])
                        sum = sum + product
                    }
                    return Float(sum)
                }
            }
        }
        preconditionFailure("Validated weights must have a linear layer")
    }
}
