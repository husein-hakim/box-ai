import Foundation
import Testing
@testable import BoxingCore

/// Opt-in live comparison of text providers on BOX's real prompts (touch /tmp/boxqa/live-ai).
/// Writes timings and validity to /tmp/boxqa/bench.txt. Not part of normal runs.
struct ProviderBenchmarkTests {
    static var enabled: Bool { FileManager.default.fileExists(atPath: "/tmp/boxqa/live-ai") }

    @MainActor func context(beginner: Bool) throws -> PlanningContext {
        let store = try AppStore(container: LocalDatabase.open(inMemory: true))
        if beginner {
            store.saveProfile(name: "", experience: "Beginner", goal: "General boxing", equipment: [], space: "Small indoor space", minutes: 30)
            store.selectedDays = [2, 4, 6]
        } else {
            store.saveProfile(name: "", experience: "Intermediate", goal: "Learn every punch & defense", equipment: ["Dumbbells", "Skipping rope", "Gloves"], space: "Open indoor space", minutes: 45)
            store.selectedDays = [2, 3, 5, 6, 7]
        }
        return store.planningContext()
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(15))) @MainActor func compareTextProviders() async throws {
        var lines: [String] = []
        for provider in [QwenClient.TextProvider.qwen, .gemini] {
            var client = QwenClient(); client.textProvider = provider
            let suite = "box.bench.\(provider.rawValue)"; UserDefaults().removePersistentDomain(forName: suite)
            client.usage = AIUsage(defaults: UserDefaults(suiteName: suite)!)
            for beginner in [true, false, true, false] {
                let ctx = try context(beginner: beginner)
                let start = Date()
                var outcome = "ok"
                do {
                    let plan = try await client.proposeTrainingPlan(context: ctx)
                    outcome = "valid · \(plan.days.filter { !$0.session.activities.isEmpty }.count) sessions · \(plan.title)"
                } catch { outcome = "FAILED · \(error)".prefix(300).description }
                lines.append("\(provider.rawValue) plan \(beginner ? "beginner" : "intermediate"): \(String(format: "%.1f", Date().timeIntervalSince(start))) s · \(outcome)")
            }
            for _ in 0..<3 {
                let start = Date()
                let reply = try? await client.complete(messages: [.init(role: "system", content: "You are a concise boxing coach."), .init(role: "user", content: "My rear hand drops when I throw a jab. What should I practise this week?")])
                lines.append("\(provider.rawValue) coach reply: \(String(format: "%.1f", Date().timeIntervalSince(start))) s · \(reply?.count ?? 0) chars")
            }
        }
        try lines.joined(separator: "\n").write(toFile: "/tmp/boxqa/bench.txt", atomically: true, encoding: .utf8)
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(5))) @MainActor func adaptivePlanCitesTheData() async throws {
        let store = try AppStore(container: LocalDatabase.open(inMemory: true))
        store.saveProfile(name: "", experience: "Intermediate", goal: "Learn every punch & defense", equipment: ["Dumbbells"], space: "Open indoor space", minutes: 40)
        store.selectedDays = [2, 4, 6, 7]
        for d in 1...6 {
            let date = Calendar.current.date(byAdding: .day, value: -d * 2, to: .now)!
            var fight = SparringSummary(configuration: .init(difficulty: .contender), score: 3200, maxStreak: 14, hits: 40, attempts: 60)
            fight.moves = ["Left hook": .init(asked: 12, hit: 5), "Jab": .init(asked: 20, hit: 19), "Slip right": .init(asked: 8, hit: 6)]
            _ = store.record(SessionRecord(id: UUID(), date: date, focus: .mixed, activeSeconds: 900, workSeconds: 900, completedRounds: 3, skippedBlocks: 0, issuedCues: 0, finished: true, sparring: fight))
            let session = GuidedSession(title: "Power day", type: .strength, activities: [.init(id: "a", activityID: "db-row-v1", mode: .guided, sets: 3, reps: 8, workSeconds: 60, restSeconds: 30)])
            _ = store.record(SessionRecord(id: UUID(), date: date.addingTimeInterval(-3600), focus: .mixed, activeSeconds: 1500, workSeconds: 1500, completedRounds: 2, skippedBlocks: 0, issuedCues: 0, finished: true,
                                           guided: GuidedSummary(execution: GuidedExecution(session: session), feedback: "Exhausted", effort: 4)))
        }
        let context = store.planningContext(feedback: "Check-in: last week felt too hard.")
        var client = QwenClient(); client.textProvider = .gemini
        let suite = "box.bench.adaptive"; UserDefaults().removePersistentDomain(forName: suite)
        client.usage = AIUsage(defaults: UserDefaults(suiteName: suite)!)
        let start = Date()
        let plan = try await client.proposeTrainingPlan(context: context)
        let blocks = plan.days.flatMap { $0.session.activities.map(\.activityID) }
        let report = "notes: \(context.adaptive?.coachNotes ?? [])\n\n\(String(format: "%.1f", Date().timeIntervalSince(start))) s\ntitle: \(plan.title)\nprogression: \(plan.progression)\nlead hook blocks: \(blocks.filter { $0 == "lead-hook-v1" }.count)\nall: \(blocks)"
        try report.write(toFile: "/tmp/boxqa/adaptive.txt", atomically: true, encoding: .utf8)
        #expect(blocks.contains("lead-hook-v1"))
    }

    @Test(.enabled(if: enabled)) func liveDebriefUsesOnlyTheFacts() async throws {
        var fight = SparringSummary(configuration: .init(difficulty: .contender), score: 4200, maxStreak: 18, hits: 31, attempts: 40)
        fight.moves = ["Left hook": .init(asked: 12, hit: 5), "Jab": .init(asked: 16, hit: 15), "Duck": .init(asked: 12, hit: 11)]
        let record = SessionRecord(id: UUID(), date: .now, focus: .mixed, activeSeconds: 180, workSeconds: 180, completedRounds: 3, skippedBlocks: 0, issuedCues: 0, finished: true, sparring: fight)
        let facts = SessionFacts.make(record, history: [], stance: .orthodox)
        var client = QwenClient(); client.textProvider = .gemini
        client.usage = AIUsage(defaults: UserDefaults(suiteName: "box.bench.debrief.\(UUID())")!)
        let start = Date()
        let d = try await client.debrief(prompt: facts.prompt(profile: "Intermediate boxer, orthodox stance, goal: Learn every punch & defense.", nextSession: "Defense & hooks", adjustment: "Added Lead hook on camera for your left hook (41%)", reviewFocus: ["Rear hand drops on the hook (cue: Glove on cheek)"]))
        try "\(String(format: "%.1f", Date().timeIntervalSince(start))) s\n\(d)".write(toFile: "/tmp/boxqa/debrief.txt", atomically: true, encoding: .utf8)
    }
}
