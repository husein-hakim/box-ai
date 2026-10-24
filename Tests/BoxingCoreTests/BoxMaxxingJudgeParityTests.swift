import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingJudgeParityTests {
    typealias J = BoxMaxxingJudge
    private struct Fixtures: Decodable {
        struct Timing: Decodable { let window: J.Window; let onsetMs: Double; let peakMs: Double; let expected: J.Outcome; let padState: J.PadState; let closed: Bool }
        struct Punch: Decodable { let event: J.Event; let window: J.Window; let expectedLimbs: [J.Limb]; let target: J.Target?; let expected: J.Result }
        struct Match: Decodable { let event: J.Event; let expectedKind: J.PunchKind; let minimumConfidence: Double; let lenient: Bool; let expected: Bool }
        struct Target: Decodable { let headLineY: Double; let expected: J.Target }
        let timing: [Timing]; let punch: [Punch]; let matches: [Match]; let targets: [Target]
    }
    @Test func judgmentsAgreeWithRawInstructionReplay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let f = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: root.appendingPathComponent("research/boxmaxxing/port/judge/fixtures.json")))
        for v in f.timing {
            #expect(J.timing(window: v.window, onsetMs: v.onsetMs, peakMs: v.peakMs) == v.expected)
            #expect(J.padState(window: v.window, atMs: v.peakMs) == v.padState)
            #expect(J.windowClosed(v.window, atMs: v.peakMs) == v.closed)
        }
        for v in f.punch { #expect(J.punch(v.event, window: v.window, expectedLimbs: v.expectedLimbs, target: v.target) == v.expected) }
        for v in f.matches { #expect(J.matchesStep(v.event, expectedKind: v.expectedKind, minimumConfidence: v.minimumConfidence, lenient: v.lenient) == v.expected) }
        for v in f.targets { #expect(J.straightTarget(headLineY: v.headLineY) == v.expected) }
    }
}
