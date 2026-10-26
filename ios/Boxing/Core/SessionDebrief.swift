import Foundation

/// Coaching feedback after any session: what went well, what to work on, and
/// what changes next time. An instant version is computed from the data; the
/// coach (AI) rewrites it in a natural voice when available.
struct SessionDebrief: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Identifiable, Sendable {
        var title: String
        var detail: String
        var id: String { title }
    }
    var headline: String
    var good: [Point]
    var workOn: [Point]
    var next: String
    /// "auto" (computed) or "coach" (AI-written).
    var source: String

    func sanitized() -> SessionDebrief? {
        func clean(_ s: String, _ n: Int) -> String { String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(n)) }
        var d = self
        d.headline = clean(headline, 90); d.next = clean(next, 300)
        d.good = good.prefix(2).map { .init(title: clean($0.title, 60), detail: clean($0.detail, 240)) }.filter { !$0.title.isEmpty }
        d.workOn = workOn.prefix(2).map { .init(title: clean($0.title, 60), detail: clean($0.detail, 240)) }.filter { !$0.title.isEmpty }
        guard !d.headline.isEmpty, !(d.good.isEmpty && d.workOn.isEmpty) else { return nil }
        return d
    }
}

/// Measured facts about one session, compared with earlier ones.
struct SessionFacts: Sendable {
    struct Move: Sendable { let name: String; let asked: Int; let hit: Int; let previous: Double? ; var accuracy: Double { asked > 0 ? Double(hit) / Double(asked) : 0 } }
    var kind: String
    var title: String
    var minutes: Int
    var completed = 0, partial = 0, skipped = 0
    var skippedTitles: [String] = []
    var effort: Int?
    var feedback: String?
    var moves: [Move] = []
    var score: Int?
    var previousBest: Int?
    var accuracy: Double?
    var previousAccuracy: Double?
    var maxStreak: Int?
    var knockedOut = false
    var padHits: Int?, padAttempts: Int?
    var weakest: Move? { moves.filter { $0.asked >= 4 }.min { $0.accuracy < $1.accuracy } }
    var strongest: Move? { moves.filter { $0.asked >= 4 }.max { $0.accuracy < $1.accuracy } }

    static func make(_ record: SessionRecord, history: [SessionRecord], stance: BoxMaxxingJudge.Stance) -> SessionFacts {
        let earlier = history.filter { $0.id != record.id && $0.date < record.date }
        var f = SessionFacts(kind: "rounds", title: String(localized: record.focus.title), minutes: Int((record.workSeconds / 60).rounded()))
        if let guided = record.guided {
            f.kind = "guided"; f.title = guided.title
            f.completed = guided.completed; f.partial = guided.partial; f.skipped = guided.skipped
            f.effort = guided.effort; f.feedback = guided.feedback.flatMap { $0.isEmpty ? nil : $0 }
            let e = guided.execution
            f.skippedTitles = e.session.activities.indices.filter { e.outcome(at: $0) == .skipped }.compactMap { ActivityCatalog.find(e.session.activities[$0].activityID)?.title }
            let cameraAttempts = e.results.flatMap { $0.cameraSets ?? [] }.flatMap(\.state.attempts)
            if !cameraAttempts.isEmpty { f.padAttempts = cameraAttempts.count; f.padHits = cameraAttempts.filter(\.isHit).count }
        }
        if let pad = record.pad { f.kind = "pads"; f.padAttempts = pad.attempts.count; f.padHits = pad.attempts.filter(\.isHit).count }
        if let s = record.sparring {
            f.kind = s.configuration.mode == .arcade ? "sparring" : s.configuration.mode == .drill ? "camera drill" : "detection check"
            f.title = s.configuration.drillTitle ?? String(localized: "Sparring · \(s.configuration.difficulty.title)")
            f.score = s.configuration.mode == .arcade ? s.score : nil
            f.accuracy = s.accuracy; f.maxStreak = s.maxStreak; f.knockedOut = s.knockedOut
            let prior = earlier.sorted { $0.date > $1.date }.compactMap(\.sparring)
            f.previousBest = prior.filter { $0.configuration.mode == .arcade && $0.configuration.difficulty == s.configuration.difficulty }.map(\.score).max()
            let recentPrior = Array(prior.prefix(5))
            f.previousAccuracy = recentPrior.isEmpty ? nil : recentPrior.map(\.accuracy).reduce(0, +) / Double(recentPrior.count)
            f.moves = s.moves.map { name, stats in
                let a = recentPrior.reduce(0) { $0 + ($1.moves[name]?.asked ?? 0) }, h = recentPrior.reduce(0) { $0 + ($1.moves[name]?.hit ?? 0) }
                return Move(name: name, asked: stats.asked, hit: stats.hit, previous: a >= 4 ? Double(h) / Double(a) : nil)
            }.sorted { $0.name < $1.name }
        }
        return f
    }

    var text: String {
        var lines = ["Session: \(title) (\(kind)), \(minutes) min of timed work."]
        if kind == "guided" {
            lines.append("Blocks: \(completed) completed, \(partial) partial, \(skipped) skipped\(skippedTitles.isEmpty ? "" : " (skipped: \(skippedTitles.joined(separator: ", ")))").")
        }
        if let effort { lines.append("Effort rating: \(["", "too easy", "just right", "hard", "too hard"][min(4, max(1, effort))]).") }
        if let feedback { lines.append("Their note: \(feedback.prefix(300))") }
        if let h = padHits, let a = padAttempts, a > 0 { lines.append("Camera punches recognised as asked: \(h) of \(a).") }
        if let score { lines.append("Score \(score)\(previousBest.map { $0 > 0 ? " (previous best \($0))" : "" } ?? ""). Best streak \(maxStreak ?? 0).\(knockedOut ? " Lost all lives." : "")") }
        if let accuracy { lines.append("Accuracy \(Int(accuracy * 100))%\(previousAccuracy.map { " (recent average \(Int($0 * 100))%)" } ?? "").") }
        if !moves.isEmpty {
            lines.append("Per move: " + moves.map { m in "\(m.name) \(m.hit)/\(m.asked)" + (m.previous.map { " (was \(Int($0 * 100))%)" } ?? "") }.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// The instant debrief: plain rules over the facts.
    func autoDebrief(nextSession: String?) -> SessionDebrief {
        var good: [SessionDebrief.Point] = [], work: [SessionDebrief.Point] = []
        if let score, let best = previousBest, score > best { good.append(.init(title: String(localized: "New best: \(score.formatted())"), detail: String(localized: "Up from \(best.formatted()).") )) }
        if let s = strongest, s.accuracy >= 0.8 { good.append(.init(title: String(localized: "\(s.name) is sharp"), detail: String(localized: "\(s.hit) of \(s.asked) on time\(s.previous.map { $0 < s.accuracy - 0.05 ? ", up from \(Int($0 * 100))%" : "" } ?? "").") )) }
        if let a = accuracy, let p = previousAccuracy, a >= p + 0.08 { good.append(.init(title: String(localized: "Cleaner than usual"), detail: String(localized: "\(Int(a * 100))% accuracy against your recent \(Int(p * 100))%.") )) }
        if kind == "guided", skipped == 0, partial == 0, completed > 0 { good.append(.init(title: String(localized: "Every block finished"), detail: String(localized: "\(completed) of \(completed) done.") )) }
        if let h = padHits, let a = padAttempts, a >= 6, Double(h) / Double(a) >= 0.8 { good.append(.init(title: String(localized: "Accurate punches"), detail: String(localized: "\(h) of \(a) recognised as asked.") )) }
        if let w = weakest, w.accuracy < 0.65 { work.append(.init(title: String(localized: "\(w.name) needs reps"), detail: String(localized: "\(w.hit) of \(w.asked) this time. Slow it down and make the shape clean before adding speed.") )) }
        if !skippedTitles.isEmpty { work.append(.init(title: String(localized: "Skipped: \(skippedTitles.prefix(2).joined(separator: ", "))"), detail: String(localized: "If it didn't fit, your next week will swap or shorten it.") )) }
        if effort == 4 { work.append(.init(title: String(localized: "That was too much"), detail: String(localized: "Next session gets lighter so you can recover and keep the habit.") )) }
        if knockedOut { work.append(.init(title: String(localized: "Ran out of lives"), detail: String(localized: "Stay on the beat rather than rushing; misses cost more than late hits.") )) }
        if good.isEmpty { good.append(.init(title: String(localized: "Work in the bank"), detail: String(localized: "\(minutes) minutes done. Consistency is what builds skill.") )) }
        let headline = !work.isEmpty && good.count <= 1 ? String(localized: "Good work. One thing to sharpen.") : String(localized: "Strong session.")
        return SessionDebrief(headline: headline, good: Array(good.prefix(2)), workOn: Array(work.prefix(2)),
                              next: nextSession.map { String(localized: "Next up: \($0).") } ?? String(localized: "Keep the streak going tomorrow."), source: "auto")
    }

    func prompt(profile: String, nextSession: String?, adjustment: String?, reviewFocus: [String]) -> String {
        """
        You are the BOX coach talking to your boxer straight after a session. Be warm, direct and specific, like a coach on the gym floor. Use only the facts below; never invent numbers or moves.

        FACTS (measured by the app; camera numbers are estimates)
        \(text)
        Profile: \(profile)
        Their current fixes from clip reviews: \(reviewFocus.isEmpty ? "none" : reviewFocus.joined(separator: "; "))
        Next planned session: \(nextSession ?? "none")
        Change the app is proposing for it: \(adjustment ?? "none")

        Return JSON only:
        {"headline":"Five to eight words","good":[{"title":"Short","detail":"One sentence with the number that proves it"}],"workOn":[{"title":"Short","detail":"One sentence: what to do about it, with a cue"}],"next":"One or two sentences on what happens next session and why (mention the proposed change if there is one)"}
        good: 1–2 items. workOn: 0–2 items, each tied to a specific measured weakness above (a low move, skipped blocks, a too-hard rating, lost lives); leave it empty rather than giving generic advice. No medical advice; if they mention pain, tell them to rest and see a professional.
        """
    }
}

/// A small, validated change to the next planned session based on how this one went.
struct SessionAdjustment: Equatable, Sendable {
    var summary: String
    var session: GuidedSession

    static func propose(facts: SessionFacts, next: GuidedSession, stance: BoxMaxxingJudge.Stance, validate: (GuidedSession) -> [String]) -> SessionAdjustment? {
        let fixed: Set<ActivityKind> = [.warmup, .cooldown, .mobility]
        func main(_ s: GuidedSession) -> [Int] { s.activities.indices.filter { ActivityCatalog.find(s.activities[$0].activityID).map { !fixed.contains($0.kind) } ?? false } }
        var s = next
        var changes: [String] = []
        let tooHard = facts.effort == 4 || (facts.kind == "guided" && facts.skipped + facts.partial >= max(2, (facts.completed + facts.skipped + facts.partial) / 2))
        let tooEasy = facts.effort == 1 && facts.skipped == 0 && facts.partial == 0
        if tooHard {
            var names: [String] = []
            for i in main(s) where s.activities[i].sets > 1 { s.activities[i].sets -= 1; names.append(ActivityCatalog.find(s.activities[i].activityID)?.title ?? "") }
            if !names.isEmpty { changes.append(String(localized: "one fewer set on \(names.prefix(3).joined(separator: ", "))")) }
        } else if tooEasy {
            var names: [String] = []
            for i in main(s).prefix(2) {
                guard let a = ActivityCatalog.find(s.activities[i].activityID), s.activities[i].sets < a.support.maxSets else { continue }
                s.activities[i].sets += 1
                if s.activities[i].sets > 1 && s.activities[i].restSeconds < 15 { s.activities[i].restSeconds = min(30, a.support.maxRest) }
                names.append(a.title)
            }
            if !names.isEmpty { changes.append(String(localized: "an extra set on \(names.joined(separator: ", "))")) }
        }
        if let weak = facts.weakest, weak.accuracy < 0.6, weak.asked >= 6, let drillID = AdaptiveSummary.drill(forMove: weak.name, stance: stance),
           !s.activities.contains(where: { $0.activityID == drillID }), let drill = ActivityCatalog.find(drillID) {
            let mode: TrainingMode = CameraPlanningCapability.supports(drillID) && drill.modes.contains(.camera) ? .camera : (drill.modes.contains(.shadowboxing) ? .shadowboxing : drill.modes.first ?? .guided)
            let block = ActivityPrescription(id: drillID + "-adapt", activityID: drillID, mode: mode, sets: 2, reps: drill.support.kind == .timed ? 0 : min(8, drill.support.maxReps),
                                             workSeconds: min(max(60, drill.support.minWork), drill.support.maxWork), restSeconds: min(30, drill.support.maxRest), difficulty: drill.difficulty)
            let insertAt = s.activities.lastIndex { ActivityCatalog.find($0.activityID)?.kind == .cooldown } ?? s.activities.endIndex
            var candidate = s
            candidate.activities.insert(block, at: insertAt)
            // Make room within the time budget by trimming the longest main block if needed.
            var tries = 0
            while !validate(candidate).isEmpty && tries < 4, let longest = main(candidate).filter({ candidate.activities[$0].id != block.id && candidate.activities[$0].sets > 1 }).max(by: { candidate.activities[$0].estimatedSeconds < candidate.activities[$1].estimatedSeconds }) {
                candidate.activities[longest].sets -= 1; tries += 1
            }
            if validate(candidate).isEmpty { s = candidate; changes.append(String(localized: "added \(drill.title)\(mode == .camera ? " on camera" : "") for your \(weak.name.lowercased()) (\(Int(weak.accuracy * 100))%)")) }
        }
        guard !changes.isEmpty, s != next, validate(s).isEmpty else { return nil }
        return SessionAdjustment(summary: changes.joined(separator: "; ").prefix(1).uppercased() + changes.joined(separator: "; ").dropFirst(), session: s)
    }
}
