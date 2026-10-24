import Testing
@testable import BoxingCore

@Test func defaultBudgetIncludesOnlyBetweenRoundRests() {
    let configuration = RoundConfiguration()
    #expect(configuration.totalSeconds == 360)
    #expect(configuration.blocks.filter { $0.kind == .rest }.count == 2)
}

@Test func pausedAndBackgroundTimeReceiveNoCredit() {
    var clock = RoundTimeline(configuration: .init())
    clock.start(at: 10)
    clock.pause(at: 80)
    #expect(clock.workSeconds == 10)
    let remaining = clock.remaining
    clock.advance(to: 200)
    #expect(clock.remaining == remaining)
    clock.resume(at: 200)
    clock.advance(to: 205)
    #expect(clock.activeSeconds == 75)
    #expect(clock.workSeconds == 15)
}

@Test func skippedWorkIsNotCompletedWork() {
    var clock = RoundTimeline(configuration: .init())
    clock.start(at: 0)
    clock.advance(to: 70)
    clock.skip(at: 70)
    #expect(clock.current?.kind == .rest)
    #expect(clock.completedRounds == 0)
    #expect(clock.workSeconds == 10)
    #expect(clock.skippedBlocks == 1)
}

@Test func fullSessionCapsTimeAndCountsWorkSeparately() {
    var clock = RoundTimeline(configuration: .init())
    clock.start(at: 0)
    clock.advance(to: 500)
    #expect(clock.status == .finished)
    #expect(clock.activeSeconds == 360)
    #expect(clock.workSeconds == 180)
    #expect(clock.completedRounds == 3)
    clock.advance(to: 900)
    #expect(clock.activeSeconds == 360)
}

@Test func stopAndReversedClockCannotAddTime() {
    var clock = RoundTimeline(configuration: .init())
    clock.start(at: 10)
    clock.advance(to: 5)
    #expect(clock.activeSeconds == 0)
    clock.stop(at: 20)
    clock.resume(at: 40)
    clock.advance(to: 100)
    #expect(clock.activeSeconds == 10)
    #expect(clock.status == .stopped)
}
