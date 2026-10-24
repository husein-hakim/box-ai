import Foundation
import Testing
@testable import BoxingCore

struct BoxMaxxingFeatureTests {
    private struct Fixture: Decodable {
        struct FrameCase: Decodable {
            var name: String
            var current: BoxMaxxingFeaturePose
            var previous: BoxMaxxingFeaturePose?
            var expected: [Float]
        }
        struct WindowCase: Decodable {
            var name: String
            var frames: [BoxMaxxingFeatureFrame]
            var endMs: Double
            var samples: Int
            var stepMs: Double
            var expected: [Float]
        }
        var frameCases: [FrameCase]
        var windowCases: [WindowCase]
    }

    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Tests/Fixtures/Recognition/features/fixtures.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func frameFeaturesAgreeWithInstructionReplay() throws {
        for vector in try fixture().frameCases {
            let actual = try BoxMaxxingFeatures.frame(vector.current, previous: vector.previous)
            #expect(actual.count == 85)
            #expect(actual == vector.expected, "Frame vector: \(vector.name)")
        }
    }

    @Test func samplingAgreesWithInstructionReplay() throws {
        for vector in try fixture().windowCases {
            let actual = try BoxMaxxingFeatures.sampleWindow(vector.frames, endingAt: vector.endMs,
                                                           samples: vector.samples, stepMs: vector.stepMs)
            #expect(actual == vector.expected, "Window vector: \(vector.name)")
        }
    }

    @Test func heldPositionsAreRetainedButHeldVelocitiesAreZero() throws {
        var previous = BoxMaxxingFeaturePose(tMs: 1_000, points: Array(repeating: .init(x: 0, y: 0, score: 1), count: 17))
        var current = previous
        current.tMs = 1_040
        current.points[9] = .init(x: 1, y: 1, score: 1, held: true)
        let held = try BoxMaxxingFeatures.frame(current, previous: previous)
        #expect(held[18] == 1 && held[19] == 1)
        #expect(held[52] == 0 && held[53] == 0 && held[77] == 0)
        previous.lost = true
        current.points[9].held = false
        let afterLost = try BoxMaxxingFeatures.frame(current, previous: previous)
        #expect(afterLost[52] == 0 && afterLost[77] == 1)
        current.lost = true
        #expect(try BoxMaxxingFeatures.frame(current, previous: previous) == Array(repeating: Float(0), count: 85))
    }

    @Test func ringRetentionAndResetDoNotReusePreResetVelocity() throws {
        var ring = BoxMaxxingFeatureRing()
        var pose = BoxMaxxingFeaturePose(tMs: 0, points: Array(repeating: .init(x: 0, y: 0, score: 1), count: 17))
        try ring.push(pose)
        pose.tMs = 2_500; try ring.push(pose)
        #expect(ring.size == 2) // Exactly the cutoff remains in the original.
        pose.tMs = 2_501; try ring.push(pose)
        #expect(ring.size == 2 && ring.frames.first?.tMs == 2_500)
        ring.reset()
        #expect(ring.size == 0 && ring.previous == nil)
        pose.tMs = 2_600; pose.points[0].x = 1
        try ring.push(pose)
        #expect(ring.frames[0].f[34] == 0)
    }

    @Test func mirrorSwapsAnatomicalSidesAndNegatesOnlyHorizontalFeatures() throws {
        let input = (0..<85).map(Float.init)
        let mirrored = try BoxMaxxingFeatures.mirrorWindow(input, samples: 1)
        #expect(mirrored[18] == -input[20] && mirrored[19] == input[21])
        #expect(mirrored[52] == -input[54] && mirrored[53] == input[55])
        #expect(mirrored[77] == input[78])
        #expect(try BoxMaxxingFeatures.mirrorWindow(mirrored, samples: 1) == input)
        #expect(BoxMaxxingFeatures.mirrorClass("straight_left") == "straight_right")
        #expect(BoxMaxxingFeatures.mirrorClass("slip") == "slip")
    }
}
