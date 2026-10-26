import Foundation
import Testing
@testable import BoxingCore

struct ClipReviewTests {
    private func samples(_ fighter: SyntheticFighter) -> [PoseSample] {
        fighter.frames.map { frame in
            let points: [PadPoint?] = (frame["keypoints"] as! [[String: Any]]).map { PadPoint(x: $0["x"] as! Double, y: $0["y"] as! Double) }
            return PoseSample(tMs: frame["tMs"] as! Double, points: points, aspect: 640.0 / 480.0)
        }
    }

    @Test func analyzerFindsMovesWithClipTimesAndMeasuresGuard() throws {
        var fighter = SyntheticFighter()
        fighter.hold(1600)
        fighter.move(MoveRecognizerTests.jab); fighter.hold(900)
        fighter.move(MoveRecognizerTests.leftHook); fighter.hold(900)
        fighter.move(MoveRecognizerTests.duck, framesPer: 5); fighter.hold(1200)
        let motion = try ClipMotionAnalyzer.analyze(samples(fighter), stance: .orthodox)
        #expect(motion.moves.map(\.action) == [.straight(.left), .hook(.left), .duck])
        #expect(motion.trackedShare > 0.95)
        #expect(motion.moves.allSatisfy { $0.seconds > 1.5 && $0.seconds < motion.durationSeconds })
        #expect((motion.guardShare ?? 0) > 0.9)
        #expect(motion.punches.allSatisfy { !$0.otherHandLow })
        let evidence = motion.evidence(stance: .orthodox, offsetSeconds: 10)
        #expect(evidence.contains("Jab ×1") && evidence.contains("Duck ×1"))
        #expect(evidence.contains(String(format: "%.1fs Jab", motion.moves[0].seconds + 10)))
    }

    @Test func droppedRearHandDuringJabIsFlagged() throws {
        var fighter = SyntheticFighter()
        fighter.hold(1600)
        // Jab while the right wrist sits at the waist.
        let low: [Int: SyntheticFighter.P] = [10: (0.62, 0.55)]
        fighter.move(MoveRecognizerTests.jab.map { $0.merging(low) { $1 } }); fighter.hold(900)
        let motion = try ClipMotionAnalyzer.analyze(samples(fighter), stance: .orthodox)
        let jab = try #require(motion.punches.first)
        #expect(jab.otherHandLow)
        #expect(jab.action == .straight(.left))
    }

    @Test func untrackedClipGivesNoStatistics() throws {
        let empty = (0..<60).map { PoseSample(tMs: Double($0) * 80, points: Array(repeating: nil, count: 17), aspect: 0.56) }
        let motion = try ClipMotionAnalyzer.analyze(empty, stance: .orthodox)
        #expect(!motion.isUsable && motion.moves.isEmpty)
        #expect(motion.evidence(stance: .orthodox, offsetSeconds: 0).contains("Judge from the images alone"))
    }

    @Test func keyMomentsPreferFaultsAndCoverTheSegment() {
        let motion = ClipMotion(durationSeconds: 20, trackedShare: 1, feetVisibleShare: 1, moves: [
            .init(seconds: 3, action: .straight(.left), confidence: 0.9, otherHandLow: false, droppedAfter: false),
            .init(seconds: 9, action: .hook(.right), confidence: 0.9, otherHandLow: true, droppedAfter: false)
        ])
        let times = ClipMotionAnalyzer.keyMoments(motion, duration: 20, count: 6)
        #expect(times.count == 6)
        #expect(times.contains(9) && times.contains(3))
        #expect(times.allSatisfy { $0 >= 0.3 && $0 <= 19.65 })
        #expect(times == times.sorted())
    }

    @Test func reviewSanitizingRepairsAndRejects() throws {
        let json = """
        {"status":"OK","headline":"Sharp jab, rear hand drifts","summary":"Good rhythm.","scores":{"overall":95,"offense":60,"defense":50,"footwork":55,"guard":45},
         "scoreBasis":"x","confidence":"Medium","strengths":[{"seconds":4.2,"title":"Snappy jab","detail":"d"}],
         "fixes":[{"seconds":40,"title":"Rear hand drops","why":"Open to the hook","cue":"Glove on cheek","drillID":"made-up-v1"},{"seconds":null,"title":"","why":"","cue":"","drillID":null}],
         "moments":[{"seconds":2,"text":"Balanced","positive":true},{"seconds":99,"text":"Outside","positive":false}],"unobservable":["Feet out of frame"]}
        """
        let review = try JSONDecoder().decode(ClipReview.self, from: Data(json.utf8))
        let clean = try #require(review.sanitized(start: 0, end: 12, drillIDs: ["jab-reset-v1"]))
        #expect(clean.status == "ok" && clean.confidence == "medium")
        #expect(clean.fixes.count == 1 && clean.fixes[0].seconds == nil && clean.fixes[0].drillID == nil)
        #expect(clean.moments.count == 1)
        #expect(clean.scores?.overall == (2 * 95 + 52) / 3)

        var noFix = review; noFix.fixes = []
        #expect(noFix.sanitized(start: 0, end: 12, drillIDs: []) == nil)
        var rejected = review; rejected.status = "rejected"; rejected.rejectReason = "Not boxing"
        #expect(rejected.sanitized(start: 0, end: 12, drillIDs: [])?.isRejected == true)
    }

    @Test func styleBecomesASparringDrillInTheUsersStance() throws {
        let json = """
        {"status":"ok","fighter":"Muhammad Ali","recognised":true,"stance":"Orthodox","archetype":"Out-boxer","summary":"Moves and jabs.",
         "traits":[{"title":"Constant footwork","detail":"d","seconds":3,"source":"clip"},{"title":"Pull-back counter","detail":"d","seconds":0,"source":"known"}],
         "emphasis":{"jab":95,"power":40,"combinations":60,"headMovement":85,"footwork":98,"pressure":20,"counters":80,"guard":130},
         "signatureCombos":[["jab","jab","cross"],["slipRear","leadHook","bogus"],["jab"],["jab","jab","cross"]],"drillIDs":["jab-reset-v1","nope"],
         "conditioning":"Leg endurance","fuelNote":"Eat enough carbohydrate","caution":"Hands low is risky"}
        """
        let style = try #require(try JSONDecoder().decode(FighterStyle.self, from: Data(json.utf8)).sanitized(start: 0, end: 20, drillIDs: ["jab-reset-v1"]))
        #expect(style.stance == "orthodox" && style.emphasis.guardScore == 100)
        #expect(style.signatureCombos == [["jab", "jab", "cross"], ["slipRear", "leadHook"]])
        #expect(style.drillIDs == ["jab-reset-v1"])
        #expect(style.traits[0].seconds == 3 && style.traits[1].seconds == nil)
        let southpaw = try #require(style.sparringConfiguration(userStance: .southpaw))
        #expect(southpaw.sequence == [.straight(.right), .straight(.right), .straight(.left), .slip(.left), .hook(.right)])
        #expect(southpaw.mode == .drill && southpaw.isValid)
        #expect(style.planFocus.summary.contains("Muhammad Ali"))
    }

    @Test func focusSessionFitsLevelEquipmentAndBudget() throws {
        let session = try #require(FocusSession.build(title: "Fix the guard", drillIDs: ["jab-reset-v1", "lead-hook-v1", "made-up", "stance-guard-v1"],
                                                      equipment: [], openSpace: false, difficulty: .beginner, budgetSeconds: 600))
        #expect(session.activities.first?.activityID == "warm-march-v1" && session.activities.last?.activityID == "walk-reset-v1")
        #expect(!session.activities.contains { $0.activityID == "lead-hook-v1" })
        #expect(session.activities.contains { $0.activityID == "jab-reset-v1" })
        #expect(session.validationErrors(equipment: [], openSpace: false, difficulty: .beginner, budget: 600).isEmpty)
        let tight = try #require(FocusSession.build(title: "Short", drillIDs: ["jab-reset-v1", "cross-reset-v1", "stance-guard-v1"], equipment: [], openSpace: false, difficulty: .beginner, budgetSeconds: 300))
        #expect(tight.estimatedSeconds <= 300)
        #expect(FocusSession.build(title: "None", drillIDs: ["lead-hook-v1"], equipment: [], openSpace: false, difficulty: .beginner, budgetSeconds: 600) == nil)
    }
}
