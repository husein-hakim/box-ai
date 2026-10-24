import Foundation

enum BlockKind: String, Codable, Sendable {
    case prepare, work, rest, reset
}

struct RoundBlock: Identifiable, Equatable, Sendable, Codable {
    let id: Int
    let kind: BlockKind
    let seconds: Double
    let round: Int
}

struct RoundConfiguration: Equatable, Codable, Sendable {
    var rounds = 3
    var workSeconds = 60
    var restSeconds = 30
    var cueInterval = 8

    var blocks: [RoundBlock] {
        var result = [RoundBlock(id: 0, kind: .prepare, seconds: 60, round: 0)]
        for round in 1...max(1, rounds) {
            result.append(RoundBlock(id: result.count, kind: .work, seconds: Double(workSeconds), round: round))
            if round < rounds {
                result.append(RoundBlock(id: result.count, kind: .rest, seconds: Double(restSeconds), round: round))
            }
        }
        result.append(RoundBlock(id: result.count, kind: .reset, seconds: 60, round: rounds))
        return result
    }

    var totalSeconds: Int { Int(blocks.reduce(0) { $0 + $1.seconds }) }
}

/// A monotonic clock supplied by the caller keeps pauses and interruptions out of training credit.
struct RoundTimeline: Sendable, Codable {
    enum Status: String, Sendable, Codable { case ready, running, paused, finished, stopped }

    let blocks: [RoundBlock]
    private(set) var status: Status = .ready
    private(set) var index = 0
    private(set) var blockElapsed = 0.0
    private(set) var activeSeconds = 0.0
    private(set) var workSeconds = 0.0
    private(set) var completedRounds = 0
    private(set) var skippedBlocks = 0
    private var lastTick: Double?

    private enum CodingKeys: String, CodingKey {
        case blocks, status, index, blockElapsed, activeSeconds, workSeconds, completedRounds, skippedBlocks
    }
    func restored() -> RoundTimeline {
        var copy = self
        copy.lastTick = nil
        if copy.status == .running { copy.status = .paused }
        return copy
    }
    func isValidCheckpoint(configuration: RoundConfiguration) -> Bool {
        guard (1...20).contains(configuration.rounds), (1...3600).contains(configuration.workSeconds),
              (0...3600).contains(configuration.restSeconds), (1...60).contains(configuration.cueInterval) else { return false }
        return blocks.count <= 128 && blocks == configuration.blocks && index >= 0 && index <= blocks.count &&
        [blockElapsed, activeSeconds, workSeconds].allSatisfy { $0.isFinite && $0 >= 0 } &&
        activeSeconds <= Double(configuration.totalSeconds) + 0.000001 && workSeconds <= activeSeconds + 0.000001 &&
        blockElapsed <= (current?.seconds ?? 0) + 0.000001 && completedRounds >= 0 && completedRounds <= configuration.rounds &&
        skippedBlocks >= 0 && skippedBlocks <= blocks.count && (index < blocks.count || isTerminal)
    }

    init(configuration: RoundConfiguration) { blocks = configuration.blocks }
    init(blocks: [RoundBlock]) { self.blocks = blocks }

    var current: RoundBlock? { blocks.indices.contains(index) ? blocks[index] : nil }
    var remaining: Double { max(0, (current?.seconds ?? 0) - blockElapsed) }
    var isTerminal: Bool { status == .finished || status == .stopped }

    mutating func start(at now: Double) {
        guard status == .ready, !blocks.isEmpty else { return }
        status = .running
        lastTick = now
    }

    mutating func advance(to now: Double) {
        guard status == .running, let previous = lastTick, now >= previous else { return }
        lastTick = now
        var delta = now - previous
        while delta > 0, let block = current {
            let used = min(delta, remaining)
            blockElapsed += used
            activeSeconds += used
            if block.kind == .work { workSeconds += used }
            delta -= used
            if blockElapsed >= block.seconds {
                if block.kind == .work { completedRounds += 1 }
                moveToNextBlock()
            }
        }
    }

    mutating func pause(at now: Double) {
        guard status == .running else { return }
        advance(to: now)
        guard !isTerminal else { return }
        status = .paused
        lastTick = nil
    }

    mutating func resume(at now: Double) {
        guard status == .paused else { return }
        status = .running
        lastTick = now
    }

    mutating func skip(at now: Double) {
        guard status == .running || status == .paused else { return }
        if status == .running { advance(to: now) }
        guard !isTerminal else { return }
        skippedBlocks += 1
        moveToNextBlock()
    }

    mutating func stop(at now: Double) {
        if status == .running { advance(to: now) }
        guard !isTerminal else { return }
        status = .stopped
        lastTick = nil
    }

    private mutating func moveToNextBlock() {
        index += 1
        blockElapsed = 0
        if index >= blocks.count {
            status = .finished
            lastTick = nil
        }
    }
}
