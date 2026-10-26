import SwiftUI
import AVFoundation

struct PadTrainingSetupView: View {
    let store: AppStore
    let activityID: String?
    @State private var configuration = PadConfiguration()
    @State private var instructionsRead = false
    @State private var showingMore = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Label("Camera · Live pads", systemImage: "camera.viewfinder").boxEyebrow(.white.opacity(0.85))
                        Spacer()
                        BoxChip(text: "Beta", onHero: true)
                    }
                    Text(activityID == nil ? "Hit the\npads." : "Camera\npractice.").boxDisplay(44, relativeTo: .title).padding(.top, 10)
                    Text("Targets appear around you. Punch into the ring.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                    HStack(spacing: 6) {
                        BoxValueChip(text: configuration.mode == .learn ? String(localized: "\(configuration.attempts) punches") : String(localized: "\(configuration.rounds) × \(configuration.workSeconds)s"), onHero: true)
                        BoxChip(text: LocalizedStringResource(stringLiteral: configuration.level.title), onHero: true)
                        BoxChip(text: configuration.stance == .orthodox ? "Orthodox" : "Southpaw", onHero: true)
                    }.padding(.top, 14)
                }.boxHero().boxEntrance()
                VStack(alignment: .leading, spacing: 14) {
                    if activityID == nil {
                        BoxSegmented(options: [PadConfiguration.Mode.learn, .rounds],
                                     selection: Binding(get: { configuration.mode }, set: { configuration.mode = $0 }),
                                     title: { $0 == .learn ? "Learn" : "Live rounds" },
                                     symbol: { $0 == .learn ? "graduationcap.fill" : "timer" })
                    }
                    if configuration.mode == .learn {
                        PadCountStepper(label: "Punches", value: $configuration.attempts, range: 4...24, step: 2)
                    } else {
                        PadCountStepper(label: "Rounds", value: $configuration.rounds, range: 1...6, step: 1)
                    }
                    BoxSegmented(options: PadLevel.allCases, selection: Binding(get: { configuration.level }, set: { configuration.level = $0 }),
                                 title: { LocalizedStringResource(stringLiteral: $0.title) })
                    Text(configuration.level.explanation).font(.footnote).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 18).boxEntrance(1)
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showingMore.toggle() } } label: {
                    HStack {
                        Label("More options", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).rotationEffect(.degrees(showingMore ? 180 : 0))
                    }
                    .foregroundStyle(BoxStyle.ink).padding(.horizontal, 16).frame(minHeight: 48)
                    .background(BoxStyle.surface, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BoxStyle.border) }
                }.buttonStyle(BoxPressStyle()).boxEntrance(2)
                if showingMore {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Stance", selection: $configuration.stance) {
                            Text("Orthodox · left lead").tag(BoxMaxxingJudge.Stance.orthodox)
                            Text("Southpaw · right lead").tag(BoxMaxxingJudge.Stance.southpaw)
                        }.tint(BoxStyle.ink)
                        if configuration.mode == .rounds {
                            Picker("Work", selection: $configuration.workSeconds) { Text("30 sec").tag(30); Text("60 sec").tag(60); Text("2 min").tag(120) }.tint(BoxStyle.ink)
                            Picker("Rest", selection: $configuration.restSeconds) { Text("15 sec").tag(15); Text("30 sec").tag(30); Text("60 sec").tag(60) }.tint(BoxStyle.ink)
                        }
                        BoxSegmented(options: PadTargetMode.allCases, selection: Binding(get: { configuration.effectiveTargetMode }, set: { configuration.targetMode = $0 }),
                                     title: { LocalizedStringResource(stringLiteral: $0.title) })
                        Text(configuration.effectiveTargetMode == .accuracy ? "Punch into rings set to your reach. A quick hands-free reach check runs after the countdown." : "React to each callout. No target rings or accuracy.")
                            .font(.footnote).foregroundStyle(BoxStyle.muted)
                        if let activity = ActivityCatalog.find(activityID ?? "jab-reset-v1") {
                            DisclosureGroup("How to throw it") {
                                ActivityInstructions(activity: activity, mode: .shadowboxing).padding(.top, 8)
                            }.font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
                        }
                    }
                    .font(.subheadline).boxPanel(padding: 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Button { instructionsRead.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: instructionsRead ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(instructionsRead ? BoxStyle.conditioning : BoxStyle.dim)
                            .contentTransition(.symbolEffect(.replace))
                        Text("Noncontact only. My phone is propped out of reach and I won’t strike it.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: instructionsRead)
                .accessibilityAddTraits(instructionsRead ? .isSelected : [])
                PrimaryButton(title: "Start", symbol: "camera.fill") { store.startPad(configuration) }
                    .disabled(!instructionsRead || !configuration.isValid)
                Text("Beta · Experimental recognition and timing. No technique or power grades.").font(.caption).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }.boxScreen().foregroundStyle(BoxStyle.ink)
            .navigationTitle("Live pads").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear {
                configuration.activityID = activityID
                configuration.level = .suggested(experience: store.profile.experience)
                configuration.stance = store.stance == "Southpaw" ? .southpaw : .orthodox
            }
    }
}

private struct PadCountStepper: View {
    let label: LocalizedStringResource
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(BoxStyle.muted)
            Spacer()
            control("minus", enabled: value - step >= range.lowerBound) { value -= step }
            Text(value, format: .number).boxNumber(26).frame(minWidth: 48)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
            control("plus", enabled: value + step <= range.upperBound) { value += step }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label)).accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value + step <= range.upperBound { value += step }
            case .decrement: if value - step >= range.lowerBound { value -= step }
            @unknown default: break
            }
        }
    }
    private func control(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); BoxHaptics.selection() } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).frame(width: 38, height: 38)
                .background(BoxStyle.surfaceRaised, in: .circle).overlay { Circle().strokeBorder(BoxStyle.borderStrong) }
        }
        .buttonStyle(BoxPressStyle(scale: 0.88)).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

struct PadTrainingPlayer: View {
    let controller: SessionController
    let save: () -> Void
    let discard: () -> Void
    let checkpoint: () -> Void
    var fallback: (() -> Void)?
    var end: () -> Void = {}
    var later: (() -> Void)?
    @State private var camera: PadTrainingCamera
    @State private var director = PadArenaDirector()
    private var pad: PadTrainingState { controller.pad! }
    private var cameraNeeded: Bool { guard let pad = controller.pad else { return false }; return pad.phase != .briefing && pad.phase != .paused && pad.phase != .recap }
    init(controller: SessionController, save: @escaping () -> Void, discard: @escaping () -> Void, checkpoint: @escaping () -> Void,
         fallback: (() -> Void)? = nil, end: @escaping () -> Void = {}, later: (() -> Void)? = nil) {
        self.controller = controller; self.save = save; self.discard = discard; self.checkpoint = checkpoint
        self.fallback = fallback; self.end = end; self.later = later
        _camera = State(initialValue: PadTrainingCamera(configuration: controller.pad!.configuration, diagnostics: controller.pad!.diagnostics?.camera ?? .init()))
    }
    var body: some View {
        Group {
            if let pad = controller.pad {
                if pad.phase == .briefing {
                    PadTrainingBriefing(pad: pad, begin: { controller.begin() })
                } else if pad.phase == .recap {
                    PadTrainingRecap(pad: pad, bestCombo: director.bestCombo, save: save, discard: discard, embedded: controller.execution != nil)
                } else {
                    PadArena(controller: controller, camera: camera, director: director, pad: pad, checkpoint: checkpoint,
                             end: { camera.suspend(); end() },
                             later: later.map { action in { camera.suspend(); camera.stop(); action() } },
                             fallback: fallback.map { action in { camera.suspend(); camera.stop(); action() } },
                             skip: fallback == nil ? nil : { camera.suspend(); camera.stop(); discard() })
                }
            }
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .task(id: cameraNeeded) { if cameraNeeded { await camera.start() } else { camera.stop() } }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                step()
            }
        }
        .onChange(of: controller.pad?.cueID) { _, id in
            if id == nil && controller.pad?.cueID == nil { camera.suspend() }
            if id != nil { camera.clearCoaching() }
        }
        .onChange(of: camera.reachStage) { _, stage in
            guard director.armed, let pad = controller.pad, camera.needsReach, pad.phase != .paused,
                  pad.feedbackStage != .outcome, pad.feedbackStage != .reset else { return }
            if stage != .idle { BoxHaptics.selection() }
            if stage == .ready { BoxHaptics.success() }
            controller.speak(LocalizedStringResource(stringLiteral: camera.reachInstruction))
        }
        .onDisappear { camera.stop() }
    }
    private func step() {
        guard let current = controller.pad, current.phase != .briefing && current.phase != .recap else { return }
        let now = ProcessInfo.processInfo.systemUptime
        director.update(now: now, pad: current, camera: camera) { controller.speak($0) }
        guard current.phase != .paused else { return }
        let oldFeedback = pad.feedback
        let oldStage = pad.feedbackStage
        let oldCount = pad.attempts.count
        let oldEpisodes = pad.diagnostics?.trackingEpisodes
        let oldCameraEpisodes = pad.diagnostics?.camera.interruptionEpisodes
        camera.setReachSampling(pad.feedbackStage != .cue && pad.feedbackStage != .outcome && pad.feedbackStage != .reset && pad.phase != .rest)
        camera.refreshFreshness()
        for event in camera.drainEvents() {
            switch event {
            case .interrupted(let id, let reason):
                if id == controller.pad?.cueID {
                    if reason == "target_alignment_changed" { controller.pad?.targetSetupRequired() }
                    else { controller.pad?.trackingLost(reason: reason, at: now) }
                }
            case .response(let result):
                controller.pad?.resolve(id: result.id, outcome: result.outcome, reactionMs: result.reactionMs, at: now, targetMatch: result.targetMatch, coaching: result.coaching)
            case .unjudged(let id, let reason):
                controller.pad?.retryResponse(id: id, reason: reason, at: now)
            }
        }
        controller.pad?.diagnostics?.camera = camera.diagnosticsSnapshot()
        // The countdown arms the arena: no cue before the fighter has seen 3-2-1.
        controller.pad?.tick(at: now, trackingReady: camera.trackingReady, trackingReason: camera.trackingReason,
                             speechBusy: controller.isSpeaking, cueingReady: camera.canPresentCue && director.armed,
                             scoringReady: camera.scoringReady)
        if let id = pad.cueID, !pad.cuePresented, !camera.prepare(id: id, hand: pad.hand) { controller.pad?.targetSetupRequired() }
        camera.setReachSampling(pad.feedbackStage != .cue && pad.feedbackStage != .outcome && pad.feedbackStage != .reset && pad.phase != .rest)
        // State transitions, visible feedback and speech use the same source in
        // this actor turn. No delayed onChange can read the next cue's wording.
        if pad.feedbackStage != .cue && pad.feedbackStage != .outcome && (pad.feedback != oldFeedback || pad.feedbackStage != oldStage) {
            controller.speak(LocalizedStringResource(stringLiteral: pad.spokenFeedback))
        }
        if pad.attempts.count != oldCount {
            director.record(pad.attempts.last)
            if let last = pad.attempts.last {
                if last.isHit && last.targetMatch?.outcome != .missed { BoxHaptics.success() } else { BoxHaptics.warning() }
            }
        }
        if pad.attempts.count != oldCount || pad.diagnostics?.trackingEpisodes != oldEpisodes ||
            pad.diagnostics?.camera.interruptionEpisodes != oldCameraEpisodes ||
            (pad.feedbackStage == .outcome && oldStage != .outcome) { checkpoint() }
    }
}

// MARK: - Arena director

/// Hands-free flow: body in frame → 3-2-1 → (auto reach capture) → pads.
/// No button press is ever needed once the fighter is in stance.
@MainActor @Observable
final class PadArenaDirector {
    private(set) var armed = false
    private(set) var countdown: Int?
    private(set) var flash: LocalizedStringResource?
    private(set) var combo = 0
    private(set) var bestCombo = 0
    var reminders = false
    @ObservationIgnored private var readySince: Double?
    @ObservationIgnored private var notReadySince: Double?
    @ObservationIgnored private var countdownStart: Double?
    @ObservationIgnored private var flashUntil = 0.0
    @ObservationIgnored private var retryAt: Double?
    @ObservationIgnored private var lastPhase: PadTrainingState.Phase?

    func update(now: Double, pad: PadTrainingState, camera: PadTrainingCamera, speak: (LocalizedStringResource) -> Void) {
        if flash != nil && now >= flashUntil { flash = nil }
        defer { lastPhase = pad.phase }
        // Every pause and every rest re-arms the arena with a fresh countdown.
        if pad.phase == .paused || pad.phase == .rest {
            if armed || countdown != nil { disarm() }
            return
        }
        if armed { autoCalibrate(now: now, pad: pad, camera: camera); return }
        guard pad.phase == .calibrating, camera.trackingReady, camera.error == nil else {
            readySince = nil
            // Brief tracking flicker must not restart the count; half a second out does.
            if notReadySince == nil { notReadySince = now }
            if countdownStart != nil, now - (notReadySince ?? now) >= 0.5 { countdownStart = nil; countdown = nil }
            return
        }
        notReadySince = nil
        if readySince == nil { readySince = now }
        if countdownStart == nil, now - (readySince ?? now) >= 0.6 { countdownStart = now }
        guard let start = countdownStart else { return }
        let remaining = 3 - Int((now - start).rounded(.down))
        if remaining <= 0 {
            armed = true; countdown = nil; countdownStart = nil
            let calibrating = camera.needsReach && !camera.reachReady
            show(calibrating ? "Guard up" : "Fight", until: now + 0.9)
            BoxHaptics.heavy()
            speak(calibrating ? "Guard up" : "Fight")
            autoCalibrate(now: now, pad: pad, camera: camera)
        } else if countdown != remaining {
            countdown = remaining
            BoxHaptics.impact()
            speak(LocalizedStringResource(stringLiteral: "\(remaining)"))
        }
    }

    /// Reach capture starts and retries itself whenever the fighter is in view.
    private func autoCalibrate(now: Double, pad: PadTrainingState, camera: PadTrainingCamera) {
        guard camera.needsReach, camera.trackingReady, pad.cueID == nil else { return }
        switch camera.reachStage {
        case .idle:
            retryAt = nil; camera.startReachCalibration()
        case .failed:
            if let retryAt {
                if now >= retryAt { self.retryAt = nil; camera.startReachCalibration() }
            } else { retryAt = now + 2.2 }
        default:
            retryAt = nil
        }
    }

    func record(_ attempt: PadAttempt?) {
        guard let attempt, attempt.countsTowardDrill else { return }
        if attempt.isHit && attempt.targetMatch?.outcome != .missed {
            combo += 1; bestCombo = max(bestCombo, combo)
        } else { combo = 0 }
    }

    func disarm() { armed = false; countdown = nil; countdownStart = nil; readySince = nil; notReadySince = nil; retryAt = nil }

    #if DEBUG
    /// Design QA only: pose the director without a live camera.
    func debugPose(armed: Bool, countdown: Int? = nil, combo: Int = 0) {
        self.armed = armed; self.countdown = countdown; self.combo = combo; bestCombo = max(bestCombo, combo)
    }
    #endif

    private func show(_ text: LocalizedStringResource, until: Double) { flash = text; flashUntil = until }
}

// MARK: - Arena (full-screen camera + HUD)

private struct PadArena: View {
    let controller: SessionController
    let camera: PadTrainingCamera
    let director: PadArenaDirector
    let pad: PadTrainingState
    let checkpoint: () -> Void
    let end: () -> Void
    let later: (() -> Void)?
    let fallback: (() -> Void)?
    let skip: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PadCameraStage(controller: controller, camera: camera, pad: pad)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { camera.setViewport($0) }
                .ignoresSafeArea()
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 230)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 320)
            }
            .ignoresSafeArea().allowsHitTesting(false)
            if pad.feedbackStage == .cue && pad.cuePresented {
                PadEdgeGlow(color: BoxStyle.accent).ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 10) {
                PadTopHUD(controller: controller, camera: camera, pad: pad, end: end, pause: pause)
                PadCallout(camera: camera, director: director, pad: pad)
                Spacer(minLength: 0)
                PadCentreHUD(camera: camera, director: director, pad: pad)
                Spacer(minLength: 0)
                PadCoachingToast(camera: camera, pad: pad)
                PadOutcomeBanner(controller: controller, pad: pad, combo: director.combo)
                PadBottomHUD(camera: camera, director: director, pad: pad)
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
            if pad.phase == .paused {
                PadPauseMenu(camera: camera, director: director, pad: pad,
                             resume: resume, end: end, later: later, fallback: fallback, skip: skip)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: pad.phase)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: pad.feedbackStage == .outcome)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
    private func pause() { camera.suspend(); controller.pause(); checkpoint(); BoxHaptics.impact() }
    private func resume() { camera.suspend(); controller.resume(); checkpoint(); BoxHaptics.impact() }
}

private struct PadTopHUD: View {
    let controller: SessionController
    let camera: PadTrainingCamera
    let pad: PadTrainingState
    let end: () -> Void
    let pause: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PadHUDButton(symbol: "xmark", label: "End session", action: end)
                Spacer(minLength: 4)
                PadProgressHUD(pad: pad)
                Spacer(minLength: 4)
                PadHUDButton(symbol: controller.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             label: controller.voiceEnabled ? "Mute spoken cues" : "Enable spoken cues") { controller.toggleVoice() }
                PadHUDButton(symbol: "pause.fill", label: "Pause", action: pause)
                    .disabled(pad.phase == .paused)
            }
            HStack {
                PadReadinessIndicator(readiness: pad.phase == .paused ? .paused : camera.readiness)
                Spacer()
                Text("\(pad.configuration.level.title) · \(pad.configuration.effectiveTargetMode.title)")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.top, 4)
    }
}

private struct PadProgressHUD: View {
    let pad: PadTrainingState
    var body: some View {
        if pad.configuration.mode == .learn {
            let total = pad.configuration.attempts
            VStack(spacing: 5) {
                Text("\(pad.completedAttempts) / \(total)").boxNumber(22).foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(pad.completedAttempts)))
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { index in
                        Capsule().fill(index < pad.completedAttempts ? BoxStyle.accent : .white.opacity(0.22))
                            .frame(width: max(4, min(14, 150 / CGFloat(total))), height: 4)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(pad.completedAttempts) of \(total) attempts"))
        } else {
            let limit = pad.phase == .rest ? pad.configuration.restSeconds : pad.configuration.workSeconds
            let remaining = max(0, limit - Int(pad.roundSeconds))
            VStack(spacing: 2) {
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond))).boxNumber(26, italic: true).foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                Text(pad.phase == .rest ? "Rest" : "Round \(pad.round) of \(pad.configuration.rounds)").boxEyebrow(.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Upper-third callout: the punch to throw, kept clear of the target area.
private struct PadCallout: View {
    let camera: PadTrainingCamera
    let director: PadArenaDirector
    let pad: PadTrainingState
    var body: some View {
        ZStack {
            if pad.phase == .work && pad.feedbackStage == .cue && pad.cuePresented {
                VStack(spacing: 2) {
                    Text(pad.hand == .lead ? "Jab" : "Cross").boxDisplay(64)
                        .foregroundStyle(.white)
                        .shadow(color: BoxStyle.accent.opacity(0.9), radius: 18)
                    Text(pad.hand == .lead ? "Lead hand" : "Rear hand").boxEyebrow(BoxStyle.accent)
                }
                .transition(.scale(scale: 1.25).combined(with: .opacity))
                .id(pad.cueID)
            } else if let flash = director.flash {
                Text(flash).boxDisplay(64).foregroundStyle(.white)
                    .shadow(color: BoxStyle.accent.opacity(0.9), radius: 20)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            }
        }
        .frame(height: 96)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: pad.cueID)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: director.flash != nil)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Centre of the arena: framing guide, countdown, reach capture or rest.
private struct PadCentreHUD: View {
    let camera: PadTrainingCamera
    let director: PadArenaDirector
    let pad: PadTrainingState
    var body: some View {
        Group {
            if let error = camera.error {
                PadHUDCard(symbol: "exclamationmark.triangle.fill", color: BoxStyle.accent, title: "Camera stopped", detail: error)
            } else if pad.phase == .paused {
                EmptyView()
            } else if pad.phase == .rest {
                VStack(spacing: 6) {
                    Text("Rest").boxEyebrow(BoxStyle.timer)
                    Text("\(max(0, pad.configuration.restSeconds - Int(pad.roundSeconds)))").boxNumber(110, italic: true).foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                    Text("Breathe. Shake out your arms.").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
            } else if let count = director.countdown {
                PadCountdown(number: count)
            } else if !director.armed {
                PadFramingGuide(camera: camera)
            } else if camera.needsReach && !camera.reachReady && pad.phase == .calibrating {
                PadReachHUD(camera: camera)
            } else if pad.phase == .calibrating && pad.feedbackStage != .outcome && pad.feedbackStage != .retry {
                PadHUDCard(symbol: "figure.boxing", color: BoxStyle.strength, title: "Back to your guard",
                           detail: camera.targetNotice ?? pad.feedback)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PadFramingGuide: View {
    let camera: PadTrainingCamera
    var body: some View {
        let adjusting = camera.readiness == .adjust
        VStack(spacing: 14) {
            ZStack {
                ViewfinderCorners().frame(width: 230, height: 270)
                Image(systemName: "figure.boxing").font(.system(size: 96, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Text(adjusting ? "Adjust your distance" : camera.readiness == .inView ? "Hold your guard" : "Step into frame")
                .boxDisplay(40).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(adjusting ? camera.tracking : "Head, shoulders and both arms in view. We start automatically.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PadCountdown: View {
    let number: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 8).frame(width: 210, height: 210)
            Circle().stroke(BoxStyle.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 210, height: 210).shadow(color: BoxStyle.accent, radius: 16)
            Text("\(number)").boxNumber(150, relativeTo: .largeTitle, italic: true).foregroundStyle(.white)
                .shadow(color: BoxStyle.accent.opacity(0.8), radius: 24)
        }
        .id(number)
        .transition(reduceMotion ? .opacity : .scale(scale: 1.6).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: number)
        .accessibilityLabel(Text("Starting in \(number)"))
    }
}

private struct PadReachHUD: View {
    let camera: PadTrainingCamera
    var body: some View {
        let step = camera.reachStep
        let failed = camera.reachStage == .failed
        let reaching = camera.reachStage == .leadReach || camera.reachStage == .rearReach
        VStack(spacing: 14) {
            Text(failed ? "Again" : "Lock in your reach · \(max(1, step.current)) of \(step.total)")
                .boxEyebrow(failed ? BoxStyle.strength : BoxStyle.accent)
            ZStack {
                BoxRing(progress: failed ? 0 : camera.reachProgress, lineWidth: 8, color: reaching ? BoxStyle.accent : BoxStyle.conditioning,
                        track: .white.opacity(0.18), glow: true)
                    .animation(.linear(duration: 0.12), value: camera.reachProgress)
                Image(systemName: reaching ? "hand.point.up.left.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 112, height: 112)
            Text(camera.reachInstruction).boxDisplay(38).foregroundStyle(.white).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            if let notice = camera.targetNotice {
                Text(notice).font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.strength).multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Result of the last punch: big verdict, reaction time and combo.
private struct PadOutcomeBanner: View {
    let controller: SessionController
    let pad: PadTrainingState
    let combo: Int
    var body: some View {
        ZStack {
            if (pad.feedbackStage == .outcome || pad.feedbackStage == .retry) && pad.phase != .paused {
                let verdict = verdict
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verdict.title).boxDisplay(46).foregroundStyle(verdict.color)
                        if let reaction = verdict.reaction {
                            Text("\(Int(reaction)) ms").boxNumber(26).foregroundStyle(.white)
                        }
                    }
                    Text(pad.feedbackDetail ?? pad.feedback).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center).lineLimit(2)
                    if verdict.success && combo >= 2 {
                        Text("Combo ×\(combo)").boxSection(20).foregroundStyle(BoxStyle.strength)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.55), in: .rect(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(verdict.color.opacity(0.6), lineWidth: 1.5) }
                .shadow(color: verdict.color.opacity(0.35), radius: 20)
                .background {
                    if pad.feedbackStage == .outcome, let feedbackID = pad.feedbackID {
                        let message = pad.spokenFeedback
                        PadOutcomeAcknowledgement(id: feedbackID) { id, submittedAt in
                            guard controller.pad?.feedbackPresented(id: id, at: submittedAt) == true else { return }
                            controller.speak(LocalizedStringResource(stringLiteral: message))
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
    }
    private var verdict: (title: LocalizedStringResource, color: Color, reaction: Double?, success: Bool) {
        guard pad.feedbackStage == .outcome else { return ("Tracking lost", BoxStyle.strength, nil, false) }
        guard pad.feedbackIsRecognised || pad.feedbackID == pad.attempts.last?.id, let last = pad.attempts.last, last.id == pad.feedbackID else {
            return ("Retry", BoxStyle.strength, nil, false)
        }
        if last.isHit {
            switch last.targetMatch?.outcome {
            case .missed: return ("Off target", BoxStyle.strength, last.reactionMs, false)
            case .uncertain: return ("Retry", BoxStyle.strength, nil, false)
            default: return ("Hit", BoxStyle.conditioning, last.reactionMs, true)
            }
        }
        return switch last.outcome {
        case "wrong_hand": ("Wrong hand", BoxStyle.accent, nil, false)
        case "wrong_kind": ("Straight punch", BoxStyle.accent, nil, false)
        case "early": ("Too early", BoxStyle.strength, nil, false)
        default: ("Too slow", BoxStyle.accent, nil, false)
        }
    }
}

/// Instant feedback when a punch is seen but not accepted: why, and what to change.
private struct PadCoachingToast: View {
    let camera: PadTrainingCamera
    let pad: PadTrainingState
    @State private var visible = false
    var body: some View {
        ZStack {
            if visible, let advice = camera.coaching, pad.feedbackStage == .cue {
                Label { Text(advice) } icon: { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right") }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(BoxStyle.strength, in: .capsule)
                    .shadow(color: BoxStyle.strength.opacity(0.5), radius: 12)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: visible)
        .task(id: camera.coachingID) {
            guard camera.coaching != nil else { return }
            visible = true; BoxHaptics.warning()
            try? await Task.sleep(for: .seconds(1.8))
            visible = false
        }
    }
}

/// Where the punch landed: a burst on a clean hit, a marker and guide line on a miss.
private struct PadImpactOverlay: View {
    let match: PadTargetMatch
    let imageSize: CGSize
    @State private var burst = false
    var body: some View {
        GeometryReader { geometry in
            let mapping = PadCameraTransform(image: imageSize, viewport: geometry.size)
            let region = mapping.region(match.target)
            ZStack {
                switch match.outcome {
                case .reached:
                    Circle().fill(BoxStyle.conditioning.opacity(burst ? 0 : 0.45))
                        .frame(width: region.width, height: region.height)
                        .position(x: region.midX, y: region.midY)
                    Circle().stroke(BoxStyle.conditioning, lineWidth: 6)
                        .frame(width: region.width, height: region.height)
                        .scaleEffect(burst ? 1.7 : 1).opacity(burst ? 0 : 1)
                        .position(x: region.midX, y: region.midY)
                case .missed:
                    Circle().stroke(BoxStyle.strength, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .frame(width: region.width, height: region.height)
                        .position(x: region.midX, y: region.midY)
                    if let fist = match.closestWrist {
                        let point = mapping.screen(fist)
                        Path { path in path.move(to: point); path.addLine(to: CGPoint(x: region.midX, y: region.midY)) }
                            .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                        Circle().fill(BoxStyle.accent).frame(width: 20, height: 20)
                            .overlay { Circle().stroke(.white, lineWidth: 2) }
                            .scaleEffect(burst ? 1 : 1.6)
                            .position(point)
                        Text("Your punch").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.6), in: .capsule)
                            .position(x: point.x, y: point.y + 22)
                    }
                case .uncertain:
                    EmptyView()
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { burst = true } }
        .accessibilityHidden(true)
    }
}

private struct PadBottomHUD: View {
    let camera: PadTrainingCamera
    let director: PadArenaDirector
    let pad: PadTrainingState
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if director.combo >= 2 && pad.feedbackStage != .outcome {
                Text("×\(director.combo)").boxNumber(22, italic: true).foregroundStyle(BoxStyle.strength)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: .capsule)
                    .overlay { Capsule().strokeBorder(BoxStyle.strength.opacity(0.5)) }
                    .accessibilityLabel(Text("Combo \(director.combo)"))
            }
            Text(hint).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 34)
    }
    private var hint: String {
        if pad.phase == .work, pad.feedbackStage == .cue || pad.feedbackStage == .ready {
            if director.reminders || pad.configuration.level == .beginner {
                return pad.hand == .lead ? String(localized: "Lead hand straight out. Rear hand stays home.") :
                    String(localized: "Rear hand straight, turn the hip. Lead hand stays home.")
            }
            return camera.needsReach ? String(localized: "Punch into the ring. Never touch the phone.") : String(localized: "React fast. Reaction only.")
        }
        if pad.feedbackStage == .reset { return String(localized: "Reset to your guard.") }
        if let processing = camera.processingText { return processing }
        return String(localized: "Noncontact. Keep the phone out of reach.")
    }
}

private struct PadPauseMenu: View {
    let camera: PadTrainingCamera
    let director: PadArenaDirector
    let pad: PadTrainingState
    let resume: () -> Void
    let end: () -> Void
    let later: (() -> Void)?
    let fallback: (() -> Void)?
    let skip: (() -> Void)?
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55)).background(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Paused").boxDisplay(56).foregroundStyle(.white)
                Text("\(pad.completedAttempts) attempts · \(Duration.seconds(Int(pad.workSeconds)).formatted(.time(pattern: .minuteSecond))) work")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 10)
                PrimaryButton(title: "Resume", symbol: "play.fill", action: resume)
                if camera.needsReach {
                    Button { resume(); camera.startReachCalibration() } label: {
                        Label("Resume & recalibrate reach", systemImage: "scope").frame(maxWidth: .infinity)
                    }.buttonStyle(BoxSecondaryStyle())
                }
                Toggle(isOn: Binding(get: { director.reminders }, set: { director.reminders = $0 })) {
                    Label("Technique reminders", systemImage: "text.bubble")
                }
                .font(.subheadline.weight(.semibold)).tint(BoxStyle.conditioning)
                .padding(.horizontal, 16).frame(minHeight: 46)
                .background(BoxStyle.surfaceRaised, in: .capsule)
                if let fallback {
                    Button(action: fallback) { Label("Continue guided · keep elapsed work", systemImage: "waveform").frame(maxWidth: .infinity) }
                        .buttonStyle(BoxSecondaryStyle())
                        .accessibilityHint("Camera observations stay separate. Remaining work uses a timer and your own check-in.")
                }
                if let later {
                    Button(action: later) { Label("Continue later", systemImage: "bookmark").frame(maxWidth: .infinity) }
                        .buttonStyle(BoxSecondaryStyle())
                }
                HStack(spacing: 16) {
                    if let skip { Button("Skip activity", role: .destructive, action: skip) }
                    Button("End session", role: .destructive, action: end)
                }
                .font(.subheadline.weight(.semibold)).padding(.top, 4)
                #if DEBUG
                Button(camera.showAlignment ? "Hide alignment overlay" : "Show alignment overlay") { camera.showAlignment.toggle() }
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                #endif
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
    }
}

private struct PadHUDButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.18)) }
        }
        .buttonStyle(BoxPressStyle(scale: 0.88))
        .accessibilityLabel(Text(label))
    }
}

private struct PadHUDCard: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringResource
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34, weight: .bold)).foregroundStyle(color)
            Text(title).boxDisplay(36).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

/// Red pulse on the screen edges while a cue is live: readable in peripheral vision.
private struct PadEdgeGlow: View {
    let color: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RoundedRectangle(cornerRadius: 48, style: .continuous)
            .strokeBorder(color.opacity(on ? 0.9 : 0.45), lineWidth: 10)
            .blur(radius: 10)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

private struct PadTrainingBriefing: View {
    let pad: PadTrainingState
    let begin: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Label(pad.configuration.title, systemImage: "camera.viewfinder").boxEyebrow(.white.opacity(0.85))
                Text("Set up.\nStep back.\nFight.").boxDisplay(44, relativeTo: .title).padding(.top, 10)
            }
            .boxHero(ropes: false)
            .overlay { ViewfinderCorners().padding(10).allowsHitTesting(false) }
            .boxEntrance()
            BoxRowGroup {
                BoxRow(symbol: "iphone", color: BoxStyle.timer, title: String(localized: "Prop your phone at chest height"),
                       subtitle: String(localized: "About 2 m away, safely out of reach"), showsChevron: false)
                BoxRow(symbol: "person.crop.rectangle", color: BoxStyle.conditioning, title: String(localized: "Get your upper body in frame"),
                       subtitle: String(localized: "Head, shoulders and both arms. Legs can be out."), showsChevron: false)
                BoxRow(symbol: "timer", title: String(localized: "We count you in"),
                       subtitle: pad.configuration.effectiveTargetMode == .accuracy ? String(localized: "3-2-1, a quick reach check, then the pads") : String(localized: "3-2-1, then react to each callout"),
                       showsChevron: false)
            }.boxEntrance(1)
            Spacer(minLength: 0)
            Text("Noncontact. Never strike the phone. Experimental recognition—no technique or power grades.")
                .font(.caption).foregroundStyle(BoxStyle.muted)
            PrimaryButton(title: "Open camera", symbol: "camera.fill") { begin() }
        }
        .boxPage()
        .padding(.top, 8)
    }
}

private struct PadCameraStage: View {
    let controller: SessionController
    let camera: PadTrainingCamera
    let pad: PadTrainingState
    var body: some View {
        ZStack {
            PadMirroredPreview(session: camera.engine.session, imageSize: camera.imageSize, rotationDegrees: camera.rotationDegrees)
            if let cue = pad.cueID, pad.phase == .work, camera.trackingReady,
               !camera.needsReach || camera.target?.cueID == cue {
                PadTargetCanvas(cueID: cue, level: pad.configuration.level, target: camera.target,
                                imageSize: camera.imageSize, handTitle: pad.hand == .lead ? "JAB" : "CROSS") { id, visibleMs in
                    guard controller.pad?.cueID == id, controller.pad?.cuePresented == false,
                          camera.present(id: id, hand: pad.hand, level: pad.configuration.level, atMs: visibleMs) else { return false }
                    guard controller.pad?.presented(id) == true else { camera.suspend(); return false }
                    controller.speak(LocalizedStringResource(stringLiteral: pad.hand == .lead ? "Jab" : "Cross"))
                    return true
                }
                .allowsHitTesting(false)
                .accessibilityLabel(camera.needsReach ? (pad.hand == .lead ? "Jab target. Lead hand." : "Cross target. Rear hand.") : (pad.hand == .lead ? "Jab. Reaction only." : "Cross. Reaction only."))
            }
            if pad.feedbackStage == .outcome, let match = camera.lastTargetMatch, match.target.cueID == pad.feedbackID {
                PadImpactOverlay(match: match, imageSize: camera.imageSize)
                    .allowsHitTesting(false)
            }
            if camera.showAlignment {
                PadAlignmentOverlay(points: camera.alignmentPoints, target: pad.cueID == camera.target?.cueID || pad.feedbackID == camera.target?.cueID ? camera.target : nil,
                                    match: camera.lastTargetMatch, imageSize: camera.imageSize, rotationDegrees: camera.rotationDegrees, ageMs: camera.alignmentAgeMs)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

private struct PadReadinessIndicator: View {
    let readiness: PadTrainingCamera.Readiness
    private var color: Color {
        switch readiness {
        case .inView: BoxStyle.conditioning
        case .unclear, .adjust, .delayed: BoxStyle.strength
        case .paused, .unavailable: .white.opacity(0.7)
        }
    }
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 4).accessibilityHidden(true)
            Text(readiness.label).font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.8)
                .lineLimit(1).fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.black.opacity(0.5), in: .capsule)
        .overlay { Capsule().strokeBorder(color.opacity(0.5)) }
        .accessibilityElement(children: .combine)
        // Static signal: no pulsing, flashing or decorative motion during practice.
    }
}

private struct PadTrainingRecap: View {
    let pad: PadTrainingState
    var bestCombo = 0
    let save: () -> Void
    let discard: () -> Void
    var embedded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SessionCompleteBadge(title: pad.endedEarly ? "Practice paused here." : "Practice complete.", subtitle: "Live pads")
                if bestCombo >= 2 {
                    BoxStatTile(label: "Best combo", value: "×\(bestCombo)", symbol: "flame.fill", color: BoxStyle.strength,
                                caption: "Clean hits in a row")
                }
                PadResultSummary(state: pad)
                if pad.workSeconds <= 0 && pad.attempts.isEmpty {
                    BoxInlineNotice(text: "No training was recorded. Discard this setup and try again when the camera is ready.", symbol: "exclamationmark.triangle", color: BoxStyle.strength)
                }
                PrimaryButton(title: embedded ? "Continue session" : "Save practice", symbol: embedded ? "arrow.right" : "checkmark") { save() }.disabled(pad.workSeconds <= 0 && pad.attempts.isEmpty)
                Button(embedded ? "Skip remaining activity" : "Discard practice", role: .destructive) { discard() }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }.boxPage()
        }
    }
}

struct PadResultSummary: View {
    let state: PadTrainingState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.configuration.title).font(.headline)
                    Text("\(state.configuration.level.title) · \(state.configuration.mode == .learn ? "Learn" : "Live rounds") · \(state.configuration.effectiveTargetMode.title)").font(.caption).foregroundStyle(BoxStyle.muted)
                }
                Spacer()
                BoxChip(text: "Beta", color: BoxStyle.accent)
            }
            HStack(spacing: 8) {
                summaryStat("\(state.completedAttempts)", "Attempts")
                summaryStat("\(state.attempts.filter(\.isHit).count)/\(state.attempts.count)", "Recognised")
            }
            if state.configuration.effectiveTargetMode == .accuracy {
                let matches = state.attempts.compactMap(\.targetMatch)
                LabeledContent("2D targets reached", value: "\(matches.filter { $0.outcome == .reached }.count)")
                LabeledContent("Recognised · target missed", value: "\(matches.filter { $0.outcome == .missed }.count)")
                LabeledContent("Recognised · aim unclear, retried", value: "\(matches.filter { $0.outcome == .uncertain }.count)")
                Text("Recognition and target accuracy are separate. Aim-unclear responses retain recognition evidence but do not complete an attempt or count as target misses.")
                    .font(.caption).foregroundStyle(BoxStyle.muted)
            }
            DisclosureGroup("Response breakdown") {
            LabeledContent("Wrong hand", value: "\(state.attempts.filter { $0.outcome == "wrong_hand" }.count)")
            LabeledContent("Straight punch requested", value: "\(state.attempts.filter { $0.outcome == "wrong_kind" }.count)")
            LabeledContent("Moved before the cue", value: "\(state.attempts.filter { $0.outcome == "early" }.count)")
            LabeledContent("No response detected", value: "\(state.attempts.filter { $0.outcome == "miss_timeout" }.count)")
            }
            LabeledContent("Unclear cues · retried", value: "\(state.uncertainAttempts)")
            DisclosureGroup("Tracking & retry details") {
            if let diagnostics = state.diagnostics {
                let causes = diagnostics.camera.interruptionCauses ?? diagnostics.episodeCauses
                LabeledContent("Tracking / camera interruptions", value: "\(diagnostics.camera.interruptionEpisodes ?? diagnostics.trackingEpisodes)")
                LabeledContent("Body visibility interruptions", value: "\(causes.filter { $0.key.hasPrefix("body_") }.values.reduce(0, +))")
                LabeledContent("Processing interruptions", value: "\(causes.filter { PadTrackingGuidance.isProcessing($0.key) }.values.reduce(0, +))")
                LabeledContent("Practice pauses for tracking", value: "\(diagnostics.trackingEpisodes)")
                LabeledContent("Responses unclear · retried", value: "\(state.retries?.count ?? 0)")
                LabeledContent("Cues retried without a miss", value: "\(state.uncertainAttempts)")
                Text("Interruptions count sustained tracking or camera-health loss. Practice pauses count when cueing stops. Brief skipped frames and unclear aiming or recognition do not add interruptions. Retries do not complete attempts or add misses.")
                    .font(.caption).foregroundStyle(BoxStyle.muted)
            } else {
                LabeledContent("Cues retried (older practice)", value: "\(state.uncertainAttempts)")
            }
            }
            let reactions = state.attempts.filter(\.isHit).compactMap(\.reactionMs).filter { $0 >= 0 }.sorted()
            if !reactions.isEmpty {
                let middle = reactions.count / 2
                let median = reactions.count.isMultiple(of: 2) ? (reactions[middle - 1] + reactions[middle]) / 2 : reactions[middle]
                LabeledContent("Median response onset", value: "\(Int(median)) ms")
            }
            Text("Experimental recognition, onset timing and 2D aiming only. No measured physical contact, depth, power or verified technique. Calibration establishes comfortable projected reach and framing.")
                .font(.caption).foregroundStyle(BoxStyle.muted)
            if !state.attempts.isEmpty {
                DisclosureGroup("Punch outcomes") {
                    ForEach(state.attempts) { attempt in
                        LabeledContent(attempt.hand == .lead ? "Jab" : "Cross", value: attempt.title)
                    }
                }.font(.subheadline)
            }
            if let retries = state.retries, !retries.isEmpty {
                DisclosureGroup("Unclear responses · not misses") {
                    ForEach(retries) { retry in
                        LabeledContent(retry.hand == .lead ? "Jab retried" : "Cross retried", value:
                            retry.reason.hasPrefix("target_") ? "Aiming could not be judged" : PadTrackingGuidance.isProcessing(retry.reason) ? "Processing gap" : "Response could not be judged")
                    }
                }.font(.subheadline)
            }
            if let diagnostics = state.diagnostics { PadDiagnosticsSummary(diagnostics: diagnostics) }
        }
        .font(.subheadline).tint(BoxStyle.muted)
        .boxPanel(padding: 18)
    }
    private func summaryStat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).boxNumber(30).foregroundStyle(BoxStyle.ink)
            Text(label).boxEyebrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct PadDiagnosticsSummary: View {
    let diagnostics: PadTrainingDiagnostics
    var body: some View {
        DisclosureGroup("Local camera diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Metadata stays on this iPhone. Frame issue totals count frames, not punches or separate interruptions.")
                Text(verbatim: "Processed frames: \(diagnostics.camera.frames) · source changes: \(diagnostics.camera.generationChanges) · rejected deliveries: \(diagnostics.camera.rejectedDeliveries)")
                Text(verbatim: "Maximum capture age: \(Int(diagnostics.camera.maxCaptureAgeMs)) ms · processing: \(Int(diagnostics.camera.maxProcessingMs)) ms · UI delivery: \(Int(diagnostics.camera.maxDeliveryMs)) ms")
                Text(verbatim: "Interruption causes: " + counts(diagnostics.camera.interruptionCauses ?? diagnostics.episodeCauses))
                Text(verbatim: "Practice-pause causes: " + counts(diagnostics.episodeCauses))
                Text(verbatim: "Recovered errors: " + counts(diagnostics.camera.recoveredErrors ?? [:]))
                Text(verbatim: "Retry causes: " + counts(diagnostics.retryCauses))
                Text(verbatim: "Frame issues: " + counts(diagnostics.camera.frameIssues))
                if let disagreements = diagnostics.camera.legacyPresenceDisagreements {
                    Text("Recovered full-body framing disagreed on \(disagreements) frames. This is a policy comparison, not a tracking-loss count.")
                }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline)
    }
    private func counts(_ values: [String: Int]) -> String {
        let text = values.keys.sorted().map { "\($0): \(values[$0] ?? 0)" }.joined(separator: ", ")
        return text.isEmpty ? "None" : text
    }
}

struct PadMirroredPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let imageSize: CGSize
    let rotationDegrees: Int
    func makeUIView(context: Context) -> PadPreviewSurface { PadPreviewSurface() }
    func updateUIView(_ view: PadPreviewSurface, context: Context) {
        view.previewLayer.session = session; view.imageSize = imageSize; view.rotationDegrees = rotationDegrees
        view.setNeedsLayout()
    }
}
final class PadPreviewSurface: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var imageSize = CGSize(width: 720, height: 1280)
    var rotationDegrees = 90
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .black; clipsToBounds = true; layer.addSublayer(previewLayer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        previewLayer.frame = PadCameraTransform(image: imageSize, viewport: bounds.size).imageRect
        previewLayer.videoGravity = .resizeAspect
        if let connection = previewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
            // Use the very same quarter-turn that produced the upright pose,
            // rather than an independently horizon-levelled preview angle.
            let angle = CGFloat(rotationDegrees)
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        CATransaction.commit()
    }
}

private struct PadAlignmentOverlay: View {
    let points: [PadPoint?]
    let target: PadTargetDefinition?
    let match: PadTargetMatch?
    let imageSize: CGSize
    let rotationDegrees: Int
    let ageMs: Int
    var body: some View {
        Canvas { context, size in
            let mapping = PadCameraTransform(image: imageSize, viewport: size)
            context.stroke(Path(mapping.imageRect), with: .color(.cyan), lineWidth: 1)
            for (a, b) in [(5, 7), (7, 9), (6, 8), (8, 10), (5, 6)] {
                if points.indices.contains(b), let start = points[a], let end = points[b] {
                    var line = Path(); line.move(to: mapping.screen(start)); line.addLine(to: mapping.screen(end))
                    context.stroke(line, with: .color(.cyan), lineWidth: 2)
                }
            }
            for index in [5, 6, 7, 8, 9, 10] {
                if points.indices.contains(index), let point = points[index] {
                    let location = mapping.screen(point)
                    context.fill(Path(ellipseIn: CGRect(x: location.x - 4, y: location.y - 4, width: 8, height: 8)), with: .color(.yellow))
                    let label = index == 5 ? "L shoulder" : index == 6 ? "R shoulder" : index == 7 ? "L elbow" : index == 8 ? "R elbow" : index == 9 ? "L wrist" : "R wrist"
                    context.draw(Text(verbatim: label).font(.caption2).foregroundStyle(.yellow), at: CGPoint(x: location.x, y: location.y - 12))
                }
            }
            if let target {
                context.stroke(Path(ellipseIn: mapping.region(target)), with: .color(.pink), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                if match?.target.cueID == target.cueID, let point = match?.closestWrist {
                    let location = mapping.screen(point)
                    context.stroke(Path(ellipseIn: CGRect(x: location.x - 7, y: location.y - 7, width: 14, height: 14)), with: .color(.pink), lineWidth: 3)
                }
            }
            context.draw(Text(verbatim: "DEV · anatomical L/R · mirrored · fit · \(rotationDegrees)°\nPose age at delivery: \(ageMs) ms · live preview leads pose\nPink = judged region / closest peak path; yellow = joints").font(.caption2).foregroundStyle(.white),
                         at: CGPoint(x: size.width / 2, y: 24))
        }
    }
}

#if DEBUG
/// Design QA gallery: the real arena views posed in each state, no camera needed.
struct PadArenaGallery: View {
    let state: String
    @State private var controller: SessionController
    @State private var camera: PadTrainingCamera
    @State private var director = PadArenaDirector()
    private let pad: PadTrainingState
    init(state: String) {
        self.state = state
        let configuration = PadConfiguration(level: .intermediate, targetMode: .reaction)
        var pad = PadTrainingState(configuration: configuration)
        pad.begin()
        if state != "framing" && state != "countdown" {
            for t in stride(from: 0.0, through: 1.2, by: 0.1) { pad.tick(at: t, trackingReady: true, cueingReady: true, scoringReady: true) }
            if let id = pad.cueID {
                pad.presented(id)
                if state == "hit" { pad.resolve(id: id, outcome: "hit_green", reactionMs: 312, at: 1.6) }
                if state == "miss" { pad.resolve(id: id, outcome: "wrong_hand", reactionMs: 280, at: 1.6) }
            }
        }
        self.pad = pad
        var launch = SessionLaunch(configuration: .init(), focus: .mixed)
        launch.pad = pad
        _controller = State(initialValue: SessionController(launch: launch, voiceEnabled: false))
        _camera = State(initialValue: PadTrainingCamera(configuration: configuration))
    }
    var body: some View {
        PadArena(controller: controller, camera: camera, director: director, pad: pad, checkpoint: {},
                 end: {}, later: nil, fallback: nil, skip: nil)
            .background {
                LinearGradient(colors: [Color(white: 0.32), Color(white: 0.14)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
            .overlay {
                if state == "mitt" {
                    Canvas { context, size in
                        let side = min(size.width, size.height) * 0.42
                        let region = CGRect(x: (size.width - side) / 2, y: size.height * 0.36, width: side, height: side)
                        context.withCGContext { PadMittArt.draw(in: region, context: $0) }
                    }
                    .allowsHitTesting(false).ignoresSafeArea()
                }
            }
            .onAppear {
                switch state {
                case "countdown": director.debugPose(armed: false, countdown: 2)
                case "framing": director.debugPose(armed: false)
                default: director.debugPose(armed: true, combo: state == "hit" ? 3 : 0)
                }
            }
    }
}
#endif
