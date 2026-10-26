import AVFoundation
import Foundation
import Observation

enum BoxingCue: String, CaseIterable {
    case jab, cross, oneTwo, reset
    var title: LocalizedStringResource {
        switch self {
        case .jab: "Jab"
        case .cross: "Cross"
        case .oneTwo: "Jab. Cross."
        case .reset: "Reset"
        }
    }
    var detail: LocalizedStringResource {
        switch self {
        case .jab: "Lead hand. Return to guard."
        case .cross: "Rear hand. Return to guard."
        case .oneTwo: "Lead straight. Rear straight. Reset."
        case .reset: "Hands home. Find your balance."
        }
    }
}

@MainActor @Observable
final class SessionController {
    let launch: SessionLaunch
    private(set) var timeline: RoundTimeline
    private(set) var execution: GuidedExecution?
    private var standalonePad: PadTrainingState?
    var pad: PadTrainingState? {
        get { execution?.camera ?? standalonePad }
        set {
            if execution != nil { execution?.camera = newValue }
            else { standalonePad = newValue }
        }
    }
    private(set) var cue: BoxingCue = .reset
    private(set) var issuedCues = 0
    private(set) var pauseReason: LocalizedStringResource?
    private(set) var audioNotice: LocalizedStringResource?
    var voiceEnabled: Bool
    var isSpeaking: Bool { voiceEnabled && speech.isSpeaking }

    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var lastBlockID: Int?
    @ObservationIgnored private var lastCueKey: Int?
    @ObservationIgnored private var cueIndex = 0

    init(launch: SessionLaunch, voiceEnabled: Bool) {
        self.launch = launch
        standalonePad = launch.pad?.restored()
        execution = launch.execution?.restored()
        timeline = launch.checkpoint?.timeline.restored() ?? RoundTimeline(configuration: launch.configuration)
        if let checkpoint = launch.checkpoint {
            issuedCues = checkpoint.issuedCues; cueIndex = checkpoint.cueIndex
            cue = BoxingCue(rawValue: checkpoint.cueRaw) ?? .reset
            pauseReason = "Restored from your saved practice. Time away has not been counted."
        }
        self.voiceEnabled = voiceEnabled
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }
    var remainingText: String {
        Duration.seconds(Int(ceil(timeline.remaining))).formatted(.time(pattern: .minuteSecond))
    }
    var phaseTitle: LocalizedStringResource {
        switch timeline.current?.kind {
        case .prepare: "Get ready"
        case .work: "Your round"
        case .rest: "Breathe & reset"
        case .reset: "Finish easy"
        case nil: "Round complete"
        }
    }
    var phaseDetail: LocalizedStringResource {
        switch timeline.current?.kind {
        case .prepare: "Clear your space. Settle into your stance. Move at your own pace."
        case .work: cue.detail
        case .rest: "Relax your shoulders. Let your breathing settle."
        case .reset: "Ease out of the round and take a moment to reflect."
        case nil: "Your timer activity is ready to save."
        }
    }

    var status: RoundTimeline.Status {
        if let pad {
            if execution != nil, pad.phase == .briefing || pad.phase == .recap { return .running }
            return pad.status
        }
        guard let execution else { return timeline.status }
        if execution.phase == .briefing { return .ready }
        if execution.phase == .recap { return execution.endedEarly ? .stopped : .finished }
        return execution.paused ? .paused : .running
    }
    var isTerminal: Bool { status == .finished || status == .stopped }
    var activeSeconds: Double { execution?.totalActiveSeconds ?? pad?.activeSeconds ?? timeline.activeSeconds }
    func startActivity(stance: BoxMaxxingJudge.Stance = .orthodox, level: PadLevel = .beginner) {
        activateAudio()
        if let execution, execution.currentMode == .camera,
           let configuration = execution.current?.cameraConfiguration(stance: stance, suggestedLevel: level) {
            self.execution?.startCamera(configuration)
        } else { execution?.startSet(at: now); announceActivity() }
    }
    func chooseMode(_ mode: TrainingMode) { execution?.chooseMode(mode) }
    func finishCameraSet() { execution?.finishCameraSet(at: now); silence(); announceActivity() }
    func continueGuided() {
        execution?.continueGuided(at: now)
        pauseReason = "Continuing with guided shadowboxing. Timed work is kept; remaining work needs your own check-in."
        silence()
    }
    func finishActivitySet() { execution?.finishSet(at: now); silence() }
    func confirmActivity(reps: Int?) { execution?.confirm(reps: reps, at: now); announceActivity() }
    private func activateAudio() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]); try AVAudioSession.sharedInstance().setActive(true) }
        catch { audioNotice = "Audio is unavailable. Follow the on-screen instructions." }
    }
    private func announceActivity() {
        guard let execution, let current = execution.current else { return }
        if execution.phase == .rest { speak("Rest. Breathe and reset.") }
        else if execution.phase == .instruction { speak(LocalizedStringResource(stringLiteral: ActivityCatalog.find(current.activityID)?.title ?? "Next activity")) }
        else if execution.phase == .work { speak(LocalizedStringResource(stringLiteral: ActivityCatalog.find(current.activityID)?.cues.first ?? "Begin")) }
    }
    func begin() {
        if pad != nil { pad?.begin(); activateAudio(); return }
        if execution != nil { execution?.begin(); activateAudio(); announceActivity(); return }
        guard timeline.status == .ready else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            audioNotice = "Audio could not start. Follow the on-screen cues instead."
        }
        timeline.start(at: now)
        announcePhaseIfNeeded()
    }

    func tick() {
        if pad != nil { return } // Camera training supplies tracking freshness and its own monotonic tick.
        if let before = execution {
            execution?.tick(at: now)
            if before.phase != execution?.phase { silence(); announceActivity() }
            else if let current = execution?.current, execution?.phase == .work, execution?.paused == false {
                let key = before.index * 10000 + before.set * 1000 + Int(execution?.elapsed ?? 0) / 8
                if key != lastCueKey {
                    lastCueKey = key
                    let cues = ActivityCatalog.find(current.activityID)?.cues ?? []
                    if !cues.isEmpty { speak(LocalizedStringResource(stringLiteral: cues[cueIndex % cues.count])); cueIndex += 1 }
                }
            }
            return
        }
        guard timeline.status == .running else { return }
        timeline.advance(to: now)
        if timeline.isTerminal { silence(); return }
        announcePhaseIfNeeded()
        issueCueIfNeeded()
    }

    func pause(reason: LocalizedStringResource? = nil) {
        if pad != nil { pad?.pause(); pauseReason = reason; silence(); return }
        if execution != nil { execution?.pause(at: now); pauseReason = reason; silence(); return }
        guard timeline.status == .running else { return }
        timeline.pause(at: now)
        pauseReason = reason
        silence()
    }

    func resume() {
        if pad != nil { pad?.resume(); activateAudio(); pauseReason = nil; return }
        if execution != nil { activateAudio(); execution?.resume(at: now); pauseReason = nil; announceActivity(); return }
        guard timeline.status == .paused else { return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]); try AVAudioSession.sharedInstance().setActive(true) }
        catch { audioNotice = "Audio is unavailable. Follow the on-screen cues instead." }
        pauseReason = nil
        timeline.resume(at: now)
        speak(timeline.current?.kind == .work ? cue.title : phaseTitle)
    }

    func skip() {
        if execution != nil { execution?.skip(at: now); silence(); announceActivity(); return }
        let wasRunning = timeline.status == .running
        silence()
        timeline.skip(at: now)
        if wasRunning && !timeline.isTerminal {
            announcePhaseIfNeeded()
            issueCueIfNeeded()
        }
    }

    func stop() {
        if execution != nil { execution?.end(at: now); silence(); return }
        if pad != nil { pad?.stop(); silence(); return }
        timeline.stop(at: now)
        silence()
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        if !voiceEnabled { silence() }
    }

    func cleanUp() {
        silence()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func checkpoint() -> SessionCheckpoint {
        SessionCheckpoint(timeline: timeline, issuedCues: issuedCues, cueIndex: cueIndex, cueRaw: cue.rawValue)
    }
    func record(feedback: String = "", effort: Int? = nil) -> SessionRecord {
        if let pad, execution == nil {
            return SessionRecord(id: launch.id, date: .now, focus: launch.focus, activeSeconds: pad.activeSeconds,
                workSeconds: pad.workSeconds, completedRounds: pad.completedRounds, skippedBlocks: 0,
                issuedCues: pad.attempts.count, finished: !pad.endedEarly, assignmentID: launch.assignmentID, pad: pad)
        }
        if let execution {
            return SessionRecord(id: launch.id, date: .now, focus: launch.focus, activeSeconds: execution.activeSeconds,
                                 workSeconds: execution.results.reduce(0) { $0 + $1.timedSeconds },
                                 completedRounds: execution.results.reduce(0) { $0 + $1.confirmedSets },
                                 skippedBlocks: execution.results.filter(\.skipped).count, issuedCues: 0,
                                 finished: !execution.endedEarly && execution.results.indices.allSatisfy { execution.outcome(at: $0) == .completed },
                                 guided: GuidedSummary(execution: execution, feedback: String(feedback.prefix(1000)), effort: effort), assignmentID: execution.assignmentID)
        }
        return SessionRecord(id: launch.id, date: .now, focus: launch.focus,
                      activeSeconds: timeline.activeSeconds, workSeconds: timeline.workSeconds,
                      completedRounds: timeline.completedRounds, skippedBlocks: timeline.skippedBlocks,
                      issuedCues: issuedCues, finished: timeline.status == .finished, assignmentID: launch.assignmentID)
    }

    private func announcePhaseIfNeeded() {
        guard let block = timeline.current, lastBlockID != block.id else { return }
        lastBlockID = block.id
        if block.kind != .work { speak(phaseTitle) }
    }

    private func issueCueIfNeeded() {
        guard let block = timeline.current, block.kind == .work else { return }
        let key = block.id * 10_000 + Int(timeline.blockElapsed) / launch.configuration.cueInterval
        guard key != lastCueKey else { return }
        lastCueKey = key
        let pool: [BoxingCue]
        switch launch.focus {
        case .mixed: pool = [.jab, .cross, .oneTwo, .reset]
        case .jab: pool = [.jab, .reset]
        case .straightCombination: pool = [.oneTwo, .reset]
        }
        cue = pool[cueIndex % pool.count]
        cueIndex += 1
        issuedCues += 1
        speak(cue.title)
    }

    func speak(_ text: LocalizedStringResource) {
        guard voiceEnabled else { return }
        silence()
        let utterance = AVSpeechUtterance(string: String(localized: text))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        speech.speak(utterance)
    }

    private func silence() { speech.stopSpeaking(at: .immediate) }
}
