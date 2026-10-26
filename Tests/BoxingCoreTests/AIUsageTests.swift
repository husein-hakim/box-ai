import Foundation
import Testing
@testable import BoxingCore

final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_800_000_000) }

struct AIUsageTests {
    func make() -> (AIUsage, Clock) {
        let clock = Clock()
        return (AIUsage(defaults: UserDefaults(suiteName: "box.usage.\(UUID().uuidString)")!, now: { clock.t }), clock)
    }

    @Test func burstIsLimitedThenRecovers() throws {
        let (usage, clock) = make()
        try usage.begin(.clipReview)
        #expect(throws: AIUsage.Limit.tooSoon(seconds: 5)) { try usage.begin(.clipReview) }   // double tap
        clock.t += 6
        try usage.begin(.clipReview)
        clock.t += 6
        #expect(throws: AIUsage.Limit.tooSoon(seconds: 48)) { try usage.begin(.clipReview) }  // 2 per minute
        clock.t += 49
        try usage.begin(.clipReview)
    }

    @Test func noDailyCapForSteadyUse() throws {
        let (usage, clock) = make()
        // A coach message every 20 seconds for three hours never trips a limit.
        for _ in 0..<540 { try usage.begin(.coach); clock.t += 20 }
    }

    @Test func overallCeilingAndBusyPause() throws {
        let (usage, clock) = make()
        let features: [AIUsage.Feature] = [.coach, .food, .workout, .debrief]
        for i in 0..<15 { try usage.begin(features[i % 4]); clock.t += 2 }
        #expect(throws: AIUsage.Limit.self) { try usage.begin(.nutrition) }
        clock.t += 60
        try usage.begin(.nutrition)
        usage.noteBusy()
        #expect(throws: AIUsage.Limit.coolingDown(seconds: 60)) { try usage.begin(.food) }
        clock.t += 61
        try usage.begin(.food)
    }
}
