import Foundation
import JavaScriptCore

/// Exact recovered local pipeline executed by a restricted instruction reference.
/// Own on a single processing queue. No networking, UI modules, simulated events or scores.
/// The temporal classifier is native Swift; remaining state machines retain original
/// bytecode control flow until a direct Swift port has independent numerical parity.
final class BoxMaxxingKernel {
    struct Input: Codable, Sendable {
        var tMs: Double
        var width: Double
        var height: Double
        var keypoints: [BoxMaxxingTracker.RawPoint?]
        var source: String
        var model: String
        var trackingGeneration: UInt64
        var mirrored: Bool = false
    }
    struct Presence: Decodable, Sendable {
        let inFrame: Bool
        let framing: String
        // Recovered presence policy ('upper' includes hips). Live jab/cross
        // supplies a separate, current-observation upper-body policy to the bridge.
        var supportsUpperBody: Bool { inFrame && framing != "none" }
    }
    struct Sample: Decodable, Sendable {
        let frame: BoxMaxxingTracker.Output
        let status: String
        let presence: Presence?
        let justCalibrated: Bool
        let punches: [BoxMaxxingJudge.Event]
        let trackingChanged: Bool
        let rawJSON: Data
        private enum CodingKeys: String, CodingKey { case frame, status, presence, justCalibrated, punches, trackingChanged }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frame = try c.decode(BoxMaxxingTracker.Output.self, forKey: .frame)
            status = try c.decode(String.self, forKey: .status)
            presence = try c.decodeIfPresent(Presence.self, forKey: .presence)
            justCalibrated = try c.decode(Bool.self, forKey: .justCalibrated)
            punches = try c.decode([BoxMaxxingJudge.Event].self, forKey: .punches)
            trackingChanged = try c.decode(Bool.self, forKey: .trackingChanged)
            rawJSON = Data()
        }
        private init(_ decoded: Sample, rawJSON: Data) {
            presence = decoded.presence
            frame = decoded.frame; status = decoded.status; justCalibrated = decoded.justCalibrated
            punches = decoded.punches; trackingChanged = decoded.trackingChanged; self.rawJSON = rawJSON
        }
        static func decode(_ data: Data) throws -> Self { Self(try JSONDecoder().decode(Self.self, from: data), rawJSON: data) }
    }
    enum Failure: Error { case resources, invalidFrame, runtime(String) }
    private let context: JSContext
    private let classifier: BoxMaxxingClassifier
    private var kernel: JSValue!
    private var lastException: String?

    init() throws {
        classifier = try .bundled()
        guard let context = JSContext() else { throw Failure.resources }
        self.context = context
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let scriptURL = bundle.url(forResource: "boxmaxxing-reference", withExtension: "js"),
              let payloadURL = bundle.url(forResource: "boxmaxxing-pipeline", withExtension: "json") else { throw Failure.resources }
        context.exceptionHandler = { [weak self] _, value in self?.lastException = value?.toString() ?? "Unknown JavaScript exception" }
        let classify: @convention(block) ([NSNumber]) -> [String: Any] = { [weak self] values in
            guard let self else { return ["error": "Classifier unavailable"] }
            do {
                let result = try self.classifier.classify(values.map { Float($0.doubleValue) })
                return ["cls": result.classification, "p": Double(result.confidence), "probs": result.probabilities.map(Double.init)]
            } catch { return ["error": "Classifier input rejected"] }
        }
        context.setObject(classify, forKeyedSubscript: "boxClassify" as NSString)
        context.evaluateScript(try String(contentsOf: scriptURL, encoding: .utf8), withSourceURL: scriptURL)
        try checkException()
        kernel = context.objectForKeyedSubscript("boxKernel")
        _ = try call("initialize", [try String(contentsOf: payloadURL, encoding: .utf8)])
    }
    func push(_ input: Input) throws -> Sample {
        guard input.tMs.isFinite, input.width.isFinite, input.height.isFinite,
              input.width > 0, input.height > 0, input.keypoints.count == 17,
              input.keypoints.allSatisfy({ $0.map { $0.x.isFinite && $0.y.isFinite && $0.score.isFinite } ?? true }) else { throw Failure.invalidFrame }
        return try pushJSON(JSONEncoder().encode(input))
    }
    /// Used by the parity harness; product callers must use validated Input above.
    func pushJSON(_ data: Data) throws -> Sample {
        guard let input = String(data: data, encoding: .utf8),
              let result = try call("push", [input]).toString(), let encoded = result.data(using: .utf8) else { throw Failure.invalidFrame }
        return try Sample.decode(encoded)
    }
    /// Restricted interface used by the parity harness and typed response bridge.
    func responseReference(_ method: String, arguments: Data) throws -> Data {
        guard let args = String(data: arguments, encoding: .utf8),
              let result = try call("judge", [method, args]).toString(), let data = result.data(using: .utf8) else { throw Failure.invalidFrame }
        return data
    }
    func reset() throws { _ = try call("reset", []); _ = try responseReference("reset", arguments: Data("[]".utf8)) }
    func setStance(_ stance: BoxMaxxingJudge.Stance) throws { _ = try call("setStance", [stance.rawValue]) }
    private func call(_ method: String, _ arguments: [Any]) throws -> JSValue {
        lastException = nil; context.exception = nil
        guard let result = kernel.invokeMethod(method, withArguments: arguments) else { throw Failure.runtime("Missing reference method") }
        try checkException()
        return result
    }
    private func checkException() throws {
        if let lastException { throw Failure.runtime(lastException) }
    }
}
