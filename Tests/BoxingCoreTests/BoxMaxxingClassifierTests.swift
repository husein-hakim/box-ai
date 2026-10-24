import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingClassifierTests {
    private struct Fixture: Decodable {
        struct Vector: Decodable {
            let name: String; let input: [Double]; let logits: [Float]
            let probabilities: [Float]; let classIndex: Int
        }
        let embeddedMaxLogitError: Double; let vectors: [Vector]
    }
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    @Test func originalEmbeddedNumericalGatePasses() throws {
        let model = try BoxMaxxingClassifier.bundled()
        #expect(model.embeddedParityError <= 0.001)
        print("BoxMaxxing embedded max logit error: \(model.embeddedParityError)")
    }
    @Test func logitsProbabilitiesAndClassAgreeWithJavaScriptReference() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Recognition/classifier/fixtures.json")))
        let model = try BoxMaxxingClassifier.bundled()
        for vector in fixture.vectors {
            let actual = try model.classify(vector.input.map(Float.init))
            // Exact Float32 bit agreement, including exp's write-before-sum boundary.
            #expect(actual.logits.map(\.bitPattern) == vector.logits.map(\.bitPattern), "Logits: \(vector.name)")
            #expect(actual.probabilities.map(\.bitPattern) == vector.probabilities.map(\.bitPattern), "Probabilities: \(vector.name)")
            #expect(actual.classIndex == vector.classIndex)
        }
    }
    @Test func malformedOrNonfiniteInputAndWeightsFailClosed() throws {
        let model = try BoxMaxxingClassifier.bundled()
        #expect(throws: BoxMaxxingClassifier.Failure.self) { try model.classify([]) }
        #expect(throws: BoxMaxxingClassifier.Failure.self) { try model.classify(Array(repeating: .nan, count: 2040)) }
        let url = root.appendingPathComponent("ios/Boxing/Recognition/Resources/boxmaxxing-classifier.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["classes"] = BoxMaxxingClassifier.classes.reversed().map { $0 }
        #expect(throws: BoxMaxxingClassifier.Failure.self) { try BoxMaxxingClassifier(data: JSONSerialization.data(withJSONObject: object)) }
        object["classes"] = BoxMaxxingClassifier.classes
        var parity = try #require(object["parity"] as? [String: Any])
        parity["logits"] = Array(repeating: 100.0, count: 9); object["parity"] = parity
        #expect(throws: BoxMaxxingClassifier.Failure.self) { try BoxMaxxingClassifier(data: JSONSerialization.data(withJSONObject: object)) }
    }
}
