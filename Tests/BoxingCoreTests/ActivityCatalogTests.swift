import Foundation
import Testing
@testable import BoxingCore

struct ActivityCatalogTests {
    @Test func catalogHasCompleteOriginalContracts() {
        #expect(ActivityCatalog.all.count >= 30)
        #expect(Set(ActivityCatalog.all.map(\.id)).count == ActivityCatalog.all.count)
        for item in ActivityCatalog.all {
            #expect(!item.objective.isEmpty && !item.setup.isEmpty && item.instructions.count >= 3)
            #expect(!item.cues.isEmpty && !item.mistakes.isEmpty && !item.modes.isEmpty)
            #expect(!item.demonstrationAvailable)
            #expect(item.coachReview == "Pending boxing-coach review")
        }
        #expect(!CapabilityRegistry.current.movementRecognition)
        #expect(!CapabilityRegistry.current.livePadTraining)
    }
    @Test func untrustedPrescriptionValidation() {
        var session = GuidedSession(title: "Technique", type: .technique, activities: [.init(id: "a", activityID: "jab-reset-v1", mode: .shadowboxing, sets: 2, reps: 0, workSeconds: 60, restSeconds: 30)])
        #expect(session.validationErrors(equipment: [], openSpace: false, difficulty: .beginner, budget: 150).isEmpty)
        #expect(!session.validationErrors(equipment: [], openSpace: false, difficulty: .beginner, budget: 149).isEmpty)
        session.activities[0].mode = .bag
        #expect(!session.validationErrors(equipment: [], openSpace: true, difficulty: .beginner, budget: 300).isEmpty)
        session.activities[0].sets = Int.max
        #expect(!session.validationErrors(equipment: [], openSpace: true, difficulty: .beginner, budget: 300).isEmpty)
        session.activities[0].activityID = "invented-punch"
        #expect(!session.validationErrors(equipment: [], openSpace: true, difficulty: .beginner, budget: 300).isEmpty)
        session.type = .livePads
        #expect(!session.validationErrors(equipment: [], openSpace: true, difficulty: .beginner, budget: 300).isEmpty)
    }
}
