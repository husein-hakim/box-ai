import Foundation
import SwiftData
import Testing
@testable import BoxingCore

struct PadTrainingTests {
    @Test func mirroredAimMappingMatchesAspectFillCrop() {
        let image = CGSize(width: 720, height: 1280), viewport = CGSize(width: 400, height: 600)
        let centre = PadPreviewMapping.point(.init(x: 0.5, y: 0.5), image: image, viewport: viewport)
        #expect(abs(centre.x - 200) < 0.001 && abs(centre.y - 300) < 0.001)
        let left = PadPreviewMapping.point(.init(x: 0.25, y: 0.5), image: image, viewport: viewport)
        #expect(left.x > centre.x) // Front preview is mirrored exactly once.
    }
    @Test func levelsChangeTeachingAndTimingButNotRecognitionPolicy() {
        #expect(PadLevel.suggested(experience: "Beginner") == .beginner)
        #expect(PadLevel.suggested(experience: "Some experience") == .intermediate)
        #expect(PadLevel.suggested(experience: "Experienced") == .advanced)
        #expect(PadLevel.beginner.responseSeconds > PadLevel.intermediate.responseSeconds)
        #expect(PadLevel.intermediate.responseSeconds > PadLevel.advanced.responseSeconds)
        #expect(!PadConfiguration(activityID: "slip-cross-v1").isValid)
        #expect(PadConfiguration(activityID: "jab-reset-v1").hand(for: 1) == .lead)
        #expect(PadConfiguration(activityID: "cross-reset-v1").hand(for: 0) == .rear)
    }
    @Test func requiresVisibleCueAndDeduplicatesObservedResults() throws {
        var state = PadTrainingState(configuration: .init())
        state.begin(); state.tick(at: 0, trackingReady: true)
        for t in [0.25, 0.5, 0.75, 1.0] { state.tick(at: t, trackingReady: true) }
        let id = try #require(state.cueID)
        state.resolve(id: id, outcome: "hit_green", reactionMs: 200, at: 1.2)
        #expect(state.attempts.isEmpty)
        let stale = state.presented(UUID()); #expect(!stale)
        let acknowledged = state.presented(id); #expect(acknowledged)
        let duplicate = state.presented(id); #expect(!duplicate)
        state.resolve(id: id, outcome: "hit_green", reactionMs: 200, at: 1.2)
        state.resolve(id: id, outcome: "hit_green", reactionMs: 200, at: 1.3)
        #expect(state.attempts.count == 1)
        #expect(state.attempts.first?.isHit == true)
    }
    @Test func lostTrackingAndRestoreNeverCountAsMissesOrTimeAway() throws {
        var state = PadTrainingState(configuration: .init())
        state.begin(); state.tick(at: 0, trackingReady: true)
        for t in [0.25, 0.5, 0.75, 1.0] { state.tick(at: t, trackingReady: true) }
        let oldCue = try #require(state.cueID); _ = state.presented(oldCue)
        state.tick(at: 1.1, trackingReady: false)
        #expect(state.uncertainAttempts == 1 && state.attempts.isEmpty && state.cueID == nil)
        let savedTime = state.activeSeconds
        let data = try JSONEncoder().encode(state)
        var restored = try JSONDecoder().decode(PadTrainingState.self, from: data).restored()
        #expect(restored.phase == .paused && restored.isValidCheckpoint)
        restored.resume(); restored.tick(at: 5000, trackingReady: true)
        restored.resolve(id: oldCue, outcome: "hit_green", reactionMs: 10, at: 5000)
        #expect(restored.attempts.isEmpty && restored.activeSeconds == savedTime)
        restored.tick(at: 5010, trackingReady: true)
        #expect(restored.phase == .calibrating && restored.activeSeconds == savedTime)
    }
    @Test func liveRoundsUseOnlyActiveTimeAndEndAfterConfiguredRest() {
        var state = PadTrainingState(configuration: .init(mode: .rounds, rounds: 2, workSeconds: 30, restSeconds: 15))
        state.begin()
        for i in 0...120 { state.tick(at: Double(i) / 4, trackingReady: true) }
        #expect(state.phase == .rest && state.completedRounds == 1)
        state.pause(); let before = state.activeSeconds
        state.resume(); state.tick(at: 1000, trackingReady: true)
        #expect(state.activeSeconds == before)
        for i in 1...60 { state.tick(at: 1000 + Double(i) / 4, trackingReady: true) }
        #expect(state.round == 2 && state.phase == .calibrating)
        for i in 0...120 { state.tick(at: 1015 + Double(i) / 4, trackingReady: true) }
        #expect(state.phase == .recap && state.completedRounds == 2)
        #expect(state.attempts.isEmpty) // No observed events, no invented punches.
    }
    @MainActor @Test func checkpointAndResultsPersistWithoutDuplicates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try AppStore(container: LocalDatabase.open(url: url))
        store.startPad(.init(activityID: "jab-reset-v1"))
        let launch = try #require(store.activeSession)
        var state = try #require(launch.pad); state.begin(); state.tick(at: 0, trackingReady: true)
        for t in [0.25, 0.5, 0.75, 1.0] { state.tick(at: t, trackingReady: true) }
        let cue = try #require(state.cueID); _ = state.presented(cue)
        state.resolve(id: cue, outcome: "hit_green", reactionMs: 220, at: 1.25)
        store.savePad(launch: launch, state: state)
        let reopened = try AppStore(container: LocalDatabase.open(url: url))
        #expect(reopened.pendingSession?.pad?.phase == .paused)
        #expect(reopened.pendingSession?.pad?.attempts.count == 1)
        state.stop()
        let record = SessionRecord(id: launch.id, date: .now, focus: .jab, activeSeconds: state.activeSeconds,
            workSeconds: state.workSeconds, completedRounds: 0, skippedBlocks: 0, issuedCues: 1, finished: false, pad: state)
        #expect(reopened.record(record)); #expect(reopened.record(record))
        #expect(reopened.history.count == 1 && reopened.pendingSession == nil)
        #expect(try AppStore(container: LocalDatabase.open(url: url)).history.first?.pad?.attempts.first?.reactionMs == 220)
    }
}
