import Foundation
import Observation
import SwiftData
import CoreData

enum TrainingFocus: String, CaseIterable, Identifiable, Codable, Sendable {
    case mixed, jab, straightCombination
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .mixed: "Jab, cross & reset"
        case .jab: "Jab & reset"
        case .straightCombination: "Jab–cross & reset"
        }
    }
}

struct SessionLaunch: Identifiable {
    let id: UUID
    let configuration: RoundConfiguration
    let focus: TrainingFocus
    let checkpoint: SessionCheckpoint?
    var execution: GuidedExecution?
    var assignmentID: UUID?
    var pad: PadTrainingState?
    init(id: UUID = UUID(), configuration: RoundConfiguration, focus: TrainingFocus, checkpoint: SessionCheckpoint? = nil, execution: GuidedExecution? = nil, assignmentID: UUID? = nil) {
        self.id = id; self.configuration = configuration; self.focus = focus; self.checkpoint = checkpoint; self.execution = execution; self.assignmentID = assignmentID
    }
}

struct SessionRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let focus: TrainingFocus
    let activeSeconds: Double
    let workSeconds: Double
    let completedRounds: Int
    let skippedBlocks: Int
    let issuedCues: Int
    let finished: Bool
    var guided: GuidedSummary?
    var assignmentID: UUID?
    var pad: PadTrainingState?
    var sparring: SparringSummary? = nil
    /// Coaching feedback written after the session.
    var debrief: SessionDebrief? = nil
}

enum SessionFollowUp { case today, progress, assignment(UUID) }

@MainActor @Observable
final class AppStore {
    var selectedDays: Set<Int> {
        get { Set(preferences.days) }
        set { preferences.days = newValue.sorted(); persist() }
    }
    var voiceEnabled: Bool {
        get { preferences.voiceEnabled }
        set { preferences.voiceEnabled = newValue; persist() }
    }
    var stance: String {
        get { preferences.stance }
        set { preferences.stance = newValue; persist() }
    }
    private(set) var history: [SessionRecord] = []
    private(set) var meals: [MealEntry] = []
    private(set) var waterEntries: [WaterEntry] = []
    private(set) var messages: [CoachMessage] = []
    private(set) var videos: [LocalVideo] = []
    private(set) var markers: [VideoMarker] = []
    private(set) var reports: [AIClipReport] = []
    private(set) var profile: AthleteProfile
    private(set) var plan: [PlannedPractice] = []
    private(set) var workouts: [WorkoutCompletion] = []
    private(set) var workoutDrafts: [WorkoutDraft] = []
    private(set) var workoutPlans: [SavedWorkoutPlan] = []
    private(set) var targets: NutritionTargets
    private(set) var pendingSession: SessionLaunch?
    var activeSession: SessionLaunch?
    var queuedSession: SessionLaunch?
    var replacementSession: SessionLaunch?
    var storageNotice: String?
    var sessionFollowUp: SessionFollowUp?
    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored let context: ModelContext
    private var preferences: LocalPreferences
    private static let legacyKey = "boxing.local-progress.v1"

    private struct Legacy: Codable {
        var selectedDays: Set<Int>
        var voiceEnabled: Bool
        var stance: String
        var history: [SessionRecord]
    }

    init(container: ModelContainer, defaults: UserDefaults = .standard) throws {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
        let preferences = try context.fetch(FetchDescriptor<LocalPreferences>()).first ?? LocalPreferences()
        let profile = try context.fetch(FetchDescriptor<AthleteProfile>()).first ?? AthleteProfile()
        let targets = try context.fetch(FetchDescriptor<NutritionTargets>()).first ?? NutritionTargets()
        if profile.modelContext == nil { context.insert(profile) }
        if preferences.modelContext == nil { context.insert(preferences) }
        if targets.modelContext == nil { context.insert(targets) }
        self.preferences = preferences; self.profile = profile; self.targets = targets
        // Import the complete legacy snapshot before saving anything. Retain it if import fails.
        if !preferences.legacyImported {
            if let data = defaults.data(forKey: Self.legacyKey) {
                let legacy = try JSONDecoder().decode(Legacy.self, from: data)
                preferences.days = legacy.selectedDays.sorted()
                preferences.voiceEnabled = legacy.voiceEnabled
                preferences.stance = legacy.stance
                let ids = Set(try context.fetch(FetchDescriptor<SavedPractice>()).map(\.id))
                for record in legacy.history where !ids.contains(record.id) {
                    context.insert(try SavedPractice(record))
                }
            }
            preferences.legacyImported = true
            try context.save()
            defaults.removeObject(forKey: Self.legacyKey)
        }
        try context.save()
        try reload()
        // Another device's changes arrive through CloudKit; refresh when they land.
        remoteChanges = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeRemoteChanges() }
        }
    }

    @ObservationIgnored private var remoteChanges: NSObjectProtocol?

    /// Folds in changes synced from another device: merges duplicate single records
    /// (two devices can each create a profile before syncing) and reloads.
    func mergeRemoteChanges() {
        guard activeSession == nil else { return }
        do {
            if let keep = try Self.singleton(context, LocalPreferences.self, score: { ($0.days.count, $0.legacyImported ? 1 : 0) }) { preferences = keep }
            if let keep = try Self.singleton(context, AthleteProfile.self, score: { ($0.equipment.count + ($0.goal.isEmpty ? 0 : 1) + ($0.styleFocusData == nil ? 0 : 1), $0.sessionMinutes) }) { profile = keep }
            if let keep = try Self.singleton(context, NutritionTargets.self, score: { ($0.acceptedAt == nil ? 0 : 1, Int($0.calories)) }) { targets = keep }
            try Self.dedupe(context, SavedPractice.self, by: \.id)
            try Self.dedupe(context, PlannedPractice.self, by: \.id)
            try Self.dedupe(context, MealEntry.self, by: \.id)
            try Self.dedupe(context, AIClipReport.self, by: \.id)
            if context.hasChanges { try context.save() }
            try reload()
        } catch { storageNotice = String(localized: "Synced changes could not be loaded. Your data on this iPhone is unchanged.") }
    }
    private static func singleton<T: PersistentModel>(_ context: ModelContext, _ type: T.Type, score: (T) -> (Int, Int)) throws -> T? {
        let all = try context.fetch(FetchDescriptor<T>())
        guard all.count > 1 else { return all.first }
        let keep = all.max { score($0) < score($1) }!
        for item in all where item.persistentModelID != keep.persistentModelID { context.delete(item) }
        return keep
    }
    private static func dedupe<T: PersistentModel>(_ context: ModelContext, _ type: T.Type, by id: KeyPath<T, UUID>) throws {
        var seen = Set<UUID>()
        for item in try context.fetch(FetchDescriptor<T>()) {
            if seen.contains(item[keyPath: id]) { context.delete(item) } else { seen.insert(item[keyPath: id]) }
        }
    }

    func start(configuration: RoundConfiguration = .init(), focus: TrainingFocus = .mixed) {
        let launch = SessionLaunch(configuration: configuration, focus: focus)
        if pendingSession != nil { replacementSession = launch } else { activeSession = launch }
    }
    func saveCheckpoint(launch: SessionLaunch, checkpoint: SessionCheckpoint) {
        guard checkpoint.timeline.status != .ready, checkpoint.isValid(configuration: launch.configuration) else { return }
        do {
            let draft = try context.fetch(FetchDescriptor<SavedSessionDraft>()).first ?? SavedSessionDraft()
            draft.executionData = nil; draft.padData = nil; draft.assignmentID = launch.assignmentID
            draft.sessionID = launch.id; draft.focusRaw = launch.focus.rawValue
            draft.configuration = try JSONEncoder().encode(launch.configuration)
            draft.checkpoint = try JSONEncoder().encode(checkpoint)
            if draft.modelContext == nil { context.insert(draft) }
            try context.save()
            pendingSession = SessionLaunch(id: launch.id, configuration: launch.configuration, focus: launch.focus, checkpoint: checkpoint, assignmentID: launch.assignmentID)
        } catch { failedSave() }
    }
    @discardableResult func discardCheckpoint() -> Bool {
        do {
            for item in try context.fetch(FetchDescriptor<SavedSessionDraft>()) { context.delete(item) }
            try context.save(); pendingSession = nil; return true
        } catch { failedSave(); return false }
    }
    @discardableResult func record(_ record: SessionRecord) -> Bool {
        guard !history.contains(where: { $0.id == record.id }) else { return true }
        if let id = record.assignmentID, let assignment = plan.first(where: { $0.id == id }) {
            guard !assignmentIsComplete(assignment) else {
                storageNotice = "This assignment is already completed. Its saved result has been kept."; return false
            }
            if let session = assignment.session {
                guard let summary = record.guided, summary.execution.session == session,
                      summary.execution.assignmentID == id, summary.execution.phase == .recap,
                      summary.execution.camera == nil, summary.execution.isValidCheckpoint else {
                    storageNotice = "The result does not match the complete assigned session. It has not been saved."; return false
                }
            }
        }
        do {
            context.insert(try SavedPractice(record))
            if let assignmentID = record.assignmentID, let assignment = plan.first(where: { $0.id == assignmentID }) {
                assignment.completionID = record.id
            }
            for draft in try context.fetch(FetchDescriptor<SavedSessionDraft>()) where draft.sessionID == record.id { context.delete(draft) }
            try commit(); return true
        }
        catch { failedSave(); return false }
    }
    @discardableResult func saveMeal(_ draft: MealDraft, date: Date, existing: MealEntry? = nil) -> Bool {
        guard draft.isValid else { return false }
        if let existing { existing.update(draft, date: date) }
        else { context.insert(MealEntry(date: date, draft: draft)) }
        return persist()
    }
    @discardableResult func addWater(_ amount: Int, date: Date) -> Bool {
        guard (1...10_000).contains(amount) else { return false }
        context.insert(WaterEntry(date: date, millilitres: amount))
        return persist()
    }
    func deleteMeal(_ meal: MealEntry) { context.delete(meal); persist() }
    func deleteWater(_ entry: WaterEntry) { context.delete(entry); persist() }
    @discardableResult func saveReport(video: LocalVideo, start: Double, end: Double, model: String, draft: VideoReviewDraft) -> Bool {
        guard draft.isValid(start: start, end: end) else { return false }
        do { context.insert(try AIClipReport(videoID: video.id, start: start, end: end, model: model, draft: draft)); try commit(); return true }
        catch { failedSave(); return false }
    }
    @discardableResult func addMarker(video: LocalVideo, start: Double, end: Double, duration: Double, action: String, note: String) -> Bool {
        guard start.isFinite, end.isFinite, duration.isFinite, start >= 0, end > start, end <= duration,
              ["Jab", "Cross", "Jab–cross", "Idle / reset", "Other movement", "Uncertain / occluded"].contains(action) else { return false }
        context.insert(VideoMarker(videoID: video.id, start: start, end: end, action: action, note: note))
        return persist()
    }
    func deleteMarker(_ marker: VideoMarker) { context.delete(marker); persist() }
    @discardableResult func saveProfile(name: String, experience: String, goal: String, equipment: [String], space: String, minutes: Int) -> Bool {
        guard (4...60).contains(minutes) else { return false }
        profile.name = name; profile.experience = experience; profile.goal = goal
        profile.equipment = equipment; profile.space = space; profile.sessionMinutes = minutes
        return persist()
    }
    @discardableResult func reschedule(_ practice: PlannedPractice, to date: Date) -> Bool {
        guard practice.completionID == nil, date >= Calendar.current.startOfDay(for: .now),
              !plan.contains(where: { $0.id != practice.id && Calendar.current.isDate($0.date, inSameDayAs: date) }) else {
            storageNotice = "Choose an unassigned future date. Completed assignments stay in place."; return false
        }
        // Moving a prescribed assignment can change recovery spacing. Require regeneration for structured plans.
        guard practice.sessionData == nil else { storageNotice = "Structured plans keep their accepted recovery schedule. Remove an unwanted future assignment and generate a new draft instead."; return false }
        practice.date = Calendar.current.startOfDay(for: date); return persist()
    }
    func removePlanItem(_ practice: PlannedPractice) { guard practice.completionID == nil else { return }; context.delete(practice); persist() }
    var eligibleWorkouts: [WorkoutRoutine] {
        WorkoutRoutine.all.filter { sessionErrors($0.guidedSession).isEmpty }
    }
    @discardableResult func saveWorkoutPlan(_ proposal: WorkoutProposal) -> Bool {
        let allowed = Dictionary(uniqueKeysWithValues: eligibleWorkouts.map { ($0.id, $0.guidedSession.estimatedSeconds) })
        guard proposal.isValid(allowedSeconds: allowed, budgetSeconds: profile.sessionMinutes * 60), let session = proposal.guidedSession, sessionErrors(session).isEmpty else { return false }
        context.insert(SavedWorkoutPlan(proposal)); return persist()
    }
    func deleteWorkoutPlan(_ plan: SavedWorkoutPlan) { context.delete(plan); persist() }
    @discardableResult func saveWorkoutDraft(_ routine: WorkoutRoutine, exerciseIDs: Set<String>, notes: String) -> Bool {
        guard exerciseIDs.isSubset(of: Set(routine.exercises.map(\.id))) else { return false }
        if let draft = workoutDrafts.first(where: { $0.routineID == routine.id }) { draft.exerciseIDs = exerciseIDs.sorted(); draft.notes = notes }
        else { context.insert(WorkoutDraft(routineID: routine.id, exerciseIDs: exerciseIDs.sorted(), notes: notes)) }
        return persist()
    }
    @discardableResult func completeWorkout(_ routine: WorkoutRoutine, exerciseIDs: Set<String>, notes: String = "") -> Bool {
        let valid = Set(routine.exercises.map(\.id))
        guard !exerciseIDs.isEmpty, exerciseIDs.isSubset(of: valid) else { return false }
        context.insert(WorkoutCompletion(routineID: routine.id, title: String(localized: routine.title), exerciseIDs: exerciseIDs.sorted(), notes: notes))
        for draft in workoutDrafts where draft.routineID == routine.id { context.delete(draft) }
        return persist()
    }
    static var videoDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("BoxVideos", isDirectory: true)
    }
    func videoURL(_ video: LocalVideo) -> URL { Self.videoDirectory.appendingPathComponent(video.filename) }
    @discardableResult func saveVideo(from source: URL, title: String, kind: String) async -> Bool {
        let filename = UUID().uuidString + ".mov"
        let destination = Self.videoDirectory.appendingPathComponent(filename)
        do {
            let directory = Self.videoDirectory
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                #endif
            }.value
            context.insert(LocalVideo(filename: filename, title: title, kind: kind))
            try commit()
            return true
        } catch {
            try? FileManager.default.removeItem(at: destination)
            failedSave(); return false
        }
    }
    @discardableResult func updateVideo(_ video: LocalVideo, title: String, kind: String, notes: String, subjectCode: String, setupCode: String) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        video.title = title; video.kind = kind; video.notes = notes; video.subjectCode = subjectCode; video.setupCode = setupCode; return persist()
    }
    @discardableResult func deleteVideo(_ video: LocalVideo) -> Bool {
        let url = videoURL(video)
        for marker in markers where marker.videoID == video.id { context.delete(marker) }
        for report in reports where report.videoID == video.id { context.delete(report) }
        context.delete(video)
        guard persist() else { return false }
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { storageNotice = "The clip was removed from your library, but its file could not be deleted. Try resetting local data to clear remaining files." }
        return true
    }
    @discardableResult func saveTargets(calories: Double, protein: Double, carbs: Double, fat: Double, water: Int) -> Bool {
        guard [calories, protein, carbs, fat].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }),
              (0...20_000).contains(water) else { return false }
        targets.proposalData = nil; targets.policyID = nil; targets.acceptedAt = nil
        targets.calories = calories; targets.protein = protein; targets.carbs = carbs
        targets.fat = fat; targets.water = water
        return persist()
    }
    @discardableResult func addMessage(role: String, text: String) -> Bool {
        context.insert(CoachMessage(role: role, text: text)); return persist()
    }
    func meals(on date: Date, calendar: Calendar = .current) -> [MealEntry] {
        meals.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func water(on date: Date, calendar: Calendar = .current) -> [WaterEntry] {
        waterEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func totals(on date: Date, calendar: Calendar = .current) -> NutritionTotals {
        var result = NutritionTotals()
        for meal in meals(on: date, calendar: calendar) {
            result.calories += meal.calories; result.protein += meal.protein
            result.carbs += meal.carbs; result.fat += meal.fat
        }
        result.water = water(on: date, calendar: calendar).reduce(0) { $0 + $1.millilitres }
        return result
    }
    func resetLocalData() {
        do {
            for item in try context.fetch(FetchDescriptor<SavedPractice>()) { context.delete(item) }
            for item in meals { context.delete(item) }
            for item in waterEntries { context.delete(item) }
            for item in messages { context.delete(item) }
            for item in videos { context.delete(item) }
            for item in markers { context.delete(item) }
            for item in reports { context.delete(item) }
            for item in plan { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<AcceptedTrainingPlan>()) { context.delete(item) }
            for item in workouts { context.delete(item) }
            for item in workoutDrafts { context.delete(item) }
            for item in workoutPlans { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<SavedSessionDraft>()) { context.delete(item) }
            profile.nutritionInputData = nil
            targets.proposalData = nil; targets.policyID = nil; targets.acceptedAt = nil
            profile.name = ""; profile.experience = "Beginner"; profile.goal = "Build consistency"
            profile.equipment = []; profile.space = "Small indoor space"; profile.sessionMinutes = 10
            preferences.days = []; preferences.voiceEnabled = true; preferences.stance = "Not set"
            targets.calories = 0; targets.protein = 0; targets.carbs = 0; targets.fat = 0; targets.water = 0
            try commit()
            do {
                if FileManager.default.fileExists(atPath: Self.videoDirectory.path) { try FileManager.default.removeItem(at: Self.videoDirectory) }
            } catch { storageNotice = "Your records were erased, but some video files could not be removed. Please try reset again." }
        } catch { failedSave() }
    }
    func reload() throws {
        if let draft = try context.fetch(FetchDescriptor<SavedSessionDraft>()).first {
            if let data = draft.padData {
                let pad = try JSONDecoder().decode(PadTrainingState.self, from: data)
                guard pad.isValidCheckpoint else { throw CocoaError(.coderReadCorrupt) }
                pendingSession = SessionLaunch(id: draft.sessionID, configuration: .init(), focus: .mixed, assignmentID: draft.assignmentID)
                pendingSession?.pad = pad.restored()
            } else if let data = draft.executionData {
                let execution = try JSONDecoder().decode(GuidedExecution.self, from: data)
                guard execution.isValidCheckpoint else { throw CocoaError(.coderReadCorrupt) }
                pendingSession = SessionLaunch(id: draft.sessionID, configuration: .init(), focus: .mixed, execution: execution.restored(), assignmentID: execution.assignmentID)
            } else {
            let configuration = try JSONDecoder().decode(RoundConfiguration.self, from: draft.configuration)
            let checkpoint = try JSONDecoder().decode(SessionCheckpoint.self, from: draft.checkpoint)
            guard checkpoint.isValid(configuration: configuration) else { throw CocoaError(.coderReadCorrupt) }
            pendingSession = SessionLaunch(id: draft.sessionID, configuration: configuration, focus: TrainingFocus(rawValue: draft.focusRaw) ?? .mixed, checkpoint: checkpoint, assignmentID: draft.assignmentID)
            }
        } else { pendingSession = nil }

        plan = try context.fetch(FetchDescriptor<PlannedPractice>()).sorted { $0.date < $1.date }
        workouts = try context.fetch(FetchDescriptor<WorkoutCompletion>()).sorted { $0.date > $1.date }
        workoutDrafts = try context.fetch(FetchDescriptor<WorkoutDraft>())
        workoutPlans = try context.fetch(FetchDescriptor<SavedWorkoutPlan>()).sorted { $0.date > $1.date }
        history = try context.fetch(FetchDescriptor<SavedPractice>()).sorted { $0.date > $1.date }.map { try $0.record() }
        meals = try context.fetch(FetchDescriptor<MealEntry>()).sorted { $0.date > $1.date }
        waterEntries = try context.fetch(FetchDescriptor<WaterEntry>()).sorted { $0.date > $1.date }
        messages = try context.fetch(FetchDescriptor<CoachMessage>()).sorted { $0.date < $1.date }
        // Clip files stay on the device that recorded them; synced rows for missing files are hidden.
        videos = try context.fetch(FetchDescriptor<LocalVideo>()).filter { FileManager.default.fileExists(atPath: Self.videoDirectory.appendingPathComponent($0.filename).path) }.sorted { $0.date > $1.date }
        reports = try context.fetch(FetchDescriptor<AIClipReport>()).sorted { $0.date > $1.date }
        markers = try context.fetch(FetchDescriptor<VideoMarker>()).sorted { $0.startSeconds < $1.startSeconds }
    }
    func commit() throws { try context.save(); try reload(); storageNotice = nil }
    @discardableResult func persist() -> Bool {
        do { try commit(); return true } catch { failedSave(); return false }
    }
    func failedSave() {
        context.rollback()
        storageNotice = String(localized: "Your change could not be saved. Please try again.")
    }
}

