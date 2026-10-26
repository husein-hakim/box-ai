import Foundation
import Testing
@testable import BoxingCore

/// Synthetic 2-D kinematics for each move, fed through the recovered kernel.
struct SyntheticFighter {
    typealias P = (x: Double, y: Double)
    var t = 1000.0
    var frames: [[String: Any]] = []
    // Guard pose, same geometry family as the recovered fixtures (640×480).
    static let guardPose: [Int: P] = [0: (0.5, 0.2), 1: (0.49, 0.19), 2: (0.51, 0.19), 3: (0.48, 0.2), 4: (0.52, 0.2),
        5: (0.4, 0.3), 6: (0.6, 0.3), 7: (0.36, 0.45), 8: (0.64, 0.45), 9: (0.4, 0.25), 10: (0.6, 0.25),
        11: (0.42, 0.6), 12: (0.58, 0.6), 13: (0.42, 0.8), 14: (0.58, 0.8), 15: (0.42, 0.95), 16: (0.58, 0.95)]
    mutating func push(_ pose: [Int: P], dt: Double = 40) {
        let full = Self.guardPose.merging(pose) { $1 }
        let keypoints: [[String: Any]] = (0..<17).map { i in let p = full[i]!; return ["x": p.x, "y": p.y, "score": 0.95] }
        frames.append(["tMs": t, "width": 640, "height": 480, "keypoints": keypoints])
        t += dt
    }
    mutating func hold(_ ms: Double, _ pose: [Int: P] = guardPose) { for _ in 0..<Int(ms / 40) { push(pose) } }
    /// Interpolate joints from the guard through keyframes and back.
    mutating func move(_ keys: [[Int: P]], framesPer: Int = 3) {
        var previous = Self.guardPose
        for key in keys + [Self.guardPose] {
            let target = previous.merging(key) { $1 }
            for f in 1...framesPer {
                let a = Double(f) / Double(framesPer)
                push(Dictionary(uniqueKeysWithValues: target.map { i, p in (i, (previous[i]!.x + (p.x - previous[i]!.x) * a, previous[i]!.y + (p.y - previous[i]!.y) * a)) }))
            }
            previous = target
        }
    }
    static func shifted(dx: Double, dy: Double, joints: [Int]) -> [Int: P] {
        Dictionary(uniqueKeysWithValues: joints.map { ($0, (guardPose[$0]!.x + dx, guardPose[$0]!.y + dy)) })
    }
}

/// End-to-end: recovered kernel + native recogniser + fusion must report exactly
/// one correct action for each synthetic move (a confusion-matrix check).
struct FullPipelineMoveTests {
    func fused(_ build: (inout SyntheticFighter) -> Void) throws -> [FightAction] {
        let kernel = try BoxMaxxingKernel(); try kernel.setStance(.orthodox)
        var recognizer = MoveRecognizer(), fusion = MoveFusion()
        var fighter = SyntheticFighter()
        fighter.hold(1600); build(&fighter); fighter.hold(800)
        var out: [FightAction] = []
        for frame in fighter.frames {
            let sample = try kernel.pushJSON(JSONSerialization.data(withJSONObject: frame))
            let points: [PadPoint?] = (frame["keypoints"] as! [[String: Any]]).map { PadPoint(x: $0["x"] as! Double, y: $0["y"] as! Double) }
            let t = frame["tMs"] as! Double
            let native = recognizer.push(.init(tMs: t, points: points, aspect: 640.0 / 480.0))
            let current = recognizer
            out += fusion.push(native: native, kernel: sample.punches, nowMs: t, busy: { current.specificInProgress(side: $0) }).map(\.action)
        }
        return out
    }

    @Test func everyMoveIsRecognisedOnceAndNeverConfused() throws {
        let cases: [(String, FightAction, (inout SyntheticFighter) -> Void)] = [
            ("jab", .straight(.left), { $0.move(MoveRecognizerTests.jab) }),
            ("left hook", .hook(.left), { $0.move(MoveRecognizerTests.leftHook) }),
            ("right hook", .hook(.right), { $0.move(MoveRecognizerTests.rightHook) }),
            ("left uppercut", .uppercut(.left), { $0.move(MoveRecognizerTests.leftUpper) }),
            ("right uppercut", .uppercut(.right), { $0.move(MoveRecognizerTests.rightUpper) }),
            ("slip left", .slip(.left), { $0.move(MoveRecognizerTests.slip(towardImageLeft: true), framesPer: 5) }),
            ("slip right", .slip(.right), { $0.move(MoveRecognizerTests.slip(towardImageLeft: false), framesPer: 5) }),
            ("duck", .duck, { $0.move(MoveRecognizerTests.duck, framesPer: 5) })
        ]
        var table: [String] = []
        for (name, expected, build) in cases {
            let actual = try fused(build)
            table.append("\(name) → \(actual.map { $0.title(stance: .orthodox) })")
            #expect(actual == [expected], "\(name): \(actual)")
        }
        print("CONFUSION\n" + table.joined(separator: "\n"))
    }
}
