import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingTrackerTests {
    private struct Fixtures: Decodable {
        struct Sequence: Decodable { let name: String; let armed: Bool; let frames: [BoxMaxxingTracker.Input]; let expected: [BoxMaxxingTracker.Output] }
        let configuration: BoxMaxxingTracker.Configuration
        let sessions: [Sequence]
    }
    @Test func normalizationTrackingAndMissingPointsAgreeWithRawInstructionReplay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let f = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: root.appendingPathComponent("research/boxmaxxing/port/tracking/fixtures.json")))
        for sequence in f.sessions {
            var tracker = BoxMaxxingTracker(configuration: f.configuration)
            for (input, expected) in zip(sequence.frames, sequence.expected) {
                let actual = try tracker.update(input, armed: sequence.armed)
                #expect(actual.confident == expected.confident && actual.lost == expected.lost, "\(sequence.name) @ \(input.tMs)")
                let a = [actual.dtS, actual.scale, actual.scaleSlow, actual.centre.x, actual.centre.y, actual.shoulderTiltDeg, actual.shoulderWidth]
                let b = [expected.dtS, expected.scale, expected.scaleSlow, expected.centre.x, expected.centre.y, expected.shoulderTiltDeg, expected.shoulderWidth]
                #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1e-10 }, "Scalars: \(sequence.name) @ \(input.tMs)")
                for (a, b) in zip(actual.points, expected.points) {
                    #expect(abs(a.x - b.x) <= 1e-10 && abs(a.y - b.y) <= 1e-10 && a.score == b.score && a.held == b.held,
                            "Points: \(sequence.name) @ \(input.tMs)")
                }
                #expect(try BoxMaxxingFeatures.frame(actual.featurePose).map(\.bitPattern) == BoxMaxxingFeatures.frame(expected.featurePose).map(\.bitPattern))
            }
        }
    }
    @Test func resetAndTorsoRatioValidationMatchOriginalBounds() {
        var tracker = BoxMaxxingTracker()
        tracker.setTorsoRatio(0.5); #expect(tracker.torsoRatio == 1.5)
        tracker.setTorsoRatio(4); #expect(tracker.torsoRatio == 1.5)
        tracker.setTorsoRatio(.nan); #expect(tracker.torsoRatio == 1.5)
        tracker.setTorsoRatio(2); #expect(tracker.torsoRatio == 2)
        tracker.reset()
        #expect(tracker.previousMs == nil && tracker.scaleHat == nil && tracker.scaleSlowHat == nil)
        #expect(tracker.torsoRatio == 2)
    }
}
