import Foundation
import SwiftData

@Model final class LocalPreferences {
    var key: String = ""
    var days: [Int] = []
    var voiceEnabled: Bool = false
    var stance: String = ""
    var legacyImported: Bool = false
    init() {
        key = "primary"; days = []; voiceEnabled = true; stance = "Not set"; legacyImported = false
    }
}

@Model final class SavedPractice {
    var id: UUID = UUID()
    var date: Date = Date.now
    var payload: Data = Data()
    init(_ record: SessionRecord) throws {
        id = record.id; date = record.date; payload = try JSONEncoder().encode(record)
    }
    func record() throws -> SessionRecord { try JSONDecoder().decode(SessionRecord.self, from: payload) }
}

@Model final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var name: String = ""
    var serving: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var source: String = ""
    var assumptions: String = ""
    init(id: UUID = UUID(), date: Date, draft: MealDraft) {
        self.id = id; self.date = date; name = draft.name; serving = draft.serving
        calories = draft.calories; protein = draft.protein; carbs = draft.carbs; fat = draft.fat
        source = draft.source; assumptions = draft.assumptions
    }
    var draft: MealDraft {
        MealDraft(name: name, serving: serving, calories: calories, protein: protein, carbs: carbs,
                  fat: fat, source: source, assumptions: assumptions)
    }
    func update(_ draft: MealDraft, date: Date) {
        self.date = date; name = draft.name; serving = draft.serving; calories = draft.calories
        protein = draft.protein; carbs = draft.carbs; fat = draft.fat
        source = draft.source; assumptions = draft.assumptions
    }
}

@Model final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var millilitres: Int = 0
    init(date: Date, millilitres: Int) { id = UUID(); self.date = date; self.millilitres = millilitres }
}

@Model final class NutritionTargets {
    var key: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var water: Int = 0
    var proposalData: Data?
    var policyID: String?
    var acceptedAt: Date?
    init() { key = "primary"; calories = 0; protein = 0; carbs = 0; fat = 0; water = 0 }
}

@Model final class CoachMessage {
    var id: UUID = UUID()
    var date: Date = Date.now
    var role: String = ""
    var text: String = ""
    init(role: String, text: String) { id = UUID(); date = .now; self.role = role; self.text = text }
}

@Model final class LocalVideo {
    var id: UUID = UUID()
    var date: Date = Date.now
    var title: String = ""
    var filename: String = ""
    var kind: String = ""
    var notes: String = ""
    var subjectCode: String = ""
    var setupCode: String = ""
    init(filename: String, title: String, kind: String) {
        id = UUID(); date = .now; self.filename = filename; self.title = title; self.kind = kind; notes = ""
        subjectCode = ""; setupCode = ""
    }
}

@Model final class VideoMarker {
    var id: UUID = UUID()
    var videoID: UUID = UUID()
    var startSeconds: Double = 0
    var endSeconds: Double = 0
    var action: String = ""
    var note: String = ""
    init(videoID: UUID, start: Double, end: Double, action: String, note: String) {
        id = UUID(); self.videoID = videoID; startSeconds = start; endSeconds = end; self.action = action; self.note = note
    }
}

enum LocalDatabase {
    static var schema: Schema {
        Schema([LocalPreferences.self, SavedPractice.self, MealEntry.self, WaterEntry.self,
                NutritionTargets.self, CoachMessage.self, LocalVideo.self, VideoMarker.self, AIClipReport.self, AthleteProfile.self, PlannedPractice.self, WorkoutCompletion.self, WorkoutDraft.self, SavedWorkoutPlan.self, SavedSessionDraft.self, AcceptedTrainingPlan.self])
    }
    static func open(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: iCloud

    static let cloudContainerID = "iCloud.com.boxing.prototype"
    enum SyncState: Equatable, Sendable { case on, off, signedOut, unavailable(String) }
    private(set) nonisolated(unsafe) static var syncState: SyncState = .off
    private static let syncKey = "sync.iCloud.enabled"
    /// User preference; takes effect the next time the store opens (app launch).
    static var syncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: syncKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: syncKey) }
    }

    /// The app's store, mirrored to the user's private iCloud database when sync is on
    /// and an iCloud account is available. Uses the same file as the local store, so
    /// existing data is kept and uploaded. Falls back to local-only if CloudKit cannot start.
    static func openForApp() throws -> ModelContainer {
        guard syncEnabled else { syncState = .off; return try open() }
        guard FileManager.default.ubiquityIdentityToken != nil else { syncState = .signedOut; return try open() }
        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            let container = try ModelContainer(for: schema, configurations: [configuration])
            syncState = .on
            return container
        } catch {
            syncState = .unavailable(error.localizedDescription)
            return try open()
        }
    }
}

struct MealDraft: Codable, Equatable, Sendable {
    var name = ""
    var serving = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var source = "Manual"
    var assumptions = ""
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 &&
        [calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 100_000 }
    }
}

struct NutritionTotals: Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var water: Int = 0
}
