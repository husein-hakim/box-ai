import Foundation
import SwiftData
import Testing
@testable import BoxingCore

@MainActor private func testStore() throws -> AppStore {
    let suite = "boxing.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    return try AppStore(container: LocalDatabase.open(inMemory: true), defaults: defaults)
}

@MainActor @Test func persistenceSurvivesFreshContainerAndStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let defaults = try #require(UserDefaults(suiteName: "boxing.tests.\(UUID().uuidString)"))
    let first = try AppStore(container: LocalDatabase.open(url: url), defaults: defaults)
    first.selectedDays = [2, 4]; first.voiceEnabled = false
    first.record(sampleRecord())
    #expect(first.saveMeal(.init(name: "Lunch", calories: 600, protein: 30, carbs: 75, fat: 20), date: .now))
    #expect(first.addWater(250, date: .now))
    #expect(first.saveTargets(calories: 2000, protein: 100, carbs: 250, fat: 70, water: 2000))
    #expect(first.addMessage(role: "user", text: "How do I practise?"))
    let second = try AppStore(container: LocalDatabase.open(url: url), defaults: defaults)
    #expect(second.history.count == 1)
    #expect(second.selectedDays == [2, 4]); #expect(!second.voiceEnabled)
    #expect(second.meals.count == 1); #expect(second.waterEntries.count == 1)
    #expect(second.targets.calories == 2000); #expect(second.messages.count == 1)
}

@MainActor @Test func repeatedSaveDoesNotDuplicatePractice() throws {
    let store = try testStore(); let record = sampleRecord()
    store.record(record); store.record(record)
    #expect(store.history.count == 1)
}

@MainActor @Test func resetClearsAllLocalRecordsAndTargets() throws {
    let store = try testStore()
    store.selectedDays = [7]; store.record(sampleRecord())
    store.saveMeal(.init(name: "Lunch", calories: 10), date: .now); store.addWater(250, date: .now)
    store.addMessage(role: "user", text: "Hello"); store.saveTargets(calories: 2000, protein: 100, carbs: 200, fat: 60, water: 2000)
    store.resetLocalData()
    #expect(store.history.isEmpty && store.selectedDays.isEmpty && store.meals.isEmpty && store.waterEntries.isEmpty && store.messages.isEmpty)
    #expect(store.targets.calories == 0 && store.targets.water == 0)
}

@MainActor @Test func legacyMigrationIsCompleteAndIdempotent() throws {
    struct Legacy: Encodable {
        let selectedDays: Set<Int>; let voiceEnabled: Bool; let stance: String; let history: [SessionRecord]
    }
    let suite = "boxing.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("keep", forKey: "unrelated-setting")
    defaults.set(try JSONEncoder().encode(Legacy(selectedDays: [2, 5], voiceEnabled: false, stance: "Southpaw", history: [sampleRecord()])), forKey: "boxing.local-progress.v1")
    let container = try LocalDatabase.open(inMemory: true)
    let first = try AppStore(container: container, defaults: defaults)
    #expect(first.stance == "Southpaw" && first.selectedDays == [2, 5] && !first.voiceEnabled)
    #expect(first.history.count == 1)
    #expect(defaults.data(forKey: "boxing.local-progress.v1") == nil)
    #expect(defaults.string(forKey: "unrelated-setting") == "keep")
    let second = try AppStore(container: container, defaults: defaults)
    #expect(second.history.count == 1)
}

@MainActor @Test func corruptLegacyIsRetainedAndNeverSilentlyReset() throws {
    let suite = "boxing.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let data = Data("invalid".utf8); defaults.set(data, forKey: "boxing.local-progress.v1")
    #expect(throws: (any Error).self) { try AppStore(container: LocalDatabase.open(inMemory: true), defaults: defaults) }
    #expect(defaults.data(forKey: "boxing.local-progress.v1") == data)
}

@MainActor @Test func mealsEditDeleteAndWaterUseCalendarDaysAcrossDST() throws {
    let store = try testStore()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 30)))
    let next = try #require(calendar.date(byAdding: .hour, value: 1, to: day))
    store.saveMeal(.init(name: "Dinner", calories: 500, protein: 20, carbs: 60, fat: 15), date: day)
    store.addWater(250, date: day); store.addWater(500, date: next)
    #expect(store.totals(on: day, calendar: calendar).water == 250)
    #expect(store.totals(on: next, calendar: calendar).water == 500)
    let meal = try #require(store.meals.first)
    store.saveMeal(.init(name: "Dinner edited", calories: 600), date: day, existing: meal)
    #expect(store.meals.count == 1 && store.totals(on: day, calendar: calendar).calories == 600)
    store.deleteMeal(meal); store.deleteWater(try #require(store.waterEntries.first))
    #expect(store.meals.isEmpty && store.waterEntries.count == 1)
}

@MainActor @Test func invalidNutritionNeverSaves() throws {
    let store = try testStore()
    #expect(!store.saveMeal(.init(name: "", calories: 10), date: .now))
    #expect(!store.saveMeal(.init(name: "Invalid", calories: -.infinity), date: .now))
    #expect(!store.saveMeal(.init(name: "Invalid", protein: -1), date: .now))
    #expect(!store.addWater(-50, date: .now))
    #expect(!store.saveTargets(calories: .nan, protein: 0, carbs: 0, fat: 0, water: 0))
    #expect(store.meals.isEmpty && store.waterEntries.isEmpty)
}

private func sampleRecord() -> SessionRecord {
    SessionRecord(id: UUID(), date: .now, focus: .mixed, activeSeconds: 72,
                  workSeconds: 12, completedRounds: 0, skippedBlocks: 0, issuedCues: 2, finished: false)
}

@MainActor @Test func workoutLogOnlyAcceptsKnownCompletedExercises() throws {
    let store = try testStore()
    let routine = try #require(WorkoutRoutine.all.first)
    #expect(!store.completeWorkout(routine, exerciseIDs: []))
    #expect(!store.completeWorkout(routine, exerciseIDs: ["invented"]))
    let exercise = try #require(routine.exercises.first)
    #expect(store.completeWorkout(routine, exerciseIDs: [exercise.id]))
    #expect(store.workouts.first?.exerciseIDs == [exercise.id])
    store.resetLocalData()
    #expect(store.workouts.isEmpty && store.plan.isEmpty && store.profile.name.isEmpty)
}

@MainActor @Test func annotationIntervalsMustFitRealClipDuration() throws {
    let store = try testStore()
    let video = LocalVideo(filename: "fixture.mov", title: "Test clip", kind: "Shadowboxing")
    #expect(!store.addMarker(video: video, start: 2, end: 1, duration: 10, action: "Jab", note: ""))
    #expect(!store.addMarker(video: video, start: 0, end: 11, duration: 10, action: "Jab", note: ""))
    #expect(!store.addMarker(video: video, start: 0, end: 1, duration: 10, action: "Invented", note: ""))
    #expect(store.addMarker(video: video, start: 1, end: 2, duration: 10, action: "Jab", note: "Manual observed jab"))
    #expect(store.markers.count == 1)
}

@MainActor @Test func recordExportContainsActualLogsAndNoDeveloperConfiguration() throws {
    let store = try testStore()
    store.saveMeal(.init(name: "Export meal", calories: 500), date: .now)
    store.addMessage(role: "user", text: "A training question")
    let data = try store.exportRecords()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["format"] as? String == "BOX.local-records")
    #expect((object["meals"] as? [[String: Any]])?.count == 1)
    #expect((object["coachMessages"] as? [[String: Any]])?.count == 1)
    #expect(object["apiKey"] == nil)
}

@Test func videoAIReportRejectsTimestampsAndUnsupportedDrills() throws {
    let valid = Data(#"{"summary":"Limited view","observations":[{"seconds":2,"observation":"Lead arm extended in this still","suggestion":"Use a controlled reset","uncertainty":"Motion between frames is unknown","drillID":"jab-reset-v1"}]}"#.utf8)
    let draft = try JSONDecoder().decode(VideoReviewDraft.self, from: valid)
    #expect(draft.isValid(start: 0, end: 10))
    #expect(!draft.isValid(start: 3, end: 10))
    let unsupported = Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "jab-reset-v1", with: "invented-drill").utf8)
    #expect(!(try JSONDecoder().decode(VideoReviewDraft.self, from: unsupported)).isValid(start: 0, end: 10))
}

@MainActor @Test func workoutDraftResumesAndClearsAfterConfirmedSave() throws {
    let store = try testStore()
    let routine = try #require(WorkoutRoutine.all.first)
    let exercise = try #require(routine.exercises.first)
    #expect(store.saveWorkoutDraft(routine, exerciseIDs: [exercise.id], notes: "One set completed"))
    let second = try AppStore(container: store.container)
    #expect(second.workoutDrafts.first?.exerciseIDs == [exercise.id])
    #expect(second.workoutDrafts.first?.notes == "One set completed")
    #expect(second.completeWorkout(routine, exerciseIDs: [exercise.id], notes: "One set completed"))
    #expect(second.workoutDrafts.isEmpty)
    #expect(second.workouts.first?.notes == "One set completed")
}

@MainActor @Test func workoutProposalRejectsUnavailableEquipmentUnknownIDsAndOverBudget() throws {
    let store = try testStore()
    #expect(!store.saveWorkoutPlan(.init(title: "Rope", routineIDs: ["skipping-start"], reason: "Intervals")))
    #expect(!store.saveWorkoutPlan(.init(title: "Unknown", routineIDs: ["invented"], reason: "Training")))
    #expect(!store.saveWorkoutPlan(.init(title: "Too much", routineIDs: ["strength-foundation", "mobility-reset"], reason: "Training")))
    #expect(store.saveWorkoutPlan(.init(title: "Easy day", routineIDs: ["mobility-reset", "core-control"], reason: "Gentle support work")))
    #expect(store.workoutPlans.count == 1)
}

@Test func barcodeServingScalingConvertsUnitsAndPreservesMissingValues() throws {
    let data = Data(#"{"product_name":"Fixture food","nutriments":{"energy-kj_100g":418.4,"proteins_100g":10000,"proteins_unit":"mg","carbohydrates_100g":5,"carbohydrates_unit":"g","fat_100g":2,"fat_unit":"g"}}"#.utf8)
    let product = try JSONDecoder().decode(BarcodeProduct.self, from: data)
    let draft = try #require(product.draft(amount: 50, barcode: "00000000"))
    #expect(abs(draft.calories - 50) < 0.001)
    #expect(draft.protein == 5 && draft.carbs == 2.5 && draft.fat == 1)
    let missing = try JSONDecoder().decode(BarcodeProduct.self, from: Data(#"{"product_name":"Incomplete","nutriments":{"energy-kcal_100g":100}}"#.utf8))
    #expect(missing.draft(amount: 100, barcode: "00000000") == nil)
}

@Test func restoredTimelineNeverCreditsTimeAway() throws {
    let configuration = RoundConfiguration()
    var timeline = RoundTimeline(configuration: configuration)
    timeline.start(at: 100); timeline.advance(to: 175)
    let decoded = try JSONDecoder().decode(RoundTimeline.self, from: JSONEncoder().encode(timeline))
    var restored = decoded.restored()
    #expect(restored.status == .paused && restored.workSeconds == 15)
    restored.advance(to: 5000)
    #expect(restored.workSeconds == 15)
    restored.resume(at: 5000); restored.advance(to: 5005)
    #expect(restored.workSeconds == 20)
}

@MainActor @Test func unfinishedSessionSurvivesReopeningAndClearsOnSave() throws {
    let store = try testStore()
    let launch = SessionLaunch(configuration: .init(), focus: .jab)
    var timeline = RoundTimeline(configuration: launch.configuration)
    timeline.start(at: 0); timeline.advance(to: 70)
    store.saveCheckpoint(launch: launch, checkpoint: .init(timeline: timeline, issuedCues: 2, cueIndex: 2, cueRaw: "jab"))
    let reopened = try AppStore(container: store.container)
    #expect(reopened.pendingSession?.id == launch.id)
    #expect(reopened.pendingSession?.checkpoint?.timeline.workSeconds == 10)
    #expect(reopened.record(.init(id: launch.id, date: .now, focus: .jab, activeSeconds: 70, workSeconds: 10, completedRounds: 0, skippedBlocks: 0, issuedCues: 2, finished: false)))
    #expect(reopened.pendingSession == nil)
    #expect(try AppStore(container: store.container).pendingSession == nil)
}
