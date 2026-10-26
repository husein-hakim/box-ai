import Foundation
import Testing
@testable import BoxingCore

struct RankUnlockTests {
    func fight(_ d: SparringConfiguration.Difficulty, score: Int, hits: Int, attempts: Int) -> SparringSummary {
        SparringSummary(configuration: .init(difficulty: d), score: score, maxStreak: 10, hits: hits, attempts: attempts)
    }

    @Test func newBoxerHasRookieOnly() {
        let s = RankUnlocks.state(level: 1, sparring: [])
        #expect(s.difficulties == [.rookie] && s.maxRounds == 3 && s.roundSeconds == [45, 60])
        #expect(!s.proCombos && !s.suddenDeath)
        #expect(s.next?.id == "rounds-4")
    }

    @Test func levelsOpenEverythingInOrder() {
        #expect(RankUnlocks.state(level: 5, sparring: []).difficulties == [.rookie, .contender])
        let amateur = RankUnlocks.state(level: 8, sparring: [])
        #expect(amateur.maxRounds == 6 && amateur.roundSeconds == [45, 60, 120])
        let hof = RankUnlocks.state(level: 40, sparring: [])
        #expect(hof.difficulties == SparringConfiguration.Difficulty.allCases && hof.maxRounds == 12 && hof.proCombos && hof.suddenDeath && hof.goldTargets && hof.next == nil)
    }

    @Test func scoreChallengeSkipsAheadOnlyWhenMet() {
        let close = fight(.rookie, score: 2_600, hits: 70, attempts: 100)       // 70% accuracy: not enough
        #expect(!RankUnlocks.state(level: 1, sparring: [close]).allows(.contender))
        let met = fight(.rookie, score: 2_600, hits: 80, attempts: 100)
        let s = RankUnlocks.state(level: 1, sparring: [met])
        #expect(s.allows(.contender) && !s.allows(.champion))
        var drill = met; drill.configuration.mode = .drill
        #expect(!RankUnlocks.state(level: 1, sparring: [drill]).allows(.contender))
    }

    @Test func clampKeepsSetupInsideUnlocks() {
        var config = SparringConfiguration(difficulty: .champion, rounds: 8, roundSeconds: 180)
        config.proCombos = true; config.suddenDeath = true
        let c = RankUnlocks.clamp(config, to: RankUnlocks.state(level: 8, sparring: []))
        #expect(c.difficulty == .contender && c.rounds == 6 && c.roundSeconds == 120 && c.proCombos == nil && c.suddenDeath == nil)
    }

    @Test func everyRankLadderEntryIsCovered() {
        let total = Progression.ranks.flatMap { RankUnlocks.unlocks(for: $0) }
        #expect(total.map(\.id) == RankUnlocks.all.map(\.id))
        #expect(Progression.ranks.allSatisfy { !RankUnlocks.unlocks(for: $0).isEmpty })
    }

    @Test func suddenDeathAndProCombosChangeTheFight() {
        var config = SparringConfiguration(difficulty: .champion); config.suddenDeath = true; config.proCombos = true
        #expect(config.startingLives == 1)
        #expect(SparringConfiguration.Difficulty.undisputed.xpMultiplier > SparringConfiguration.Difficulty.champion.xpMultiplier)
    }
}
