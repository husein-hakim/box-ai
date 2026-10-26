import Foundation

/// Fast-paced sparring: pads and incoming attacks arrive on a rhythm and the
/// fighter answers each with the right move, on time. Pure game logic on the
/// capture clock (milliseconds), fully deterministic for a given seed.
struct SparringConfiguration: Codable, Equatable, Sendable {
    enum Difficulty: String, Codable, CaseIterable, Sendable {
        case rookie, contender, champion, undisputed
        var title: String {
            switch self { case .rookie: String(localized: "Rookie"); case .contender: String(localized: "Contender"); case .champion: String(localized: "Champion"); case .undisputed: String(localized: "Undisputed") }
        }
        /// Time a target is visible before it must be hit.
        var approachMs: Double { switch self { case .rookie: 1300; case .contender: 1050; case .champion: 850; case .undisputed: 720 } }
        /// Gap between beats inside a combination.
        var comboGapMs: Double { switch self { case .rookie: 750; case .contender: 560; case .champion: 430; case .undisputed: 370 } }
        /// Breather between combinations.
        var restGapMs: Double { switch self { case .rookie: 1500; case .contender: 1150; case .champion: 900; case .undisputed: 780 } }
        /// Half-width of the timing window around the arrival time.
        var windowMs: Double { switch self { case .rookie: 520; case .contender: 420; case .champion: 340; case .undisputed: 290 } }
        var lives: Int { switch self { case .rookie: 5; case .contender: 4; case .champion: 3; case .undisputed: 3 } }
        /// XP multiplier for sparring.
        var xpMultiplier: Double { switch self { case .rookie: 1; case .contender: 1.25; case .champion: 1.5; case .undisputed: 1.75 } }
    }
    enum Mode: String, Codable, Sendable { case arcade, check, drill }
    var difficulty: Difficulty = .contender
    var mode: Mode = .arcade
    var stance: BoxMaxxingJudge.Stance = .orthodox
    var rounds = 3
    var roundSeconds = 60
    var restSeconds = 20
    /// Which moves may appear. Defaults to all of them.
    var kinds: Set<FightAction.Kind> = Set(FightAction.Kind.allCases)
    /// Drill mode: these moves repeat on the beat instead of random combinations.
    var sequence: [FightAction]? = nil
    var drillTitle: String? = nil
    /// Rank unlock: one life, any miss ends the fight.
    var suddenDeath: Bool? = nil
    /// Rank unlock: longer professional combinations in the mix.
    var proCombos: Bool? = nil
    /// Rank unlock (cosmetic): targets glow gold.
    var goldTargets: Bool? = nil
    var startingLives: Int { suddenDeath == true ? 1 : difficulty.lives }
    var isValid: Bool { (1...12).contains(rounds) && (20...300).contains(roundSeconds) && (5...120).contains(restSeconds) && !kinds.isEmpty }
}

struct SparringBeat: Identifiable, Equatable, Sendable {
    let id: Int
    let action: FightAction
    let spawnMs: Double
    let hitMs: Double
    /// Index of the combination this beat belongs to and its position in it.
    let combo: Int
    let step: Int
    let comboLength: Int
}

enum SparringGrade: String, Codable, Sendable {
    case perfect, great, good, miss, wrong
    var isHit: Bool { self == .perfect || self == .great || self == .good }
    var title: String {
        switch self {
        case .perfect: String(localized: "Perfect")
        case .great: String(localized: "Great")
        case .good: String(localized: "Good")
        case .miss: String(localized: "Miss")
        case .wrong: String(localized: "Wrong move")
        }
    }
}

struct SparringResult: Equatable, Sendable {
    let beat: SparringBeat
    let grade: SparringGrade
    let detected: FightAction?
    let offsetMs: Double?
    let points: Int
    let multiplier: Int
}

/// Per-move accounting, also the Detection-check confusion table.
struct SparringMoveStats: Codable, Equatable, Sendable {
    var asked = 0
    var hit = 0
    var perfect = 0
    var detectedAs: [String: Int] = [:]
    var totalOffsetMs = 0.0
    var averageOffsetMs: Double? { hit > 0 ? totalOffsetMs / Double(hit) : nil }
}

struct SparringSummary: Codable, Equatable, Sendable {
    var configuration: SparringConfiguration
    var score = 0
    var maxStreak = 0
    var hits = 0
    var attempts = 0
    var perfects = 0
    var roundsCompleted = 0
    var knockedOut = false
    var activeSeconds = 0.0
    var moves: [String: SparringMoveStats] = [:]
    var accuracy: Double { attempts > 0 ? Double(hits) / Double(attempts) : 0 }
}

struct SparringEngine {
    enum Phase: Equatable, Sendable { case ready, fighting, rest, finished }
    enum Event: Equatable, Sendable {
        case spawned(SparringBeat)
        case resolved(SparringResult)
        case roundStarted(Int)
        case roundEnded(Int)
        case knockedOut
        case finished
    }

    let configuration: SparringConfiguration
    private(set) var phase: Phase = .ready
    private(set) var round = 0
    private(set) var roundStartMs = 0.0
    private(set) var restUntilMs = 0.0
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var maxStreak = 0
    private(set) var lives: Int
    private(set) var hits = 0
    private(set) var attempts = 0
    private(set) var perfects = 0
    private(set) var active: [SparringBeat] = []
    private(set) var moves: [String: SparringMoveStats] = [:]
    private(set) var activeMs = 0.0
    private var queue: [SparringBeat] = []
    private var nextID = 0
    private var rng: SeededGenerator
    private var lastTickMs: Double?

    init(configuration: SparringConfiguration, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.configuration = configuration
        lives = configuration.startingLives
        rng = SeededGenerator(seed: seed)
    }

    /// 1 + one step per 8 consecutive hits, up to ×4.
    var multiplier: Int { min(4, 1 + streak / 8) }
    var roundRemainingMs: Double {
        switch phase {
        case .fighting: max(0, Double(configuration.roundSeconds) * 1000 - (lastTickMs.map { $0 - roundStartMs } ?? 0))
        case .rest: max(0, restUntilMs - (lastTickMs ?? restUntilMs))
        default: 0
        }
    }
    var summary: SparringSummary {
        SparringSummary(configuration: configuration, score: score, maxStreak: maxStreak, hits: hits, attempts: attempts, perfects: perfects,
                        roundsCompleted: phase == .finished && !knockedOut ? round : max(0, round - (phase == .fighting ? 1 : 0)),
                        knockedOut: knockedOut, activeSeconds: activeMs / 1000, moves: moves)
    }
    private(set) var knockedOut = false

    mutating func start(atMs now: Double) {
        guard phase == .ready else { return }
        startRound(atMs: now)
    }

    private mutating func startRound(atMs now: Double) {
        round += 1; phase = .fighting; roundStartMs = now; active = []
        queue = schedule(from: now + 800, until: now + Double(configuration.roundSeconds) * 1000)
    }

    /// Advance the clock: spawn due beats, expire missed ones, run rounds.
    mutating func update(atMs now: Double) -> [Event] {
        var events: [Event] = []
        if let last = lastTickMs, phase == .fighting { activeMs += max(0, min(500, now - last)) }
        lastTickMs = now
        switch phase {
        case .ready, .finished:
            return []
        case .rest:
            if now >= restUntilMs { startRound(atMs: now); events.append(.roundStarted(round)) }
            return events
        case .fighting:
            while let next = queue.first, next.spawnMs <= now {
                queue.removeFirst(); active.append(next); events.append(.spawned(next))
            }
            for beat in active where now > beat.hitMs + configuration.difficulty.windowMs {
                events.append(.resolved(resolve(beat, grade: .miss, detected: nil, offset: nil)))
            }
            if lives <= 0 && configuration.mode == .arcade {
                phase = .finished; knockedOut = true; active = []; queue = []
                events += [.knockedOut, .finished]
                return events
            }
            let timeUp = configuration.mode == .check || now - roundStartMs >= Double(configuration.roundSeconds) * 1000
            if queue.isEmpty && active.isEmpty && timeUp {
                events.append(.roundEnded(round))
                if round >= configuration.rounds || configuration.mode == .check {
                    phase = .finished; events.append(.finished)
                } else {
                    phase = .rest; restUntilMs = now + Double(configuration.restSeconds) * 1000
                }
            }
            return events
        }
    }

    /// Judge a recognised move against the targets currently in play.
    mutating func receive(_ move: DetectedMove) -> [Event] {
        guard phase == .fighting else { return [] }
        let window = configuration.difficulty.windowMs
        let inWindow = active.filter { abs(move.peakMs - $0.hitMs) <= window }.sorted { $0.hitMs < $1.hitMs }
        if let match = inWindow.first(where: { $0.action == move.action }) {
            let offset = move.peakMs - match.hitMs
            let magnitude = abs(offset)
            let grade: SparringGrade = magnitude <= window * 0.25 ? .perfect : magnitude <= window * 0.5 ? .great : .good
            return [.resolved(resolve(match, grade: grade, detected: move.action, offset: offset))]
        }
        // Wrong answer to the earliest target in its window. Straights that are
        // really the start of a combination are filtered by fusion upstream.
        if let target = inWindow.first {
            return [.resolved(resolve(target, grade: .wrong, detected: move.action, offset: move.peakMs - target.hitMs))]
        }
        return []
    }

    private mutating func resolve(_ beat: SparringBeat, grade: SparringGrade, detected: FightAction?, offset: Double?) -> SparringResult {
        active.removeAll { $0.id == beat.id }
        attempts += 1
        let key = beat.action.title(stance: configuration.stance)
        var stats = moves[key] ?? .init()
        stats.asked += 1
        stats.detectedAs[detected?.title(stance: configuration.stance) ?? String(localized: "Nothing"), default: 0] += 1
        var points = 0
        let currentMultiplier = multiplier
        if grade.isHit {
            hits += 1; streak += 1; maxStreak = max(maxStreak, streak)
            stats.hit += 1; stats.totalOffsetMs += offset ?? 0
            if grade == .perfect { perfects += 1; stats.perfect += 1 }
            let base = grade == .perfect ? 150 : grade == .great ? 100 : 60
            points = base * currentMultiplier
            // Finishing a whole combination clean is worth a bonus.
            if beat.step == beat.comboLength - 1 && beat.comboLength > 1 { points += 50 * beat.comboLength }
            score += points
        } else {
            streak = 0
            // Getting caught by an attack you did not dodge costs a life.
            if configuration.mode == .arcade && (beat.action.kind == .slip || beat.action.kind == .duck) { lives -= 1 }
        }
        moves[key] = stats
        return .init(beat: beat, grade: grade, detected: detected, offsetMs: offset, points: points, multiplier: currentMultiplier)
    }

    // MARK: Choreography

    private mutating func schedule(from start: Double, until end: Double) -> [SparringBeat] {
        let d = configuration.difficulty
        var beats: [SparringBeat] = []
        var t = start + d.approachMs
        var comboIndex = 0
        if configuration.mode == .check {
            // Every enabled move, four times, slowly, in a shuffled but even order.
            var deck = Self.checkMoves(kinds: configuration.kinds).flatMap { Array(repeating: $0, count: 4) }
            deck.shuffle(using: &rng)
            for action in deck {
                beats.append(beat(action, hit: t, combo: comboIndex, step: 0, length: 1)); comboIndex += 1
                t += 2600
            }
            return beats
        }
        while t < end {
            let combo = nextCombo()
            for (step, action) in combo.enumerated() where t < end {
                beats.append(beat(action, hit: t, combo: comboIndex, step: step, length: combo.count))
                t += d.comboGapMs
            }
            comboIndex += 1
            t += d.restGapMs - d.comboGapMs
        }
        return beats
    }

    private mutating func beat(_ action: FightAction, hit: Double, combo: Int, step: Int, length: Int) -> SparringBeat {
        defer { nextID += 1 }
        let approach = configuration.mode == .check ? 1600 : configuration.difficulty.approachMs
        return SparringBeat(id: nextID, action: action, spawnMs: hit - approach, hitMs: hit, combo: combo, step: step, comboLength: length)
    }

    static func checkMoves(kinds: Set<FightAction.Kind>) -> [FightAction] {
        var all: [FightAction] = []
        if kinds.contains(.straight) { all += [.straight(.left), .straight(.right)] }
        if kinds.contains(.hook) { all += [.hook(.left), .hook(.right)] }
        if kinds.contains(.uppercut) { all += [.uppercut(.left), .uppercut(.right)] }
        if kinds.contains(.slip) { all += [.slip(.left), .slip(.right)] }
        if kinds.contains(.duck) { all.append(.duck) }
        return all
    }

    /// Real boxing combinations, numbered the way coaches call them
    /// (1 jab, 2 cross, 3 lead hook, 4 rear hook, 5 lead uppercut, 6 rear uppercut).
    private mutating func nextCombo() -> [FightAction] {
        if let sequence = configuration.sequence, !sequence.isEmpty { return sequence }
        let lead: FightAction.Side = configuration.stance == .orthodox ? .left : .right
        let rear: FightAction.Side = lead == .left ? .right : .left
        let one = FightAction.straight(lead), two = FightAction.straight(rear)
        let three = FightAction.hook(lead), four = FightAction.hook(rear)
        let five = FightAction.uppercut(lead), six = FightAction.uppercut(rear)
        let slipIn = FightAction.slip(lead), slipOut = FightAction.slip(rear), duck = FightAction.duck
        var library: [[FightAction]]
        switch configuration.difficulty {
        case .rookie:
            library = [[one], [two], [one, two], [three], [four], [five], [six], [slipIn], [slipOut], [duck], [one, one], [one, two, three]]
        case .contender:
            library = [[one, two], [one, two, three], [one, two, slipOut], [duck, three], [five, three], [six, three, two],
                       [one, slipIn, two], [three, two], [two, three, two], [slipIn, two], [duck, four], [one, two, five, two]]
        case .champion, .undisputed:
            library = [[one, two, three, two], [one, six, three, two], [slipIn, two, three], [duck, three, two], [one, two, slipOut, two, three],
                       [five, six, three, four], [one, one, two, duck, two], [three, six, three], [slipOut, slipIn, two, three], [one, two, three, six, three, two]]
        }
        if configuration.proCombos == true && configuration.difficulty != .rookie {
            library += [[one, two, three, two, three, two], [one, two, five, two, three, two], [slipIn, two, three, two, duck, three], [one, one, two, three, six, three],
                        [six, three, two, slipOut, two, three], [duck, four, three, two, one, two]]
        }
        for _ in 0..<12 {
            let pick = library[Int.random(in: 0..<library.count, using: &rng)]
            if pick.allSatisfy({ configuration.kinds.contains($0.kind) }) { return pick }
        }
        // Fallback: a single move from the enabled kinds.
        let allowed = Self.checkMoves(kinds: configuration.kinds)
        return [allowed[Int.random(in: 0..<allowed.count, using: &rng)]]
    }
}

/// Deterministic random numbers (SplitMix64) so sessions are reproducible in tests.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
