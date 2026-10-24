import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingJudgeTests {
    typealias Judge = BoxMaxxingJudge
    var window: Judge.Window { .init(tReadyMs: 1000, earlyGraceMs: 120, failMs: 1000, greenMs: 400, yellowMs: 300) }
    func event(limb: Judge.Limb = .left, onset: Double = 1100, peak: Double = 1300, wrist: Judge.Point = .init(x: 0, y: 0)) -> Judge.Event {
        .init(candidate: .init(limb: limb, kind: .straight, zone: .head, confidence: 0.8, tOnsetMs: onset, tPeakMs: peak, peakWrist: wrist))
    }
    @Test func timingBoundariesUseObservationTimes() {
        #expect(Judge.timing(window: window, onsetMs: 879, peakMs: 1300) == .early)
        #expect(Judge.timing(window: window, onsetMs: 880, peakMs: 1400) == .green)
        #expect(Judge.timing(window: window, onsetMs: 1000, peakMs: 1400.001) == .yellow)
        #expect(Judge.timing(window: window, onsetMs: 1000, peakMs: 1700) == .yellow)
        #expect(Judge.timing(window: window, onsetMs: 1000, peakMs: 1700.001) == .timeout)
        #expect(!Judge.windowClosed(window, atMs: 2000))
        #expect(Judge.windowClosed(window, atMs: 2000.001))
    }
    @Test func wrongHandPrecedesEarlyAndEarlyPrecedesTarget() {
        let target = Judge.straightTarget(headLineY: -0.85)
        let wrong = Judge.punch(event(limb: .right, onset: 0, peak: 0), window: window, expectedLimbs: [.left], target: target)
        #expect(wrong.outcome == .wrongHand && wrong.reactionMs == -1000 && wrong.hitMs == -1000)
        #expect(Judge.punch(event(onset: 0, peak: 1300, wrist: .init(x: 99, y: 99)), window: window, expectedLimbs: [.left], target: target).outcome == .early)
        #expect(Judge.punch(event(wrist: .init(x: 99, y: 99)), window: window, expectedLimbs: [.left], target: target).outcome == .timeout)
        #expect(target.contains(.init(x: -1.45, y: -2.45)))
        #expect(target.contains(.init(x: 1.45, y: 0.5)))
        #expect(!target.contains(.init(x: 1.45001, y: 0.5)))
    }
    @Test func displayWindowAndEventWindowAreDistinct() {
        var shortFail = window; shortFail.failMs = 100
        #expect(Judge.padState(window: shortFail, atMs: 1300) == .green)
        #expect(Judge.timing(window: shortFail, onsetMs: 1100, peakMs: 1300) == .timeout)
    }
    @Test func stanceAndConfidenceRemainIndependent() {
        #expect(Judge.limbs(hand: .lead, stance: .orthodox) == [.left])
        #expect(Judge.limbs(hand: .lead, stance: .southpaw) == [.right])
        #expect(Judge.limbs(hand: .rear, stance: .southpaw) == [.left])
        #expect(Judge.limbs(hand: nil, stance: .orthodox) == [.left, .right])
        var body = event(); body.candidate.zone = .body
        #expect(!Judge.matchesStep(body, expectedKind: .straight, minimumConfidence: 0.8, lenient: false))
        #expect(Judge.matchesStep(body, expectedKind: .hook, minimumConfidence: 0.8, lenient: true))
        #expect(!Judge.matchesStep(body, expectedKind: .hook, minimumConfidence: 0.8001, lenient: true))
    }
    @Test func classifierOnlyRefinesAnExistingCandidate() {
        var original = event(); original.rejected = "vertical"; original.candidate.direction = "vertical"
        let classification = Judge.Classification(cls: "straight_left", p: 0.7)
        #expect(Judge.apply(classification, to: original, policy: .bundled, bodyZoneMinY: 0.35).rejected == "vertical")
        let armed = Judge.apply(classification, to: original, policy: .armed, bodyZoneMinY: 0.35)
        #expect(armed.rejected == nil && armed.candidate.direction == "forward")
        #expect(armed.candidate.tOnsetMs == original.candidate.tOnsetMs)
        #expect(armed.candidate.tPeakMs == original.candidate.tPeakMs)
        var bilateral = original; bilateral.rejected = "bilateral"
        #expect(Judge.apply(classification, to: bilateral, policy: .armed, bodyZoneMinY: 0.35).rejected == "bilateral")
        var mixed = original; mixed.candidate.vetoes = ["vertical", "outside_zone"]
        #expect(Judge.apply(classification, to: mixed, policy: .armed, bodyZoneMinY: 0.35).rejected == "outside_zone")
        var low = classification; low.p = 0.59
        #expect(Judge.apply(low, to: original, policy: .armed, bodyZoneMinY: 0.35).rejected == "vertical")
        let wrongLimb = Judge.Classification(cls: "straight_right", p: 1)
        #expect(Judge.apply(wrongLimb, to: original, policy: .armed, bodyZoneMinY: 0.35).rejected == "vertical")
        var veto = Judge.ClassifierPolicy.bundled; veto.vetoNone = true
        #expect(Judge.apply(.init(cls: "none", p: 0.6), to: event(), policy: veto, bodyZoneMinY: 0.35).rejected == "classifier")
    }
    @Test func smoothingRetainsExactDoubleArithmeticAndReset() {
        var filter = BoxMaxxingOneEuro()
        #expect(filter.filter(0.25, dtS: 0.04) == 0.25)
        let first = filter.filter(0.5, dtS: 0.04)
        #expect(first > 0.25 && first < 0.5)
        #expect(filter.dxHat > 0)
        filter.reset()
        #expect(filter.xHat == nil && filter.dxHat == 0)
        #expect(filter.filter(-1, dtS: 0.04) == -1)
    }
}
