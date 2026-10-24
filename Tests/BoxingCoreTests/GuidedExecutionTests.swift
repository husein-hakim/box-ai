import Foundation
import SwiftData
import Testing
@testable import BoxingCore

struct GuidedExecutionTests {
    var session: GuidedSession { .init(title: "Practice", type: .mixed, activities: [
        .init(id: "a", activityID: "jab-reset-v1", mode: .shadowboxing, sets: 2, reps: 0, workSeconds: 30, restSeconds: 15),
        .init(id: "b", activityID: "squat-v1", mode: .guided, sets: 1, reps: 8, workSeconds: 60, restSeconds: 0)
    ]) }
    @Test func timerNeverConfirmsWorkAndCannotCreditTimeAway() throws {
        var execution = GuidedExecution(session: session)
        execution.begin(); execution.startSet(at: 100); execution.tick(at: 140)
        #expect(execution.phase == .confirmation)
        #expect(execution.results[0].confirmedSets == 0)
        #expect(execution.results[0].timedSeconds == 30)
        execution.confirm(at: 140)
        #expect(execution.phase == .rest)
        execution.pause(at: 145)
        let data = try JSONEncoder().encode(execution)
        execution = try JSONDecoder().decode(GuidedExecution.self, from: data).restored()
        execution.tick(at: 10000)
        #expect(execution.elapsed == 5)
        execution.resume(at: 10000); execution.tick(at: 10010)
        #expect(execution.phase == .instruction)
        execution.startSet(at: 10010); execution.finishSet(at: 10020); execution.confirm(at: 10020)
        #expect(execution.outcome(at: 0) == .partial)
        execution.startSet(at: 10020); execution.finishSet(at: 10030); execution.confirm(reps: 8, at: 10030)
        #expect(execution.outcome(at: 1) == .completed)
        #expect(execution.phase == .recap && execution.isValidCheckpoint)
    }
    @Test func skippingAndEndingPreservePartialWork() {
        var execution = GuidedExecution(session: session)
        execution.begin(); execution.startSet(at: 0); execution.tick(at: 4); execution.skip(at: 4)
        #expect(execution.outcome(at: 0) == .partial)
        execution.end(at: 5)
        #expect(execution.outcome(at: 1) == .notStarted)
        #expect(execution.endedEarly)
    }
    @Test @MainActor func checkpointAndOriginSurviveReopenAndSaveOnce() throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let store = try AppStore(container: LocalDatabase.open(url: url))
        let assignment = PlannedPractice(date: .now, focus: .mixed, configuration: .init())
        assignment.sessionData = try JSONEncoder().encode(session)
        store.context.insert(assignment); try store.commit()
        store.startAssignment(assignment)
        let launch = try #require(store.activeSession)
        var execution = try #require(launch.execution)
        execution.begin(); execution.startSet(at: 0); execution.pause(at: 10)
        store.saveExecution(launch: launch, execution: execution)
        let reopened = try AppStore(container: LocalDatabase.open(url: url))
        #expect(reopened.pendingSession?.execution?.paused == true)
        #expect(reopened.pendingSession?.assignmentID == assignment.id)
        execution.end(at: 20)
        let record = SessionRecord(id: launch.id, date: .now, focus: .mixed, activeSeconds: execution.activeSeconds, workSeconds: 10, completedRounds: 0, skippedBlocks: 0, issuedCues: 0, finished: false, guided: .init(execution: execution), assignmentID: assignment.id)
        #expect(reopened.record(record)); #expect(reopened.record(record))
        #expect(reopened.history.count == 1 && reopened.pendingSession == nil)
        #expect(reopened.plan.first?.completionID == record.id)
    }
}

// Original persistent entity names and fields exercise SwiftData's additive migration path.
private enum PreFoundationSchema {
    @Model final class PlannedPractice {
        @Attribute(.unique) var id: UUID
        var date: Date
        var focusRaw: String
        var rounds: Int
        var workSeconds: Int
        var restSeconds: Int
        var source: String
        var note: String
        init(id: UUID) {
            self.id = id; date = .now; focusRaw = "jab"; rounds = 3; workSeconds = 60; restSeconds = 30; source = "Local plan"; note = "Keep this legacy assignment"
        }
    }
    @Model final class SavedSessionDraft {
        @Attribute(.unique) var key: String
        var sessionID: UUID
        var focusRaw: String
        var configuration: Data
        var checkpoint: Data
        init() throws {
            key = "active"; sessionID = UUID(); focusRaw = "jab"
            configuration = try JSONEncoder().encode(RoundConfiguration())
            var timeline = RoundTimeline(configuration: .init()); timeline.start(at: 0); timeline.pause(at: 5)
            checkpoint = try JSONEncoder().encode(SessionCheckpoint(timeline: timeline, issuedCues: 0, cueIndex: 0, cueRaw: "reset"))
        }
    }
}

@Test @MainActor func additiveMigrationKeepsOldAssignmentAndCheckpoint() throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
    let id = UUID()
    func createOldStore() throws {
        let schema = Schema([PreFoundationSchema.PlannedPractice.self, PreFoundationSchema.SavedSessionDraft.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        context.insert(PreFoundationSchema.PlannedPractice(id: id))
        context.insert(try PreFoundationSchema.SavedSessionDraft())
        try context.save()
    }
    try createOldStore()
    let store = try AppStore(container: LocalDatabase.open(url: url))
    #expect(store.plan.count == 1 && store.plan.first?.id == id)
    #expect(store.plan.first?.sessionData == nil && store.plan.first?.note == "Keep this legacy assignment")
    #expect(store.pendingSession?.checkpoint?.timeline.activeSeconds == 5)
    #expect(store.pendingSession?.execution == nil)
}
