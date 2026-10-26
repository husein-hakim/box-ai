import Foundation
import Testing
@testable import BoxingCore

struct PadTargetingTests {
    private func pose(lead: PadPoint, at tMs: Double) -> PadReachPose {
        var points = [PadPoint?](repeating: nil, count: 17)
        points[5] = .init(x: 0.4, y: 0.4); points[6] = .init(x: 0.6, y: 0.4) // shoulders: centre (0.5, 0.4), scale 0.2
        points[9] = lead // orthodox lead hand = left wrist
        return .init(tMs: tMs, points: points, aspect: 1)
    }

    @Test func fistExtendsWristAlongTheForearm() {
        let fist = PadFist.point(wrist: .init(x: 0.5, y: 0.5), elbow: .init(x: 0.5, y: 0.6), aspect: 1)
        #expect(abs((fist?.y ?? 0) - 0.47) < 0.0001 && abs((fist?.x ?? 0) - 0.5) < 0.0001)
        #expect(PadFist.point(wrist: .init(x: 0.3, y: 0.3), elbow: nil, aspect: 1) == PadPoint(x: 0.3, y: 0.3))
        #expect(PadFist.point(wrist: nil, elbow: .init(x: 0.3, y: 0.3), aspect: 1) == nil)
    }

    @Test func padsStayInsideTheRecognizersHeadZoneEvenForAChestHeightReach() {
        var reach = PadReachCalibration(stance: .orthodox, hands: [.lead])
        let guardPoint = PadPoint(x: 0.44, y: 0.36), chestReach = PadPoint(x: 0.5, y: 0.52) // local y = +0.6, below the head zone
        var t = 0.0
        reach.start(at: t)
        func feed(_ point: PadPoint, for ms: Double) { let end = t + ms; while t < end { t += 50; reach.observe(pose(lead: point, at: t)) } }
        feed(guardPoint, for: 1200)
        #expect(reach.stage == .leadReach)
        feed(chestReach, for: 1900)
        #expect(reach.stage == .finalReturn)
        feed(guardPoint, for: 900)
        #expect(reach.stage == .ready)
        let target = try? #require(reach.target(id: UUID(), hand: .lead, generation: 1, level: .intermediate))
        guard let target else { return }
        let local = target.body.local(target.centre)
        let radius = target.radius / target.body.scale
        #expect(local.y + radius <= PadReachCalibration.headZoneLowerLimit + 0.0001)
        #expect(local.y + radius < 0.5) // never overlaps the recognizer's body zone
    }

    @Test func oneReliableSampleAtThePeakIsEnoughToJudgeAim() throws {
        var points = [PadPoint?](repeating: nil, count: 17)
        points[5] = .init(x: 0.4, y: 0.4); points[6] = .init(x: 0.6, y: 0.4)
        let body = try #require(PadBodyFrame(points: points, aspect: 1))
        let target = PadTargetDefinition(cueID: UUID(), calibrationID: UUID(), generation: 1, hand: .lead,
                                         centre: .init(x: 0.5, y: 0.35), origin: .init(x: 0.44, y: 0.36), radius: 0.05, body: body)
        let samples = [
            PadWristSample(tMs: 900, wrist: nil, body: body, reliable: false),
            PadWristSample(tMs: 1000, wrist: .init(x: 0.51, y: 0.35), body: body, reliable: true),
            PadWristSample(tMs: 1100, wrist: nil, body: body, reliable: false)
        ]
        let hit = PadTargetJudge.judge(target: target, peakMs: 1010, onsetMs: 800, samples: samples)
        #expect(hit.outcome == .reached)
        let far = [PadWristSample(tMs: 1000, wrist: .init(x: 0.5, y: 0.5), body: body, reliable: true)]
        #expect(PadTargetJudge.judge(target: target, peakMs: 1000, onsetMs: 800, samples: far).outcome == .missed)
        #expect(PadTargetJudge.judge(target: target, peakMs: 1000, onsetMs: 800, samples: []).outcome == .uncertain)
    }

    @Test func coachingExplainsRejectedPunchesFromRecognizerEvidence() {
        #expect(PadCoaching.message(rejected: nil, kind: .straight, zone: .body, peakY: 0.7) == "Punch higher, at head height.")
        #expect(PadCoaching.message(rejected: "too_small", kind: .straight, zone: .head, peakY: -0.4) == "Reach all the way out to the pad.")
        #expect(PadCoaching.message(rejected: "lateral", kind: .hook, zone: .head, peakY: -0.4)?.contains("hook") == true)
        #expect(PadCoaching.message(rejected: nil, kind: .straight, zone: .head, peakY: -0.48) == nil) // an accepted jab needs no correction
        #expect(PadCoaching.message(forRetryReason: "candidate_too_slow") == "Snap it out faster.")
        #expect(PadCoaching.message(forRetryReason: "body_arms") == nil)
    }
}
