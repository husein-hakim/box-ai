import Foundation
import Testing
@testable import BoxingCore

struct PersonalizedPlanTests {
    @MainActor func draft(_ store: AppStore) -> (TrainingPlanProposal, PlanningContext) {
        let context = store.planningContext()
        let days = (0..<7).map { offset in
            let selected = context.trainingOffsets.contains(offset)
            let items: [ActivityPrescription] = [
                .init(id: "warm", activityID: "warm-march-v1", mode: .guided, sets: 1, reps: 0, workSeconds: 30, restSeconds: 0),
                .init(id: "main", activityID: selected ? "jab-reset-v1" : "shoulder-circles-v1", mode: selected ? .shadowboxing : .guided, sets: 1, reps: 0, workSeconds: 60, restSeconds: 0),
                .init(id: "cool", activityID: "walk-reset-v1", mode: .guided, sets: 1, reps: 0, workSeconds: 30, restSeconds: 0)
            ]
            return TrainingPlanProposal.Day(offset: offset, session: .init(title: "Fixture only", type: selected ? .technique : .recovery, activities: items), rationale: "Test-only rationale")
        }
        return (.init(title: "Test fixture", progression: "Test only", days: days), context)
    }
    @Test @MainActor func acceptanceProtectsAssignmentsAndRejectsStaleContext() throws {
        let store = try AppStore(container: LocalDatabase.open(inMemory: true))
        store.selectedDays = [2, 4, 6]
        var (proposal, context) = draft(store)
        #expect(proposal.errors(context: context).isEmpty)
        #expect(store.acceptTrainingPlan(proposal, context: context))
        let ids = store.plan.map(\.id)
        #expect(!store.acceptTrainingPlan(proposal, context: context))
        #expect(store.plan.map(\.id) == ids)
        proposal.days[0].session.activities[1].activityID = "invented"
        #expect(!proposal.errors(context: context).isEmpty)
        store.stance = "Southpaw"
        #expect(!store.acceptTrainingPlan(draft(store).0, context: context))
    }
    @Test @MainActor func recoveryAndCompleteScheduleAreRequired() throws {
        let store = try AppStore(container: LocalDatabase.open(inMemory: true))
        store.selectedDays = [1, 2, 3, 4, 5, 6, 7]
        var (proposal, context) = draft(store)
        #expect(proposal.errors(context: context).contains("Include a recovery day after two training days."))
        proposal.days.removeLast()
        #expect(!proposal.errors(context: context).isEmpty)
    }
}

@Test @MainActor func realRestDaysNeedNoInventedTrainingAndCorruptPlansNeverFallBack() throws {
    let store = try AppStore(container: LocalDatabase.open(inMemory: true))
    let rest = GuidedSession(title: "Rest and recover", type: .recovery, activities: [])
    #expect(store.sessionErrors(rest).isEmpty)
    store.start(rest)
    #expect(store.activeSession == nil)
    #expect(!GuidedExecution(session: rest).isValidCheckpoint)
    let assignment = PlannedPractice(date: .now, focus: .mixed, configuration: .init())
    assignment.sessionData = Data("broken".utf8)
    store.context.insert(assignment); try store.commit()
    store.startAssignment(assignment)
    #expect(store.activeSession == nil && assignment.sessionData == Data("broken".utf8))
}

@Test @MainActor func localCivilScheduleDoesNotShiftToPreviousUTCDay() throws {
    let store = try AppStore(container: LocalDatabase.open(inMemory: true))
    store.selectedDays = [3]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
    let date = try #require(ISO8601DateFormatter().date(from: "2026-10-20T08:00:00Z"))
    let context = store.planningContext(from: date, calendar: calendar)
    #expect(context.localSchedule.first?.localDate == "2026-10-20")
    #expect(context.localSchedule.first?.weekdayName == "Tuesday")
    #expect(context.trainingOffsets == [0])
}
