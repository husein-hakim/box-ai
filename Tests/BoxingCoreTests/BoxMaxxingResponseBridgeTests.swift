import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingResponseBridgeTests {
    private let step = BoxMaxxingResponseBridge.Step(id: "synthetic-jab", hand: .lead, targetReps: 1, timeoutMs: 1000, minConfidence: 0.6)
    private let window = BoxMaxxingJudge.Window(tReadyMs: 4600, earlyGraceMs: 120, failMs: 1000, greenMs: 400, yellowMs: 300)
    private func sample(atMs: Double? = nil) throws -> BoxMaxxingKernel.Sample {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("research/boxmaxxing/port/pipeline/fixtures.json"))
        let fixture = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outputs = try #require(fixture["outputs"] as? [[String: Any]])
        var output = outputs[100]
        if let atMs {
            var frame = try #require(output["frame"] as? [String: Any]); frame["tMs"] = atMs; output["frame"] = frame
        }
        return try .decode(JSONSerialization.data(withJSONObject: output))
    }
    @Test func requiresActualPresentationAndKeepsReferenceJudgment() throws {
        let bridge = BoxMaxxingResponseBridge(kernel: try .init())
        let (token, _) = try bridge.open(step, atMs: 4600, generation: 7)
        #expect(try bridge.observe(sample(), captureMs: 5000, deliveredMs: 5000, generation: 7, timingReliable: true) == .ignored)
        #expect(try bridge.presented(token, window: window))
        #expect(try !bridge.presented(token, window: window))
        let result = try bridge.observe(sample(), captureMs: 5000, deliveredMs: 5000, generation: 7, timingReliable: true)
        guard case let .judged(events) = result else { Issue.record("Expected recovered judge output"); return }
        let hit = try #require(events.first { $0.kind == "rep_ok" })
        #expect(hit.actionId == "left:4640" && hit.cueId == token.id.uuidString)
        #expect(hit.reactionMs == 40 && hit.latencyMs == 240 && hit.grade == "green")
        #expect(try bridge.summary().reps == 1)
        #expect(try bridge.observe(sample(), captureMs: 5000, deliveredMs: 5010, generation: 7, timingReliable: true) == .ignored)
    }
    @Test func pauseAndGenerationChangesRejectOldFramesAndRenderCallbacks() throws {
        let bridge = BoxMaxxingResponseBridge(kernel: try .init())
        let (old, _) = try bridge.open(step, atMs: 4600, generation: 7)
        #expect(try bridge.presented(old, window: window))
        try bridge.suspend(atMs: 4700)
        #expect(try !bridge.presented(old, window: window))
        #expect(try bridge.observe(sample(), captureMs: 5000, deliveredMs: 5010, generation: 7, timingReliable: true) == .ignored)
        let (fresh, _) = try bridge.open(step, atMs: 5100, generation: 8)
        var newWindow = window; newWindow.tReadyMs = 5100
        #expect(try bridge.presented(fresh, window: newWindow))
        #expect(try !bridge.presented(old, window: newWindow))
        #expect(try bridge.observe(sample(), captureMs: 5140, deliveredMs: 5150, generation: 7, timingReliable: true) == .ignored)
        // Even a stale action smuggled into a fresh-generation delivery is filtered
        // by original onset, rather than credited against the new visible cue.
        _ = try bridge.observe(sample(atMs: 5140), captureMs: 5140, deliveredMs: 5150, generation: 8, timingReliable: true)
        #expect(try bridge.summary().reps == 0)
    }
    @Test func uncertainClockIsSeparateFromWrongResponse() throws {
        let bridge = BoxMaxxingResponseBridge(kernel: try .init())
        let (token, _) = try bridge.open(step, atMs: 4600, generation: 7)
        #expect(try bridge.presented(token, window: window))
        #expect(try bridge.observe(sample(), captureMs: 5000, deliveredMs: 5000, generation: 7, timingReliable: false) == .timingUncertain)
        #expect(try bridge.tick(atMs: 6500).isEmpty)
        #expect(try bridge.observe(sample(), captureMs: 5000, deliveredMs: 5000, generation: 7, timingReliable: true) == .ignored)
        let result = try bridge.summary()
        #expect(result.reps == 0 && result.wrongHand == 0 && result.wrongKind == 0 && result.missed == 0)
        try bridge.reset()
        #expect(try bridge.observe(sample(), captureMs: 5040, deliveredMs: 5040, generation: 7, timingReliable: true) == .ignored)
    }
    @Test func nativeCloseRetainsOriginalAbortedAccounting() throws {
        let bridge = BoxMaxxingResponseBridge(kernel: try .init())
        _ = try bridge.open(step, atMs: 4600, generation: 7)
        _ = try bridge.close(atMs: 4800)
        #expect(try bridge.summary().aborted == 1)
    }
}
