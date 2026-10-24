import SwiftUI

struct GuidedPlayerContent: View {
    let controller: SessionController
    let save: (String) -> Void
    let discard: () -> Void
    let checkpoint: () -> Void
    let stance: BoxMaxxingJudge.Stance
    let level: PadLevel
    let stanceKnown: Bool
    @State private var actualReps = 0
    @State private var feedback = ""
    @State private var selectedStance: BoxMaxxingJudge.Stance?
    private var cameraStance: BoxMaxxingJudge.Stance? { selectedStance ?? controller.execution?.preferredCameraStance ?? (stanceKnown ? stance : nil) }
    var body: some View {
        if let execution = controller.execution {
            VStack(alignment: .leading, spacing: 16) {
                if execution.phase == .briefing {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Before you begin", systemImage: "list.bullet.rectangle").boxEyebrow(.white.opacity(0.85))
                        Text(execution.session.title).boxDisplay(40, relativeTo: .title).padding(.top, 10)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            BoxValueChip(text: String(localized: "\(execution.session.activities.count) activities"), onHero: true)
                            BoxValueChip(text: Duration.seconds(execution.session.estimatedSeconds).formatted(.time(pattern: .minuteSecond)) + " min", onHero: true)
                        }.padding(.top, 14)
                    }.boxHero().boxEntrance()
                    SessionBriefing(session: execution.session).boxEntrance(1)
                    DevelopmentNote(text: "Original instructions pending coach review. No demonstration media is available. Guided blocks use timers and your check-ins; camera blocks use experimental recognition. Setup and feedback are outside the work/rest estimate.")
                    PrimaryButton(title: "Begin session") { controller.begin(); checkpoint() }
                } else if execution.phase == .recap {
                    let summary = GuidedSummary(execution: execution)
                    SessionCompleteBadge(title: execution.endedEarly ? "You called time." : "Session reviewed.", subtitle: "Check your work")
                    HStack(spacing: 0) {
                        recapStat(summary.completed, "Complete", BoxStyle.conditioning)
                        Rectangle().fill(BoxStyle.border).frame(width: 1)
                        recapStat(summary.partial, "Partial", BoxStyle.strength)
                        Rectangle().fill(BoxStyle.border).frame(width: 1)
                        recapStat(summary.skipped, "Skipped", BoxStyle.muted)
                    }.fixedSize(horizontal: false, vertical: true).boxPanel(padding: 0)
                    ForEach(Array(execution.session.activities.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(ActivityCatalog.find(item.activityID)?.title ?? item.activityID).font(.headline)
                                Spacer()
                                OutcomeChip(raw: execution.outcome(at: index).rawValue)
                            }
                            Text("\(execution.results[index].confirmedSets)/\(item.sets) full sets · \(execution.results[index].guidedCheckIns ?? execution.results[index].attemptedSets) guided check-ins · \(Int(execution.results[index].timedSeconds)) sec timed")
                                .font(.caption).foregroundStyle(BoxStyle.muted)
                            if item.reps > 0 { Text("\(execution.results[index].confirmedReps) reps\(ActivityCatalog.find(item.activityID)?.repsPerSide == true ? " per side" : "") confirmed by you").font(.caption).foregroundStyle(BoxStyle.muted) }
                            CameraBlockResults(result: execution.results[index])
                        }.frame(maxWidth: .infinity, alignment: .leading).boxPanel()
                    }
                    DevelopmentNote(text: "Guided sets use your check-ins. Camera sets record actual timed work and experimental observations separately. Finishing time does not certify successful punches or technique.")
                    TextField("How did it feel? Feedback for your next plan…", text: $feedback, axis: .vertical)
                        .lineLimit(3...6).padding(16)
                        .background(BoxStyle.surface, in: .rect(cornerRadius: 18, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(BoxStyle.border) }
                    PrimaryButton(title: "Save to Progress", symbol: "checkmark") { save(feedback) }
                    Button("Discard session", role: .destructive, action: discard)
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                } else if let item = execution.current, let activity = ActivityCatalog.find(item.activityID) {
                    activityHeader(execution: execution, item: item, activity: activity)
                    if execution.paused {
                        if execution.phase == .work || execution.phase == .rest {
                            BoxTimerDial(remaining: Duration.seconds(Int(ceil(execution.remaining))).formatted(.time(pattern: .minuteSecond)),
                                         fraction: fraction(execution, item), color: BoxStyle.strength, label: "Paused", dimmed: true, size: 230)
                                .frame(maxWidth: .infinity)
                        } else {
                            BoxInlineNotice(text: "Paused", symbol: "pause.circle.fill", color: BoxStyle.strength)
                        }
                        PrimaryButton(title: "Resume session") { controller.resume(); checkpoint() }
                    } else {
                        switch execution.phase {
                        case .instruction:
                            if item.supportsCameraChoice {
                                BoxSegmented(options: [TrainingMode.shadowboxing, .camera],
                                             selection: Binding(get: { execution.currentMode == .camera ? .camera : .shadowboxing }, set: { controller.chooseMode($0); checkpoint() }),
                                             title: { $0 == .camera ? "Camera · beta" : "Guided" },
                                             symbol: { $0 == .camera ? "camera.viewfinder" : "waveform" })
                                Text(execution.currentMode == .camera ? "Noncontact camera rounds. Work/rest stay as prescribed. Jab/cross are cued one at a time with resets; camera setup and feedback can extend elapsed time. Accuracy varies by phone and framing." : "Guided shadowboxing uses the same work/rest prescription and your own completion check-in. Camera measurements are not produced.")
                                    .font(.footnote).foregroundStyle(BoxStyle.muted)
                                if execution.currentMode == .camera {
                                    Picker("Stance for camera", selection: Binding(get: { cameraStance }, set: { selectedStance = $0 })) {
                                        Text("Choose stance").tag(Optional<BoxMaxxingJudge.Stance>.none)
                                        Text("Orthodox · left lead").tag(Optional(BoxMaxxingJudge.Stance.orthodox))
                                        Text("Southpaw · right lead").tag(Optional(BoxMaxxingJudge.Stance.southpaw))
                                    }
                                    .tint(BoxStyle.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .boxPanel(padding: 8)
                                }
                            }
                            ActivityInstructions(activity: activity, mode: execution.currentMode)
                            PrimaryButton(title: execution.currentMode == .camera ? "Set up camera for this set" : "Start this set",
                                          symbol: execution.currentMode == .camera ? "camera.fill" : "play.fill") { controller.startActivity(stance: cameraStance ?? stance, level: level); checkpoint() }
                                .disabled(execution.currentMode == .camera && cameraStance == nil)
                        case .work, .rest:
                            let resting = execution.phase == .rest
                            VStack(spacing: 14) {
                                Text(resting ? "Breathe & reset" : "Your set").boxEyebrow(resting ? BoxStyle.timer : BoxStyle.accent)
                                BoxTimerDial(remaining: Duration.seconds(Int(ceil(execution.remaining))).formatted(.time(pattern: .minuteSecond)),
                                             fraction: fraction(execution, item), color: resting ? BoxStyle.timer : BoxStyle.accent, size: 240)
                                if item.reps > 0 && !resting {
                                    BoxChip(text: "\(item.reps) reps\(activity.repsPerSide ? " each side" : "") · Time allowance", color: BoxStyle.accent)
                                }
                                Text(resting ? "Next: \(activity.title), set \(execution.set)." : activity.cues.joined(separator: " "))
                                    .font(.subheadline.weight(resting ? .regular : .semibold))
                                    .foregroundStyle(resting ? BoxStyle.muted : BoxStyle.ink)
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity)
                            HStack(spacing: 10) {
                                Button { controller.pause(); checkpoint() } label: {
                                    Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                                }.buttonStyle(BoxSecondaryStyle())
                                if !resting {
                                    Button { controller.finishActivitySet(); checkpoint() } label: {
                                        Label("Finish set", systemImage: "checkmark").frame(maxWidth: .infinity)
                                    }.buttonStyle(BoxPrimaryStyle(height: 46))
                                }
                            }
                            DisclosureGroup("Instructions") { ActivityInstructions(activity: activity, mode: execution.currentMode).padding(.top, 8) }
                                .font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
                        case .confirmation:
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Check in before moving on.").boxSection(24)
                                Text(item.reps > 0 ? "How many reps did you complete?" : "Confirm the work you did. A shortened set is recorded as partial.")
                                    .font(.subheadline).foregroundStyle(BoxStyle.muted)
                                if item.reps > 0 {
                                    RepCounter(value: $actualReps, maximum: item.reps, label: activity.repsPerSide ? "Reps on each side" : "Reps completed")
                                }
                            }.boxPanel(padding: 18)
                            PrimaryButton(title: "Confirm set", symbol: "checkmark") { controller.confirmActivity(reps: item.reps > 0 ? actualReps : nil); BoxHaptics.success(); checkpoint() }
                        default: EmptyView()
                        }
                    }
                    Button("Skip this activity") { controller.skip(); checkpoint() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    if let reason = controller.pauseReason { Text(reason).font(.footnote).foregroundStyle(BoxStyle.muted) }
                }
                if let notice = controller.audioNotice { BoxInlineNotice(text: notice) }
            }.foregroundStyle(BoxStyle.ink)
                .onChange(of: execution.phase) { _, phase in
                    if phase == .confirmation { actualReps = 0 }
                    checkpoint()
                }
        }
    }

    private func fraction(_ execution: GuidedExecution, _ item: ActivityPrescription) -> Double {
        let total = Double(execution.phase == .rest ? item.restSeconds : item.workSeconds)
        return total > 0 ? execution.remaining / total : 0
    }

    private func recapStat(_ value: Int, _ label: LocalizedStringResource, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .number).boxNumber(30).foregroundStyle(color)
            Text(label).boxEyebrow()
        }.frame(maxWidth: .infinity).padding(.vertical, 14)
    }

    @ViewBuilder private func activityHeader(execution: GuidedExecution, item: ActivityPrescription, activity: CatalogActivity) -> some View {
        let count = execution.session.activities.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule().fill(index < execution.index ? BoxStyle.conditioning : index == execution.index ? BoxStyle.accent : .white.opacity(0.12))
                        .frame(height: 4)
                }
            }.accessibilityHidden(true)
            Text("Activity \(execution.index + 1) of \(count) · Set \(execution.set) of \(item.sets)").boxEyebrow(BoxStyle.accent)
            Text(activity.title).boxDisplay(38, relativeTo: .title).fixedSize(horizontal: false, vertical: true)
            Text(PrescriptionText.describe(item)).font(.footnote).foregroundStyle(BoxStyle.muted)
        }
    }
}

/// Big tap targets for counting reps after a set.
private struct RepCounter: View {
    @Binding var value: Int
    let maximum: Int
    let label: LocalizedStringResource
    var body: some View {
        HStack {
            Button { if value > 0 { value -= 1; BoxHaptics.selection() } } label: {
                Image(systemName: "minus").font(.system(size: 18, weight: .bold)).frame(width: 52, height: 52)
                    .background(BoxStyle.surfaceRaised, in: .circle).overlay { Circle().strokeBorder(BoxStyle.borderStrong) }
            }.buttonStyle(BoxPressStyle(scale: 0.9)).disabled(value == 0).accessibilityLabel("Fewer reps")
            Spacer()
            VStack(spacing: 2) {
                Text(value, format: .number).boxNumber(52, relativeTo: .largeTitle).contentTransition(.numericText(value: Double(value)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
                Text(label).boxEyebrow()
            }
            Spacer()
            Button { if value < maximum { value += 1; BoxHaptics.selection() } } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .bold)).frame(width: 52, height: 52)
                    .foregroundStyle(.white)
                    .background(BoxStyle.redGradient, in: .circle)
            }.buttonStyle(BoxPressStyle(scale: 0.9)).disabled(value >= maximum).accessibilityLabel("More reps")
        }
        .foregroundStyle(BoxStyle.ink)
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text("\(value) of \(maximum)"))
    }
}

struct SessionBriefing: View {
    let session: GuidedSession
    var embedded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if embedded {
                Text(session.title).font(.title3.bold())
            }
            HStack(spacing: 6) {
                BoxChip(text: session.equipment.isEmpty ? "No equipment" : "\(session.equipment.joined(separator: " · "))", symbol: "bag")
                if session.activities.isEmpty { BoxChip(text: "Rest day", symbol: "moon.fill", color: BoxStyle.timer) }
            }
            if session.activities.isEmpty {
                Text("Rest day · No guided activities scheduled").font(.subheadline).foregroundStyle(BoxStyle.muted)
            } else {
                BoxRowGroup {
                    ForEach(Array(session.activities.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").boxNumber(16).foregroundStyle(BoxStyle.accent)
                                .frame(width: 34, height: 34)
                                .background(BoxStyle.accent.opacity(0.14), in: .circle)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ActivityCatalog.find(item.activityID)?.title ?? item.activityID).font(.subheadline.weight(.semibold))
                                Text("\(PrescriptionText.describe(item)) · \(item.mode.title)").font(.caption).foregroundStyle(BoxStyle.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("\(Duration.seconds(session.estimatedSeconds).formatted(.time(pattern: .minuteSecond))) planned work & rest · Instructions at your pace")
                    .font(.caption).foregroundStyle(BoxStyle.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityInstructions: View {
    let activity: CatalogActivity
    var mode: TrainingMode = .guided
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BoxFeatureLabel(title: "How to practise", symbol: "figure.boxing")
            Text(activity.objective).font(.headline)
            Text(activity.setup(for: mode)).font(.subheadline).foregroundStyle(BoxStyle.muted)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(activity.instructions.enumerated()), id: \.element) { index, text in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").boxNumber(14).foregroundStyle(BoxStyle.accent).frame(width: 26, height: 26)
                            .background(BoxStyle.accent.opacity(0.14), in: .circle).accessibilityHidden(true)
                        Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityElement(children: .combine).accessibilityLabel("Step \(index + 1). \(text)")
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "megaphone.fill").foregroundStyle(BoxStyle.strength)
                Text(activity.cues.joined(separator: " ")).font(.subheadline.weight(.semibold))
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(BoxStyle.strength.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
            DisclosureGroup("Common mistakes") {
                Text(activity.mistakes.joined(separator: "; ")).font(.subheadline).foregroundStyle(BoxStyle.muted).padding(.top, 6)
            }.font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).boxPanel(padding: 18)
    }
}

enum PrescriptionText {
    static func describe(_ item: ActivityPrescription) -> String {
        "\(item.sets) \(item.sets == 1 ? "set / round" : "sets / rounds") · " + (item.reps > 0 ? "\(item.reps) reps\(ActivityCatalog.find(item.activityID)?.repsPerSide == true ? " per side" : "") · \(item.workSeconds)s allowance" : "\(item.workSeconds)s work") + (item.sets > 1 ? " · \(item.restSeconds)s rest" : "") + " · " + (item.effectiveDifficulty == .beginner ? "Foundation" : "Intermediate")
    }
}

struct CameraBlockResults: View {
    let result: GuidedExecution.ActivityResult
    var body: some View {
        if let sets = result.cameraSets, !sets.isEmpty {
            ForEach(sets) { set in
                DisclosureGroup("Camera · set \(set.set)\(set.continuedGuided ? " · continued guided" : "")") {
                    PadResultSummary(state: set.state)
                }.font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
            }
        }
    }
}
