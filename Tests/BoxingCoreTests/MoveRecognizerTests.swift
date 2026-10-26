import Foundation
import Testing
@testable import BoxingCore

struct MoveRecognizerTests {
    typealias P = SyntheticFighter.P
    static let upper = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    /// Runs a synthetic sequence through the native recogniser (optionally mirrored
    /// like a real front camera) and returns the actions it reported.
    func detect(mirrored: Bool = false, _ build: (inout SyntheticFighter) -> Void) -> [FightAction] {
        var fighter = SyntheticFighter()
        fighter.hold(1600)
        build(&fighter)
        fighter.hold(800)
        var recognizer = MoveRecognizer()
        var found: [FightAction] = []
        for frame in fighter.frames {
            let keypoints = frame["keypoints"] as! [[String: Any]]
            let points: [PadPoint?] = keypoints.map { k in
                let x = k["x"] as! Double, y = k["y"] as! Double
                return PadPoint(x: mirrored ? 1 - x : x, y: y)
            }
            found += recognizer.push(.init(tMs: frame["tMs"] as! Double, points: points, aspect: 640.0 / 480.0)).map(\.action)
        }
        return found
    }

    // Keyframes. In these fixtures the fighter's LEFT shoulder (joint 5) is on image-left.
    static let leftHook: [[Int: P]] = [[7: (0.30, 0.31), 9: (0.30, 0.24)], [7: (0.31, 0.29), 9: (0.42, 0.22)], [7: (0.38, 0.29), 9: (0.52, 0.22)]]
    static let rightHook: [[Int: P]] = [[8: (0.70, 0.31), 10: (0.70, 0.24)], [8: (0.69, 0.29), 10: (0.58, 0.22)], [8: (0.62, 0.29), 10: (0.48, 0.22)]]
    static let leftUpper: [[Int: P]] = [[7: (0.38, 0.50), 9: (0.42, 0.40)], [7: (0.40, 0.45), 9: (0.44, 0.24)], [7: (0.41, 0.40), 9: (0.45, 0.16)]]
    static let rightUpper: [[Int: P]] = [[8: (0.62, 0.50), 10: (0.58, 0.40)], [8: (0.60, 0.45), 10: (0.56, 0.24)], [8: (0.59, 0.40), 10: (0.55, 0.16)]]
    static let jab: [[Int: P]] = [[7: (0.30, 0.38), 9: (0.25, 0.20)], [7: (0.24, 0.33), 9: (0.18, 0.17)]]
    /// Lean: head travels further than the shoulders and the shoulder line tilts.
    static func slip(towardImageLeft: Bool) -> [[Int: P]] {
        let s = towardImageLeft ? -1.0 : 1.0
        var pose = SyntheticFighter.shifted(dx: s * 0.06, dy: 0.01, joints: upper)
        for head in [0, 1, 2, 3, 4] { pose[head] = (SyntheticFighter.guardPose[head]!.x + s * 0.11, SyntheticFighter.guardPose[head]!.y + 0.02) }
        pose[towardImageLeft ? 5 : 6] = (pose[towardImageLeft ? 5 : 6]!.x, pose[towardImageLeft ? 5 : 6]!.y + 0.025)
        return [pose]
    }
    static let duck: [[Int: P]] = [SyntheticFighter.shifted(dx: 0, dy: 0.16, joints: upper)]

    @Test func hooksAreRecognisedForTheCorrectHandInBothCameraOrientations() {
        for mirrored in [false, true] {
            let left = detect(mirrored: mirrored) { $0.move(Self.leftHook) }
            let right = detect(mirrored: mirrored) { $0.move(Self.rightHook) }
            #expect(left.filter { $0.isPunch } == [.hook(.left)], "mirrored=\(mirrored) left=\(left)")
            #expect(right.filter { $0.isPunch } == [.hook(.right)], "mirrored=\(mirrored) right=\(right)")
        }
    }

    @Test func uppercutsAreRecognisedForTheCorrectHand() {
        for mirrored in [false, true] {
            #expect(detect(mirrored: mirrored) { $0.move(Self.leftUpper) }.filter { $0.isPunch } == [.uppercut(.left)])
            #expect(detect(mirrored: mirrored) { $0.move(Self.rightUpper) }.filter { $0.isPunch } == [.uppercut(.right)])
        }
    }

    @Test func slipsReportTheFightersOwnSideAndDucksAreRecognised() {
        // Fixture: fighter's left is image-left, so leaning image-left is a slip LEFT.
        #expect(detect { $0.move(Self.slip(towardImageLeft: true), framesPer: 5) } == [.slip(.left)])
        #expect(detect { $0.move(Self.slip(towardImageLeft: false), framesPer: 5) } == [.slip(.right)])
        // A real front camera mirrors nothing: the fighter's left is image-right. Side must still be correct.
        #expect(detect(mirrored: true) { $0.move(Self.slip(towardImageLeft: true), framesPer: 5) } == [.slip(.left)])
        #expect(detect { $0.move(Self.duck, framesPer: 5) } == [.duck])
    }

    @Test func lookalikeMotionsAreNotReportedAsTheseMoves() {
        #expect(detect { $0.hold(2000) }.isEmpty, "standing still")
        #expect(detect { $0.move(Self.jab) }.isEmpty, "a jab is left to the kernel")
        // Stepping sideways: everything translates together, no lean or tilt.
        #expect(detect { $0.move([SyntheticFighter.shifted(dx: 0.08, dy: 0, joints: Self.upper)], framesPer: 4) }.isEmpty, "side step")
        // Walking toward the camera: everything grows; not a duck.
        let closer = Dictionary(uniqueKeysWithValues: Self.upper.map { i -> (Int, P) in
            let p = SyntheticFighter.guardPose[i]!; return (i, (0.5 + (p.x - 0.5) * 1.5, 0.3 + (p.y - 0.3) * 1.5 + 0.08)) })
        #expect(!detect { $0.move([closer], framesPer: 4) }.contains(.duck), "moving closer")
        // Slow drift sideways over several seconds is not a slip.
        #expect(detect { f in for step in 1...40 { f.push(SyntheticFighter.shifted(dx: -0.002 * Double(step), dy: 0, joints: Self.upper)) } }.isEmpty, "slow drift")
    }

    @Test func fusionPrefersTheSpecificPunchOverAnEarlierStraightForTheSameHand() {
        var fusion = MoveFusion()
        let straight = BoxMaxxingJudge.Event(candidate: .init(limb: .left, kind: .straight, zone: .head, confidence: 1, tOnsetMs: 1000, tPeakMs: 1100, peakWrist: .init(x: 0, y: -0.4)))
        #expect(fusion.push(native: [], kernel: [straight], nowMs: 1120).isEmpty) // held while settling
        let hook = DetectedMove(action: .hook(.left), startMs: 1050, peakMs: 1180, confidence: 0.9, source: .native)
        #expect(fusion.push(native: [hook], kernel: [], nowMs: 1190).map(\.action) == [.hook(.left)])
        #expect(fusion.push(native: [], kernel: [], nowMs: 1500).isEmpty) // the straight was absorbed

        var plain = MoveFusion()
        _ = plain.push(native: [], kernel: [straight], nowMs: 1120)
        #expect(plain.push(native: [], kernel: [], nowMs: 1300).map(\.action) == [.straight(.left)])
        // Same punch reported twice by the kernel collapses to one.
        var dup = MoveFusion()
        _ = dup.push(native: [], kernel: [straight, straight], nowMs: 1120)
        #expect(dup.push(native: [], kernel: [], nowMs: 1300).count == 1)
    }
}
