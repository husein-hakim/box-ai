import AVFoundation
import SwiftUI
import UIKit

struct SessionPlayer: View {
    let store: AppStore
    @State private var controller: SessionController
    @State private var showStopConfirmation = false
    @State private var checkpointTime: Double = 0
    @State private var savedRecord: SessionRecord?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let autoBegin: Bool

    init(launch: SessionLaunch, voiceEnabled: Bool, store: AppStore, autoBegin: Bool = false) {
        self.store = store
        self.autoBegin = autoBegin
        // The full-screen presentation owns one controller for this immutable launch.
        _controller = State(initialValue: SessionController(launch: launch, voiceEnabled: voiceEnabled))
    }

    var body: some View {
        NavigationStack {
            Group {
            if let savedRecord {
                SessionSavedContent(store: store, record: savedRecord)
            } else if controller.pad != nil {
                PadTrainingPlayer(controller: controller,
                    save: {
                        if controller.execution != nil { controller.finishCameraSet(); saveCheckpoint() }
                        else { saveRecord() }
                    },
                    discard: {
                        if controller.execution != nil { controller.skip(); saveCheckpoint() }
                        else if store.discardCheckpoint() { dismiss() }
                    }, checkpoint: saveCheckpoint,
                    fallback: controller.execution == nil ? nil : { controller.continueGuided(); saveCheckpoint() },
                    end: { controller.pause(); showStopConfirmation = true },
                    later: {
                        controller.pause(reason: "Saved here. Resume when you are ready.")
                        saveCheckpoint()
                        if store.pendingSession?.id == controller.launch.id { dismiss() }
                    })
                .id("\(controller.execution?.current?.id ?? "standalone"):\(controller.execution?.set ?? 0)")
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if controller.execution != nil {
                        GuidedPlayerContent(controller: controller, save: { saveRecord(feedback: $0, effort: $1) },
                                            discard: { if store.discardCheckpoint() { dismiss() } }, checkpoint: saveCheckpoint,
                                            stance: store.stance == "Southpaw" ? .southpaw : .orthodox,
                                            level: .suggested(experience: store.profile.experience),
                                            stanceKnown: ["Orthodox", "Southpaw"].contains(store.stance))
                    } else if controller.status == .ready {
                        sessionOverview
                    } else if controller.isTerminal {
                        sessionRecap
                    } else {
                        activeRound
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            }
            }
            .boxScreen()
            .toolbar(arenaActive ? .hidden : .visible, for: .navigationBar)
            .toolbar(arenaActive ? .hidden : .automatic, for: .bottomBar)
            .navigationTitle(controller.execution?.session.title ?? controller.pad?.configuration.title ?? "Guided rounds").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedRecord != nil || controller.status == .ready ? "Close" : "End") {
                        if savedRecord != nil || controller.status == .ready || controller.isTerminal { dismiss() }
                        else {
                            controller.pause()
                            showStopConfirmation = true
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { controller.toggleVoice() } label: {
                        Image(systemName: controller.voiceEnabled ? "speaker.wave.2" : "speaker.slash")
                    }
                    .accessibilityLabel(controller.voiceEnabled ? "Mute spoken cues" : "Enable spoken cues")
                }
                if savedRecord == nil && controller.status != .ready && !controller.isTerminal {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Continue later") {
                            controller.pause(reason: "Saved here. Resume when you are ready.")
                            saveCheckpoint()
                            if store.pendingSession?.id == controller.launch.id { dismiss() }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(controller.status != .ready)
        .confirmationDialog("End this session?", isPresented: $showStopConfirmation, titleVisibility: .visible) {
            Button("End and review", role: .destructive) { controller.stop() }
            Button("Keep paused", role: .cancel) { }
        } message: {
            Text("Review completed, partial and skipped work before saving.")
        }
        .task {
            if autoBegin && controller.status == .ready {
                controller.begin()
                if controller.execution != nil { controller.startActivity() }
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { break }
                controller.tick()
                if controller.activeSeconds - checkpointTime >= 15 { saveCheckpoint() }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                controller.pause(reason: "Paused for an audio interruption. Resume when you are ready.")
                saveCheckpoint()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                controller.pause(reason: "Paused while the app was away. Resume when you are ready.")
                saveCheckpoint()
            }
        }
        .onChange(of: controller.status) { _, status in
            UIApplication.shared.isIdleTimerDisabled = status == .running
            saveCheckpoint()
        }
        .onDisappear {
            controller.cleanUp()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// The full-screen camera arena owns its own HUD controls.
    private var arenaActive: Bool {
        guard savedRecord == nil, let pad = controller.pad else { return false }
        return pad.phase != .briefing && pad.phase != .recap
    }

    private var sessionOverview: some View {
        let configuration = controller.launch.configuration
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .center, spacing: 10) {
                Text("Reaction training").boxEyebrow(BoxStyle.accent)
                Text("Read. React.\nReset.").boxDisplay(54).multilineTextAlignment(.center)
                Text(controller.launch.focus.title).font(.subheadline).foregroundStyle(BoxStyle.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.top, 8).boxEntrance()
            HStack(spacing: 0) {
                overviewStat("\(configuration.rounds)", "Rounds")
                Rectangle().fill(BoxStyle.border).frame(width: 1)
                overviewStat(Duration.seconds(configuration.workSeconds).formatted(.time(pattern: .minuteSecond)), "Work")
                Rectangle().fill(BoxStyle.border).frame(width: 1)
                overviewStat(configuration.rounds > 1 ? Duration.seconds(configuration.restSeconds).formatted(.time(pattern: .minuteSecond)) : "–", "Rest")
            }
            .fixedSize(horizontal: false, vertical: true)
            .boxPanel(padding: 0).boxEntrance(1)
            BoxSectionHeader(title: "How it runs") {
                Text("Total \(Duration.seconds(configuration.totalSeconds).formatted(.time(pattern: .minuteSecond)))")
            }.padding(.top, 8).boxEntrance(2)
            BoxRowGroup {
                BoxRow(symbol: "figure.stand", color: BoxStyle.timer, title: String(localized: "Prepare"), subtitle: String(localized: "1 minute"), showsChevron: false)
                BoxRow(symbol: "figure.boxing", title: String(localized: "Work"), subtitle: String(localized: "\(configuration.rounds) rounds · \(configuration.workSeconds) sec"), showsChevron: false)
                if configuration.rounds > 1 {
                    BoxRow(symbol: "pause.fill", color: BoxStyle.timer, title: String(localized: "Between rounds"), subtitle: String(localized: "\(configuration.restSeconds) sec rest"), showsChevron: false)
                }
                BoxRow(symbol: "wind", color: BoxStyle.conditioning, title: String(localized: "Reset"), subtitle: String(localized: "1 minute"), showsChevron: false)
            }.boxEntrance(3)
            BoxInlineNotice(text: "Guided audio & timer · No camera measurements. Clear about 2 m of space around you.", symbol: "checkmark.shield", color: BoxStyle.conditioning)
                .boxEntrance(4)
            DevelopmentNote(text: "Original instructions pending boxing-coach review. No demonstration media is available.")
            PrimaryButton(title: "Begin guided round") { controller.begin() }
                .accessibilityIdentifier("session.begin")
                .padding(.top, 4)
        }.foregroundStyle(BoxStyle.ink)
    }

    private func overviewStat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).boxNumber(30)
            Text(label).boxEyebrow()
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private var activeRound: some View {
        let block = controller.timeline.current
        let isWork = block?.kind == .work
        let paused = controller.status == .paused
        let fraction = block.map { $0.seconds > 0 ? controller.timeline.remaining / $0.seconds : 0 } ?? 0
        let rounds = controller.launch.configuration.rounds
        return VStack(spacing: 22) {
            HStack(spacing: 5) {
                ForEach(1...max(1, rounds), id: \.self) { round in
                    let done = round < (block?.round ?? 0) || (round == block?.round && block?.kind != .work && block?.kind != .prepare)
                    let current = round == block?.round && isWork
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(BoxStyle.accent)
                                .frame(width: geometry.size.width * (done ? 1 : current ? 1 - fraction : 0))
                        }
                    }.frame(height: 5)
                }
            }
            .frame(maxWidth: 220)
            .accessibilityHidden(true)
            Text(paused ? "Paused" : isWork ? "Round \(block?.round ?? 1) of \(rounds) · Work" : controller.phaseTitle)
                .boxEyebrow(paused ? BoxStyle.strength : isWork ? BoxStyle.accent : BoxStyle.timer)
                .contentTransition(.opacity)
            BoxTimerDial(remaining: controller.remainingText, fraction: fraction, color: isWork ? BoxStyle.accent : BoxStyle.timer,
                         label: paused ? "Paused" : "Remaining", dimmed: paused)
            VStack(spacing: 10) {
                Text(isWork ? "Throw now" : "Now").boxEyebrow()
                Text(paused ? "Paused" : isWork ? controller.cue.title : controller.phaseTitle)
                    .boxDisplay(40, relativeTo: .title)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(isWork && !paused ? AnyShapeStyle(BoxStyle.heroGradient) : AnyShapeStyle(BoxStyle.timer.opacity(0.12)))
                            .shadow(color: isWork && !paused ? BoxStyle.accent.opacity(0.5) : .clear, radius: 18, y: 10)
                    }
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(isWork && !paused ? .white.opacity(0.25) : BoxStyle.timer.opacity(0.35)) }
                    .foregroundStyle(isWork && !paused ? .white : BoxStyle.timer)
                    .id(controller.issuedCues)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 1.08).combined(with: .opacity), removal: .opacity))
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: controller.issuedCues)
                Text(controller.phaseDetail).font(.subheadline).foregroundStyle(BoxStyle.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let reason = controller.pauseReason {
                Text(reason).font(.footnote).foregroundStyle(BoxStyle.muted).multilineTextAlignment(.center)
            }
            if let notice = controller.audioNotice { BoxInlineNotice(text: notice) }
            HStack(spacing: 28) {
                Color.clear.frame(width: 58, height: 58)
                Button {
                    if paused { controller.resume() } else { controller.pause() }
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 30, weight: .bold))
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                        .frame(width: 88, height: 88)
                        .background(.white, in: .circle)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                }
                .buttonStyle(BoxPressStyle(scale: 0.9))
                .accessibilityLabel(paused ? "Resume round" : "Pause round")
                .accessibilityIdentifier("session.pauseResume")
                Button { controller.skip(); saveCheckpoint() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 18, weight: .bold))
                        .frame(width: 58, height: 58).boxGlassControl(cornerRadius: 29)
                }
                .buttonStyle(BoxPressStyle(scale: 0.9))
                .accessibilityLabel("Skip this block")
            }
            .padding(.top, 6)
            Text("\(controller.issuedCues) cues issued · Unscored")
                .font(.caption).foregroundStyle(BoxStyle.muted)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(BoxStyle.ink)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: paused)
    }

    private var sessionRecap: some View {
        VStack(alignment: .leading, spacing: 16) {
            SessionCompleteBadge(title: controller.status == .finished ? "Timer finished." : "You called time.",
                                 subtitle: "Here’s the work you timed.")
            HStack(spacing: 0) {
                recapStat(Duration.seconds(Int(controller.timeline.workSeconds)).formatted(.time(pattern: .minuteSecond)), "Work time")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                recapStat(controller.timeline.completedRounds.formatted(), "Full rounds")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                recapStat(controller.issuedCues.formatted(), "Cues")
            }
            .fixedSize(horizontal: false, vertical: true)
            .boxHero(padding: 18).boxEntrance(1)
            if controller.timeline.skippedBlocks > 0 {
                BoxRow(symbol: "forward.end.fill", color: BoxStyle.muted, title: String(localized: "Blocks skipped"), showsChevron: false) {
                    Text(controller.timeline.skippedBlocks.formatted()).boxNumber(18)
                }.boxPanel(padding: 0)
            }
            Text("Timer & audio records · No punch or technique measurements").font(.caption).foregroundStyle(BoxStyle.muted)
            PrimaryButton(title: "Save practice", symbol: "checkmark") {
                saveRecord()
            }.accessibilityIdentifier("session.save")
            Button("Discard practice", role: .destructive) { if store.discardCheckpoint() { dismiss() } }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }.foregroundStyle(BoxStyle.ink)
    }

    private func recapStat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).boxNumber(32).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).boxEyebrow(.white.opacity(0.8))
        }.frame(maxWidth: .infinity)
    }

    private func saveCheckpoint() {
        guard savedRecord == nil, controller.status != .ready else { return }
        if let execution = controller.execution { store.saveExecution(launch: controller.launch, execution: execution) }
        else if let pad = controller.pad { store.savePad(launch: controller.launch, state: pad) }
        else { store.saveCheckpoint(launch: controller.launch, checkpoint: controller.checkpoint()) }
        checkpointTime = controller.activeSeconds
    }
    private func saveRecord(feedback: String = "", effort: Int? = nil) {
        guard savedRecord == nil else { return }
        let record = controller.record(feedback: feedback, effort: effort)
        if store.record(record) { savedRecord = record; BoxHaptics.success() }
    }
}

private struct SessionSavedContent: View {
    let store: AppStore
    let record: SessionRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SessionCompleteBadge(title: "Rounds in the bank.", subtitle: "Saved to Progress")
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: record.guided?.title ?? record.pad?.configuration.title ?? String(localized: "Practice saved")).boxEyebrow(.white.opacity(0.85))
                    HStack(spacing: 0) {
                        stat(Duration.seconds(Int(record.workSeconds)).formatted(.time(pattern: .minuteSecond)), "Timed work")
                        Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                        if let summary = record.guided {
                            stat("\(summary.completed)", "Complete")
                            Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                            stat("\(summary.partial + summary.skipped)", "Partial/skipped")
                        } else {
                            stat(record.completedRounds.formatted(), "Full rounds")
                            Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                            stat(record.issuedCues.formatted(), "Cues")
                        }
                    }.fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
                .boxHero(padding: 18).boxEntrance(1)
                XPEarnedCard(store: store, sessionID: record.id).boxEntrance(2)
                CoachDebriefCard(store: store, recordID: record.id).boxEntrance(2)
                HStack(spacing: 10) {
                    BoxStatTile(label: "Streak", value: store.activityStreak().formatted(), unit: "days", symbol: "flame.fill", color: BoxStyle.strength)
                    BoxStatTile(label: "Last 7 days", value: store.activeDays().formatted(), unit: "active", symbol: "calendar", color: BoxStyle.accent)
                }
                .fixedSize(horizontal: false, vertical: true)
                .boxEntrance(2)
                if let id = record.assignmentID, let assignment = store.plan.first(where: { $0.id == id }) {
                    BoxInlineNotice(text: store.assignmentIsComplete(assignment) ? "Assignment completed." : "Partial work saved. This assignment remains unfinished.",
                                    symbol: store.assignmentIsComplete(assignment) ? "checkmark.circle.fill" : "circle.lefthalf.filled",
                                    color: store.assignmentIsComplete(assignment) ? BoxStyle.conditioning : BoxStyle.strength)
                    if let progress = store.assignmentProgress(assignment) { Text(progress).font(.caption).foregroundStyle(BoxStyle.muted) }
                }
                if let next = store.nextAssignment(after: record) {
                    Button { store.sessionFollowUp = .assignment(next.id); dismiss() } label: {
                        BoxRow(symbol: "calendar.badge.clock", title: next.displayTitle,
                               subtitle: String(localized: "Next planned · \(next.date.formatted(.dateTime.weekday().day().month()))"))
                            .boxPanel(padding: 0)
                    }.buttonStyle(BoxPressStyle()).accessibilityHint("Opens the next session")
                }
                PrimaryButton(title: "View Progress", symbol: "chart.bar.fill") { store.sessionFollowUp = .progress; dismiss() }
                    .padding(.top, 4)
                Button("Back to Today") { store.sessionFollowUp = .today; dismiss() }
                    .buttonStyle(BoxSecondaryStyle()).frame(maxWidth: .infinity)
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.conditioning)
        .foregroundStyle(BoxStyle.ink)
        .onAppear { BoxHaptics.success() }
    }
    private func stat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).boxNumber(30).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).boxEyebrow(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }
}

/// Green check that springs in, used on every completion screen.
struct SessionCompleteBadge: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(BoxStyle.conditioning)
                .frame(width: 80, height: 80)
                .background(BoxStyle.conditioning.opacity(0.14), in: .circle)
                .overlay { Circle().strokeBorder(BoxStyle.conditioning.opacity(0.4)) }
                .shadow(color: BoxStyle.conditioning.opacity(0.35), radius: 24)
                .scaleEffect(shown || reduceMotion ? 1 : 0.4)
                .opacity(shown || reduceMotion ? 1 : 0)
            Text(subtitle).boxEyebrow(BoxStyle.conditioning)
            Text(title).boxDisplay(46).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 12)
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { shown = true } }
        .accessibilityElement(children: .combine)
    }
}

/// Large glowing countdown ring readable from across the room.
struct BoxTimerDial: View {
    let remaining: String
    let fraction: Double
    var color: Color = BoxStyle.accent
    var label: LocalizedStringResource = "Remaining"
    var dimmed = false
    var size: CGFloat = 272
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: size * 0.6))
                .scaleEffect(1.25)
            BoxRing(progress: fraction, lineWidth: 12, color: color, track: .white.opacity(0.06), glow: true)
                .animation(.linear(duration: 0.2), value: fraction)
            VStack(spacing: 6) {
                Text(verbatim: remaining)
                    .boxNumber(92, relativeTo: .largeTitle, italic: true)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                Text(label).boxEyebrow()
            }
            .opacity(dimmed ? 0.55 : 1)
            .padding(28)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time remaining: \(remaining)"))
    }
}
