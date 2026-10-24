import SwiftUI
import AVFoundation

struct PadTrainingSetupView: View {
    let store: AppStore
    let activityID: String?
    @State private var configuration = PadConfiguration()
    @State private var instructionsRead = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Label("Camera · Live pads", systemImage: "camera.viewfinder").boxEyebrow(.white.opacity(0.85))
                        Spacer()
                        BoxChip(text: "Beta", onHero: true)
                    }
                    Text(activityID == nil ? "Live pads" : "Camera practice").boxDisplay(40, relativeTo: .title).padding(.top, 10)
                    Text("Straight punches. A clear focus.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                }.boxHero().boxEntrance()
                BoxInlineNotice(text: "Noncontact shadowboxing. Support the phone outside your reach. Never strike the phone or screen.", symbol: "exclamationmark.shield.fill", color: BoxStyle.strength)
                    .boxEntrance(1)
                BoxSectionHeader(title: "Your practice").padding(.top, 8)
                VStack(alignment: .leading, spacing: 14) {
                    if activityID == nil {
                        BoxSegmented(options: [PadConfiguration.Mode.learn, .rounds],
                                     selection: Binding(get: { configuration.mode }, set: { configuration.mode = $0 }),
                                     title: { $0 == .learn ? "Learn" : "Live rounds" },
                                     symbol: { $0 == .learn ? "graduationcap.fill" : "timer" })
                    }
                    Picker("Stance", selection: $configuration.stance) {
                        Text("Orthodox · left lead").tag(BoxMaxxingJudge.Stance.orthodox)
                        Text("Southpaw · right lead").tag(BoxMaxxingJudge.Stance.southpaw)
                    }.tint(BoxStyle.ink)
                    if configuration.mode == .learn {
                        Stepper("Attempts: \(configuration.attempts)", value: $configuration.attempts, in: 4...24, step: 2)
                        Text("Jab/cross cues arrive one at a time. Reset between attempts.").font(.caption).foregroundStyle(BoxStyle.muted)
                    } else {
                        Stepper("Rounds: \(configuration.rounds)", value: $configuration.rounds, in: 1...6)
                        Picker("Work", selection: $configuration.workSeconds) { Text("30 sec").tag(30); Text("60 sec").tag(60); Text("2 min").tag(120) }.tint(BoxStyle.ink)
                        Picker("Rest", selection: $configuration.restSeconds) { Text("15 sec").tag(15); Text("30 sec").tag(30); Text("60 sec").tag(60) }.tint(BoxStyle.ink)
                    }
                }.font(.subheadline).boxPanel().boxEntrance(2)
                BoxSectionHeader(title: "Guidance & feedback").padding(.top, 8)
                VStack(alignment: .leading, spacing: 12) {
                    BoxSegmented(options: PadLevel.allCases, selection: Binding(get: { configuration.level }, set: { configuration.level = $0 }),
                                 title: { LocalizedStringResource(stringLiteral: $0.title) })
                    Text(configuration.level.explanation).font(.footnote).foregroundStyle(BoxStyle.muted)
                    BoxSegmented(options: PadTargetMode.allCases, selection: Binding(get: { configuration.effectiveTargetMode }, set: { configuration.targetMode = $0 }),
                                 title: { LocalizedStringResource(stringLiteral: $0.title) })
                        .padding(.top, 4)
                    Text(configuration.effectiveTargetMode == .accuracy ? "Recognise jab/cross and judge calibrated 2D aiming. First, capture your comfortable reach with each requested hand." : "Recognise the requested jab/cross and measure response onset. No target accuracy is judged.")
                        .font(.footnote).foregroundStyle(BoxStyle.muted)
                }.boxPanel().boxEntrance(3)
                if let activity = ActivityCatalog.find(activityID ?? "jab-reset-v1") {
                    ActivityInstructions(activity: activity, mode: .shadowboxing)
                }
                if activityID == nil || activityID == "jab-cross-reset-v1" {
                    BoxInlineNotice(text: "Jab = lead hand. Cross = rear hand. For the cross, turn your rear hip gently as your rear hand travels straight. Return to guard after each punch. Keep both punches light and do not lock your elbows.", symbol: "figure.boxing", color: BoxStyle.accent)
                }
                Toggle("I’ve read the setup and movement instructions", isOn: $instructionsRead)
                    .font(.subheadline.weight(.semibold)).tint(BoxStyle.conditioning)
                    .boxPanel()
                    .sensoryFeedback(.selection, trigger: instructionsRead)
                Text("Beta · Experimental recognition and timing. No technique or power grades.").font(.caption).foregroundStyle(BoxStyle.muted)
                PrimaryButton(title: "Open camera practice", symbol: "camera.fill") { store.startPad(configuration) }
                    .disabled(!instructionsRead || !configuration.isValid)
                DevelopmentNote(text: "No demonstration video is available. Instructions await coach review. You can use guided practice instead. Camera accuracy depends on framing and device conditions.")
            }.boxPage()
        }.boxScreen().foregroundStyle(BoxStyle.ink)
            .navigationTitle("Camera training").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear {
                configuration.activityID = activityID
                configuration.level = .suggested(experience: store.profile.experience)
                configuration.stance = store.stance == "Southpaw" ? .southpaw : .orthodox
            }
    }
}

struct PadTrainingPlayer: View {
    let controller: SessionController
    let save: () -> Void
    let discard: () -> Void
    let checkpoint: () -> Void
    var fallback: (() -> Void)?
    @State private var camera: PadTrainingCamera
    private var pad: PadTrainingState { controller.pad! }
    private var cameraNeeded: Bool { guard let pad = controller.pad else { return false }; return pad.phase != .briefing && pad.phase != .paused && pad.phase != .recap }
    init(controller: SessionController, save: @escaping () -> Void, discard: @escaping () -> Void, checkpoint: @escaping () -> Void, fallback: (() -> Void)? = nil) {
        self.controller = controller; self.save = save; self.discard = discard; self.checkpoint = checkpoint
        self.fallback = fallback
        _camera = State(initialValue: PadTrainingCamera(configuration: controller.pad!.configuration, diagnostics: controller.pad!.diagnostics?.camera ?? .init()))
    }
    var body: some View {
        VStack(spacing: 0) {
            if let pad = controller.pad {
            if pad.phase == .briefing {
                PadTrainingBriefing(pad: pad, begin: { controller.begin() })
            } else if pad.phase == .recap {
                PadTrainingRecap(pad: pad, save: save, discard: discard, embedded: controller.execution != nil)
            } else {
                PadTrainingScene(controller: controller, camera: camera, checkpoint: checkpoint, pad: pad)
            }
            }
            if let fallback, controller.pad != nil {
                HStack {
                    Button("Continue guided · Keep elapsed work") {
                        camera.suspend(); camera.stop(); fallback()
                    }.buttonStyle(BoxSecondaryStyle())
                    .accessibilityHint("Camera observations stay separate. Remaining work uses a timer and your own check-in.")
                    Menu {
                        Button("Skip this activity", role: .destructive) { camera.suspend(); camera.stop(); discard() }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Assigned activity options")
                }.padding(12)
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
        .onChange(of: controller.pad?.cueID) { _, id in if id == nil && controller.pad?.cueID == nil { camera.suspend() } }
        .onChange(of: camera.reachStage) { _, stage in
            if let pad = controller.pad, camera.needsReach, pad.phase != .paused, pad.feedbackStage != .outcome, pad.feedbackStage != .reset {
                controller.speak(LocalizedStringResource(stringLiteral: camera.reachInstruction))
            }
        }
        .onDisappear { camera.stop() }
    }
    private func step() {
        guard let current = controller.pad, current.phase != .briefing && current.phase != .paused && current.phase != .recap else { return }
        let now = ProcessInfo.processInfo.systemUptime
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
                controller.pad?.resolve(id: result.id, outcome: result.outcome, reactionMs: result.reactionMs, at: now, targetMatch: result.targetMatch)
            case .unjudged(let id, let reason):
                controller.pad?.retryResponse(id: id, reason: reason, at: now)
            }
        }
        controller.pad?.diagnostics?.camera = camera.diagnosticsSnapshot()
        controller.pad?.tick(at: now, trackingReady: camera.trackingReady, trackingReason: camera.trackingReason,
                             speechBusy: controller.isSpeaking, cueingReady: camera.canPresentCue, scoringReady: camera.scoringReady)
        if let id = pad.cueID, !pad.cuePresented, !camera.prepare(id: id, hand: pad.hand) { controller.pad?.targetSetupRequired() }
        camera.setReachSampling(pad.feedbackStage != .cue && pad.feedbackStage != .outcome && pad.feedbackStage != .reset && pad.phase != .rest)
        // State transitions, visible feedback and speech use the same source in
        // this actor turn. No delayed onChange can read the next cue's wording.
        if pad.feedbackStage != .cue && pad.feedbackStage != .outcome && (pad.feedback != oldFeedback || pad.feedbackStage != oldStage) {
            controller.speak(LocalizedStringResource(stringLiteral: pad.spokenFeedback))
        }
        if pad.attempts.count != oldCount || pad.diagnostics?.trackingEpisodes != oldEpisodes ||
            pad.diagnostics?.camera.interruptionEpisodes != oldCameraEpisodes ||
            (pad.feedbackStage == .outcome && oldStage != .outcome) { checkpoint() }
    }
}

private struct PadTrainingBriefing: View {
    let pad: PadTrainingState
    let begin: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(pad.configuration.title, systemImage: "camera.viewfinder").boxEyebrow(.white.opacity(0.85))
                    Text("Set up your\ncamera.").boxDisplay(40, relativeTo: .title).padding(.top, 10)
                    Text("Room to move. A phone safely out of reach.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                }
                .boxHero(ropes: false)
                .overlay { ViewfinderCorners().padding(10).allowsHitTesting(false) }
                .boxEntrance()
                VStack(alignment: .leading, spacing: 12) {
                    BoxFeatureLabel(title: "Frame your upper body", symbol: "person.crop.rectangle", color: BoxStyle.timer)
                    Text("Keep your head, both shoulders, elbows and hands visible, with room to extend both arms. Your hips, knees and feet can stay outside the frame.").font(.subheadline)
                    Text("If straight-on arm travel is too small to measure, try a slight camera angle while keeping both shoulders visible.").font(.footnote).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 18, tint: BoxStyle.timer).boxEntrance(1)
                VStack(alignment: .leading, spacing: 12) {
                    BoxFeatureLabel(title: "Follow the cues", symbol: "hand.raised.fill")
                    Text(pad.configuration.level.explanation).font(.subheadline)
                    Text(pad.configuration.effectiveTargetMode == .accuracy ? "Capture your comfortable reach, then send each straight punch toward its ring. The whole ring is the 2D acceptance area. Return to guard between cues. Changes in distance or body angle require recalibration." : "React to the requested straight punch, then return to guard. This mode measures response onset without target accuracy.")
                        .font(.footnote).foregroundStyle(BoxStyle.muted)
                    HStack(spacing: 6) {
                        BoxChip(text: "Jab = lead hand", color: BoxStyle.accent)
                        BoxChip(text: "Cross = rear hand", color: BoxStyle.accent)
                    }
                    Text("Extend lightly without locking the elbow. Keep the other hand near your cheek, then return to guard.").font(.caption).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 18, tint: BoxStyle.accent).boxEntrance(2)
                PrimaryButton(title: "Start camera setup", symbol: "camera.fill") { begin() }
                Text("Experimental recognition · Tracking interruptions are separate from missed responses. No technique, depth, contact, power or force grades.").font(.caption).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }
    }
}

private struct PadTrainingScene: View {
    let controller: SessionController
    let camera: PadTrainingCamera
    let checkpoint: () -> Void
    let pad: PadTrainingState
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        PadReadinessIndicator(readiness: pad.phase == .paused ? .paused : camera.readiness)
                        Text(pad.configuration.level.title + " · " + pad.configuration.effectiveTargetMode.title).font(.caption2)
                    }
                    Spacer()
                    Text(pad.configuration.mode == .learn ? "\(pad.completedAttempts) / \(pad.configuration.attempts)" : "Round \(pad.round) / \(pad.configuration.rounds)")
                        .boxNumber(18)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: .capsule)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
                    Menu {
                        Button(camera.showAlignment ? "Hide development alignment" : "Show development alignment") { camera.showAlignment.toggle() }
                        if camera.needsReach {
                            Button("Recalibrate comfortable reach") { camera.startReachCalibration() }
                                .disabled(pad.cueID != nil || pad.feedbackStage == .outcome || pad.feedbackStage == .reset)
                        }
                    } label: { Image(systemName: "ellipsis.circle").padding(8) }
                    .accessibilityLabel("Camera options")
                }
                PadCameraStage(controller: controller, camera: camera, pad: pad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.1)) }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { camera.setViewport($0) }
                // Controls occupy their own area; targets are never clamped or
                // moved around cards, safe areas or buttons.
                PadFeedbackPanel(controller: controller, camera: camera, checkpoint: checkpoint, pad: pad)
                    .frame(maxHeight: geometry.size.height * 0.44)
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
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
            if camera.showAlignment {
                PadAlignmentOverlay(points: camera.alignmentPoints, target: pad.cueID == camera.target?.cueID || pad.feedbackID == camera.target?.cueID ? camera.target : nil,
                                    match: camera.lastTargetMatch, imageSize: camera.imageSize, rotationDegrees: camera.rotationDegrees, ageMs: camera.alignmentAgeMs)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

private struct PadFeedbackPanel: View {
    let controller: SessionController
    let camera: PadTrainingCamera
    let checkpoint: () -> Void
    @State private var showHelp = false
    let pad: PadTrainingState
    private var heading: String {
        if pad.phase == .paused { return "Paused" }
        if pad.phase == .rest { return "Rest & reset" }
        if pad.feedbackStage == .outcome || pad.feedbackStage == .reset || pad.feedbackStage == .retry { return pad.feedback }
        if let error = camera.error { return error }
        if let processing = camera.processingText { return processing }
        if camera.needsReach && !camera.reachReady { return camera.reachInstruction }
        if pad.phase == .calibrating { return camera.calibrationText }
        return pad.feedback
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if pad.feedbackStage == .outcome {
                    Image(systemName: pad.feedbackSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(pad.feedbackSucceeded ? BoxStyle.conditioning : BoxStyle.strength)
                        .accessibilityHidden(true)
                }
                Text(heading)
            }.boxSection(24).fixedSize(horizontal: false, vertical: true)
            .background {
                if pad.feedbackStage == .outcome, let feedbackID = pad.feedbackID {
                    let message = pad.spokenFeedback
                    PadOutcomeAcknowledgement(id: feedbackID) { id, submittedAt in
                        guard controller.pad?.feedbackPresented(id: id, at: submittedAt) == true else { return }
                        controller.speak(LocalizedStringResource(stringLiteral: message))
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let detail = pad.feedbackDetail, detail != pad.feedback { Text(detail).font(.subheadline) }
                    if pad.phase == .rest {
                        Text("\(max(0, pad.configuration.restSeconds - Int(pad.roundSeconds))) seconds").monospacedDigit()
                    } else if pad.phase == .work && pad.configuration.mode == .rounds {
                        Text("\(max(0, pad.configuration.workSeconds - Int(pad.roundSeconds))) seconds remaining").monospacedDigit().font(.caption)
                    }
                    if camera.needsReach && camera.processingText == nil && camera.error == nil && pad.phase != .paused && pad.feedbackStage != .outcome && pad.feedbackStage != .reset {
                        Text(camera.reachInstruction).font(.subheadline)
                        if let notice = camera.targetNotice { Text(notice).font(.subheadline).foregroundStyle(BoxStyle.strength) }
                        if camera.reachStage == .idle || camera.reachStage == .failed || camera.targetNotice?.hasPrefix("Your calibrated") == true || camera.targetNotice?.hasPrefix("Projected reach") == true {
                            Button("Capture comfortable reach") { camera.startReachCalibration() }
                                .buttonStyle(BoxSecondaryStyle()).disabled(!camera.trackingReady || pad.cueID != nil)
                            Text("Hands-free setup: guard, extend and hold each requested hand, then return to guard. Reach and framing only; no technique certification.")
                                .font(.caption)
                        }
                    }
                    if pad.feedbackStage == .outcome && pad.attempts.last?.outcome == "wrong_hand" {
                        Text(pad.hand == .lead ? "The jab uses your lead hand." : "The cross uses your rear hand.").font(.subheadline)
                    } else if (pad.configuration.level == .beginner || showHelp) && pad.feedbackStage != .outcome {
                        Text(pad.hand == .lead ? "Lead hand straight out. Keep the rear hand home; return to guard." : "Rear hand straight with a gentle hip turn. Keep the lead hand home; return to guard.")
                            .font(.subheadline)
                        Text(camera.needsReach ? "2D target only. Never touch the phone." : "Reaction only · no target accuracy score.")
                            .font(.caption)
                    }
                    PadCameraGuidance(camera: camera, paused: pad.phase == .paused)
                    if let notice = controller.audioNotice { Text(notice).font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if pad.configuration.level != .beginner { Button(showHelp ? "Hide reminders" : "Reminders") { showHelp.toggle() }.buttonStyle(BoxSecondaryStyle()) }
                Button(pad.phase == .paused ? "Resume & recalibrate" : "Pause") {
                    camera.suspend()
                    if pad.phase == .paused { controller.resume() } else { controller.pause() }
                    checkpoint()
                }.buttonStyle(BoxSecondaryStyle())
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(BoxStyle.surface.opacity(0.94), in: .rect(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(BoxStyle.border) }
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
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(readiness.label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.6), in: .capsule)
        .overlay { Capsule().strokeBorder(color.opacity(0.4)) }
        .accessibilityElement(children: .combine)
        // Static signal: no pulsing, flashing or decorative motion during practice.
    }
}

private struct PadCameraGuidance: View {
    let camera: PadTrainingCamera
    let paused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = camera.error { Text(error) }
            else if paused { Text("Resume when you’re ready.") }
            else if let processing = camera.processingText { Text(processing) }
            else {
                Text(camera.calibrationText)
                if let recognition = camera.recognitionText { Text(recognition) }
                else if camera.tracking != camera.calibrationText { Text(camera.tracking) }
            }
        }.font(.caption).foregroundStyle(.white.opacity(0.8))
    }
}

private struct PadTrainingRecap: View {
    let pad: PadTrainingState
    let save: () -> Void
    let discard: () -> Void
    var embedded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SessionCompleteBadge(title: pad.endedEarly ? "Practice paused here." : "Practice complete.", subtitle: "Live pads")
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

private struct PadMirroredPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let imageSize: CGSize
    let rotationDegrees: Int
    func makeUIView(context: Context) -> PadPreviewSurface { PadPreviewSurface() }
    func updateUIView(_ view: PadPreviewSurface, context: Context) {
        view.previewLayer.session = session; view.imageSize = imageSize; view.rotationDegrees = rotationDegrees
        view.setNeedsLayout()
    }
}
private final class PadPreviewSurface: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var imageSize = CGSize(width: 720, height: 1280)
    var rotationDegrees = 90
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .black; layer.addSublayer(previewLayer) }
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
