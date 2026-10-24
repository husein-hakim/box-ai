import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingKernelTests {
    @Test func completeReferencePipelineAgreesAcrossNodeAndNativeJavaScriptCore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("research/boxmaxxing/port/pipeline/fixtures.json"))
        let fixture = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inputs = try #require(fixture["inputs"] as? [[String: Any]])
        let expected = try #require(fixture["outputs"] as? [[String: Any]])
        let kernel = try BoxMaxxingKernel(); try kernel.setStance(.orthodox)
        var punchCount = 0, calibrationCount = 0
        for (input, expected) in zip(inputs, expected) {
            let actual = try kernel.pushJSON(JSONSerialization.data(withJSONObject: input))
            let expectedData = try JSONSerialization.data(withJSONObject: expected)
            let typed = try BoxMaxxingKernel.Sample.decode(expectedData)
            #expect(actual.status == typed.status && actual.justCalibrated == typed.justCalibrated && actual.trackingChanged == typed.trackingChanged)
            #expect(actual.punches == typed.punches)
            let actualJSON = try JSONSerialization.jsonObject(with: actual.rawJSON)
            #expect(numericalJSONEqual(actualJSON, expected), "Full pipeline @ \(input["tMs"] ?? "unknown")")
            punchCount += actual.punches.count; calibrationCount += actual.justCalibrated ? 1 : 0
        }
        #expect(calibrationCount == 1 && punchCount == 3)
        try kernel.reset()
        let first = try kernel.pushJSON(JSONSerialization.data(withJSONObject: inputs[0]))
        #expect(!first.justCalibrated && first.punches.isEmpty)
    }
    @Test func responseStateMachineAgreesAcrossNativeAndReference() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("research/boxmaxxing/port/judge/step-fixtures.json"))
        let fixture = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        for sequence in cases {
            let kernel = try BoxMaxxingKernel()
            let commands = try #require(sequence["commands"] as? [[String: Any]])
            for row in commands {
                let method = try #require(row["method"] as? String)
                let args = try #require(row["args"] as? [Any])
                let result = try kernel.responseReference(method, arguments: JSONSerialization.data(withJSONObject: args))
                let actual = try JSONSerialization.jsonObject(with: result, options: [.fragmentsAllowed])
                #expect(numericalJSONEqual(actual, row["expected"]!), "Response sequence: \(sequence["name"] ?? "unknown") / \(method)")
            }
        }
    }

    private func numericalJSONEqual(_ actual: Any, _ expected: Any) -> Bool {
        if let a = actual as? [String: Any], let b = expected as? [String: Any] {
            return Set(a.keys) == Set(b.keys) && a.allSatisfy { key, value in numericalJSONEqual(value, b[key]!) }
        }
        if let a = actual as? [Any], let b = expected as? [Any] { return a.count == b.count && zip(a, b).allSatisfy(numericalJSONEqual) }
        if let a = actual as? NSNumber, let b = expected as? NSNumber { return abs(a.doubleValue - b.doubleValue) <= 1e-9 }
        if let a = actual as? String, let b = expected as? String { return a == b }
        return actual is NSNull && expected is NSNull
    }
}
