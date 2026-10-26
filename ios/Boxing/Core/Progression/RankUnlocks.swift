import Foundation

/// What each rank opens up. Learning content (drills, programs, reviews) is never
/// locked; ranks unlock harder and longer sparring. Experienced boxers can skip
/// ahead on difficulty by beating a score challenge on the level below.
struct RankUnlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case difficulty(SparringConfiguration.Difficulty)
        case rounds(Int)
        case roundSeconds(Int)
        case proCombos, suddenDeath, goldTargets, hallOfFame
    }
    struct Challenge: Equatable, Sendable {
        let on: SparringConfiguration.Difficulty
        let score: Int
        let accuracy: Double
        var text: String { String(localized: "or score \(score.formatted()) at \(on.title) with \(Int(accuracy * 100))% accuracy") }
        func met(by summary: SparringSummary) -> Bool {
            summary.configuration.mode == .arcade && summary.configuration.difficulty == on && summary.score >= score && summary.accuracy >= accuracy
        }
    }
    let id: String
    let minimumLevel: Int
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    var challenge: Challenge? = nil
    var rank: BoxRank { Progression.rank(forLevel: minimumLevel) }
}

struct UnlockState: Equatable, Sendable {
    var unlocked: Set<String>
    var difficulties: [SparringConfiguration.Difficulty]
    var maxRounds: Int
    var roundSeconds: [Int]
    var proCombos: Bool
    var suddenDeath: Bool
    var goldTargets: Bool
    /// The next unlock still to earn, if any.
    var next: RankUnlock?
    func isUnlocked(_ unlock: RankUnlock) -> Bool { unlocked.contains(unlock.id) }
    func allows(_ difficulty: SparringConfiguration.Difficulty) -> Bool { difficulties.contains(difficulty) }
}

enum RankUnlocks {
    static let all: [RankUnlock] = [
        .init(id: "rookie", minimumLevel: 1, kind: .difficulty(.rookie), title: String(localized: "Rookie sparring"), detail: String(localized: "Single moves and short combos, 3 rounds."), symbol: "figure.boxing"),
        .init(id: "rounds-4", minimumLevel: 3, kind: .rounds(4), title: String(localized: "4-round fights"), detail: String(localized: "One more round to build your engine."), symbol: "4.circle.fill"),
        .init(id: "contender", minimumLevel: 5, kind: .difficulty(.contender), title: String(localized: "Contender difficulty"), detail: String(localized: "Real combinations at a steady pace."), symbol: "bolt.fill",
              challenge: .init(on: .rookie, score: 2_500, accuracy: 0.75)),
        .init(id: "rounds-6", minimumLevel: 8, kind: .rounds(6), title: String(localized: "6-round fights"), detail: String(localized: "Amateur championship distance."), symbol: "6.circle.fill"),
        .init(id: "seconds-120", minimumLevel: 8, kind: .roundSeconds(120), title: String(localized: "2-minute rounds"), detail: String(localized: "Longer rounds test your pace."), symbol: "timer"),
        .init(id: "champion", minimumLevel: 11, kind: .difficulty(.champion), title: String(localized: "Champion difficulty"), detail: String(localized: "Long, fast combinations and tight timing."), symbol: "star.fill",
              challenge: .init(on: .contender, score: 5_000, accuracy: 0.75)),
        .init(id: "seconds-180", minimumLevel: 14, kind: .roundSeconds(180), title: String(localized: "3-minute rounds"), detail: String(localized: "The professional round."), symbol: "timer"),
        .init(id: "pro-combos", minimumLevel: 17, kind: .proCombos, title: String(localized: "Pro combinations"), detail: String(localized: "Five- and six-move strings mixed into Contender and above."), symbol: "medal.fill"),
        .init(id: "sudden-death", minimumLevel: 20, kind: .suddenDeath, title: String(localized: "Sudden death"), detail: String(localized: "One life. Any miss ends the fight. Bonus XP stays the same; bragging rights do not."), symbol: "heart.slash.fill"),
        .init(id: "rounds-12", minimumLevel: 24, kind: .rounds(12), title: String(localized: "12-round title fights"), detail: String(localized: "Championship distance."), symbol: "flag.checkered"),
        .init(id: "undisputed", minimumLevel: 28, kind: .difficulty(.undisputed), title: String(localized: "Undisputed difficulty"), detail: String(localized: "The fastest targets and tightest windows in BOX."), symbol: "crown.fill",
              challenge: .init(on: .champion, score: 8_000, accuracy: 0.8)),
        .init(id: "gold-targets", minimumLevel: 33, kind: .goldTargets, title: String(localized: "Gold targets"), detail: String(localized: "Your arena targets glow gold."), symbol: "sparkles"),
        .init(id: "hall-of-fame", minimumLevel: 40, kind: .hallOfFame, title: String(localized: "Hall of Fame"), detail: String(localized: "Every unlock, and your name among the greats."), symbol: "building.columns.fill")
    ]

    static func unlocks(for rank: BoxRank) -> [RankUnlock] {
        let next = Progression.ranks.first { $0.index == rank.index + 1 }?.minimumLevel ?? Int.max
        return all.filter { $0.minimumLevel >= rank.minimumLevel && $0.minimumLevel < next }
    }

    static func state(level: Int, sparring: [SparringSummary]) -> UnlockState {
        let open = all.filter { u in u.minimumLevel <= level || (u.challenge.map { c in sparring.contains(where: c.met) } ?? false) }
        let ids = Set(open.map(\.id))
        var difficulties: [SparringConfiguration.Difficulty] = []
        var rounds = 3, seconds = [45, 60]
        var pro = false, sudden = false, gold = false
        for u in open {
            switch u.kind {
            case .difficulty(let d): difficulties.append(d)
            case .rounds(let n): rounds = max(rounds, n)
            case .roundSeconds(let s): seconds.append(s)
            case .proCombos: pro = true
            case .suddenDeath: sudden = true
            case .goldTargets: gold = true
            case .hallOfFame: break
            }
        }
        let order = SparringConfiguration.Difficulty.allCases
        return UnlockState(unlocked: ids, difficulties: order.filter(difficulties.contains), maxRounds: rounds, roundSeconds: seconds.sorted(),
                           proCombos: pro, suddenDeath: sudden, goldTargets: gold, next: all.first { !ids.contains($0.id) })
    }

    /// Clamps a configuration to what is unlocked.
    static func clamp(_ config: SparringConfiguration, to state: UnlockState) -> SparringConfiguration {
        var c = config
        if !state.allows(c.difficulty) { c.difficulty = state.difficulties.last ?? .rookie }
        c.rounds = min(c.rounds, state.maxRounds)
        if !state.roundSeconds.contains(c.roundSeconds) { c.roundSeconds = state.roundSeconds.filter { $0 <= c.roundSeconds }.last ?? 60 }
        if !state.proCombos { c.proCombos = nil }
        if !state.suddenDeath { c.suddenDeath = nil }
        return c
    }
}
