import SwiftUI
import AVKit

// MARK: - Analysis flow

/// Pick a segment, add context, analyse. Used for your own clips (coach review)
/// and for another boxer's footage (style study).
struct ClipAnalysisView: View {
    let store: AppStore
    let video: LocalVideo
    let purpose: ClipScanner.Purpose
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var length: Double = 20
    @State private var setting: ClipSetting = .shadowboxing
    @State private var focus = ""
    @State private var fighter = ""
    @State private var spotting = ""
    @State private var stage: Stage = .idle
    @State private var progress = 0.0
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var result: AIClipReport?
    enum Stage: Equatable { case idle, tracking, coaching }

    private var lengths: [Double] { purpose == .review ? [10, 20, 30] : [20, 40, 60] }
    private var end: Double { min(duration, start + length) }
    private var tint: Color { purpose == .review ? BoxStyle.coach : BoxStyle.strength }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let result {
                    SavedClipReportContent(store: store, report: result)
                } else {
                    preview.boxEntrance()
                    segment.boxEntrance(1)
                    context.boxEntrance(2)
                    if stage == .idle {
                        PrimaryButton(title: purpose == .review ? "Review this clip" : "Study this fighter", symbol: "sparkles", action: analyse)
                            .disabled(duration < 2)
                        Text(purpose == .review
                             ? "Your iPhone tracks every frame first. Only six short image strips and the measurements are sent for the coach's review. The video and audio stay on this phone."
                             : "Your iPhone tracks the footage first. Only seven short image strips and the measurements are sent for analysis. The video and audio stay on this phone.")
                            .font(.caption).foregroundStyle(BoxStyle.muted)
                    } else {
                        working
                    }
                    if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
                }
            }.boxPage()
        }
        .scrollDismissesKeyboard(.interactively)
        .boxScreen(tint: tint).foregroundStyle(BoxStyle.ink)
        .navigationTitle(purpose == .review ? "Coach review" : "Style study").navigationBarTitleDisplayMode(.inline)
        .task {
            setting = ClipSetting(kind: video.kind)
            let asset = AVURLAsset(url: store.videoURL(video))
            do {
                duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration > 0 else { duration = 0; error = String(localized: "This clip's length could not be read."); return }
                length = lengths.last { $0 <= duration } ?? lengths[0]
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { task?.cancel(); player?.pause() }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: stage)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: result?.id)
    }

    private var preview: some View {
        Group {
            if let player { VideoPlayer(player: player) } else { ProgressView().tint(tint) }
        }
        .frame(maxWidth: .infinity).frame(height: 260)
        .background(BoxStyle.surface)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(BoxStyle.borderStrong) }
    }

    private var segment: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BoxFeatureLabel(title: "Segment", symbol: "timeline.selection", color: tint)
                Spacer()
                Text(String(format: "%.1f–%.1f s", start, end)).boxNumber(16).foregroundStyle(BoxStyle.ink)
            }
            Slider(value: $start, in: 0...max(0.01, duration - min(length, duration))) { editing in
                if !editing { player?.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            }
            .tint(tint).disabled(duration <= length)
            HStack(spacing: 8) {
                ForEach(lengths, id: \.self) { value in
                    Button { length = value; start = min(start, max(0, duration - value)) } label: {
                        Text("\(Int(value)) s").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(length == value ? tint.opacity(0.25) : BoxStyle.surfaceRaised, in: .capsule)
                            .overlay { Capsule().strokeBorder(length == value ? tint : BoxStyle.border) }
                    }
                    .buttonStyle(BoxPressStyle()).disabled(value > duration + 0.5 && value != lengths[0])
                }
            }
            Text(purpose == .review ? "Pick the part with the most work in it. Whole body in frame works best." : "Pick a stretch with plenty of exchanges. Avoid replays and slow motion.")
                .font(.caption).foregroundStyle(BoxStyle.muted)
        }
        .boxPanel(padding: 16, tint: tint)
    }

    @ViewBuilder private var context: some View {
        VStack(alignment: .leading, spacing: 12) {
            if purpose == .review {
                Text("What kind of training?").boxEyebrow()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ClipSetting.allCases) { option in
                        Button { setting = option } label: {
                            Label(option.title, systemImage: option.symbol).font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(setting == option ? tint.opacity(0.25) : BoxStyle.surfaceRaised, in: .rect(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(setting == option ? tint : BoxStyle.border) }
                        }.buttonStyle(BoxPressStyle())
                    }
                }
                field("What should your coach look at? (optional)", text: $focus, prompt: "e.g. my guard when I throw hooks")
            } else {
                field("Fighter", text: $fighter, prompt: "e.g. Muhammad Ali")
                field("How to spot them (optional)", text: $spotting, prompt: "e.g. white trunks, starts on the left")
            }
        }
        .boxPanel(padding: 16)
    }

    private func field(_ label: LocalizedStringResource, text: Binding<String>, prompt: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).boxEyebrow()
            TextField(String(localized: prompt), text: text).font(.body)
                .padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 12, style: .continuous))
        }
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView().tint(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage == .tracking ? "Tracking movement on your iPhone" : (purpose == .review ? "Your coach is reviewing" : "Breaking down the style"))
                        .font(.headline)
                    Text(stage == .tracking ? "\(Int(progress * 100))% · free and private" : "Usually 10–30 seconds").font(.caption).foregroundStyle(BoxStyle.muted)
                }
                Spacer()
                Button("Cancel") { task?.cancel(); stage = .idle }.font(.subheadline.weight(.semibold))
            }
            BoxProgressTrack(value: stage == .tracking ? progress * 0.7 : 0.85, color: tint)
        }
        .boxPanel(padding: 16, tint: tint)
    }

    private func analyse() {
        guard QwenClient().isConfigured else { error = QwenError.notConfigured.localizedDescription; return }
        error = nil; progress = 0; stage = .tracking; player?.pause()
        let url = store.videoURL(video), from = start, to = end, purpose = purpose
        let stance: BoxMaxxingJudge.Stance = store.stance == "Southpaw" ? .southpaw : .orthodox
        let setting = setting, focus = focus, fighter = fighter, spotting = spotting
        let drills = ClipPrompts.drillMenu(ActivityCatalog.all)
        let profile = store.profileSummary, history = store.reviewHistoryText
        task = Task { @MainActor in
            do {
                let scan = try await ClipScanner.scan(url: url, start: from, end: to, stance: stance, purpose: purpose) { value in
                    Task { @MainActor in progress = value }
                }
                try Task.checkCancellation()
                stage = .coaching
                let model = QwenDeveloperConfiguration.visionModel
                switch purpose {
                case .review:
                    let prompt = ClipPrompts.review(setting: setting, focus: focus, profile: profile, history: history, evidence: scan.evidence, drills: drills)
                    var review = try await QwenClient().reviewClip(prompt: prompt, strips: scan.strips, start: from, end: to)
                    review.setting = setting; review.motion = scan.motion; review.segmentStart = from; review.segmentEnd = to
                    try Task.checkCancellation()
                    result = store.saveClipReview(video: video, review: review, model: model)
                case .style:
                    let prompt = ClipPrompts.style(fighter: fighter, description: spotting, evidence: scan.evidence, drills: drills)
                    var style = try await QwenClient().studyStyle(prompt: prompt, strips: scan.strips, start: from, end: to)
                    style.motion = scan.motion; style.segmentStart = from; style.segmentEnd = to
                    try Task.checkCancellation()
                    result = store.saveStyleStudy(video: video, style: style, model: model)
                }
                if result != nil { BoxHaptics.success() } else { error = store.storageNotice }
                stage = .idle
            } catch is CancellationError { stage = .idle }
            catch { if !Task.isCancelled { self.error = error.localizedDescription }; stage = .idle }
        }
    }
}

// MARK: - Saved reports

struct SavedAIReportView: View {
    let store: AppStore
    let report: AIClipReport
    var body: some View {
        ScrollView { SavedClipReportContent(store: store, report: report).boxPage() }
            .boxScreen(tint: report.kind == "style-1" ? BoxStyle.strength : BoxStyle.coach).foregroundStyle(BoxStyle.ink)
            .navigationTitle(report.kind == "style-1" ? "Style study" : "Coach review").navigationBarTitleDisplayMode(.inline)
    }
}

struct SavedClipReportContent: View {
    let store: AppStore
    let report: AIClipReport
    var body: some View {
        if let review = report.review { ClipReviewReport(store: store, review: review) }
        else if let style = report.style { FighterStyleReport(store: store, style: style) }
        else if let legacy = try? JSONDecoder().decode(VideoReviewDraft.self, from: report.payload) {
            LegacyReportContent(store: store, draft: legacy, start: report.startSeconds, end: report.endSeconds)
        } else {
            BoxInlineNotice(text: "This saved report could not be opened.", symbol: "exclamationmark.triangle", color: BoxStyle.accent)
        }
    }
}

// MARK: - Coach review report

struct ClipReviewReport: View {
    let store: AppStore
    let review: ClipReview
    @State private var notice: String?
    private var stance: BoxMaxxingJudge.Stance { store.stance == "Southpaw" ? .southpaw : .orthodox }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if review.isRejected {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "video.slash.fill").font(.title).foregroundStyle(BoxStyle.accent)
                    Text("Couldn't review this one").boxSection(24)
                    Text(review.rejectReason ?? "").font(.subheadline).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 18)
            } else {
                header
                if let scores = review.scores { ScoreCard(scores: scores, basis: review.scoreBasis) }
                if let motion = review.motion, motion.isUsable { MotionCard(motion: motion, stance: stance) }
                BoxSectionHeader(title: "Fix first")
                ForEach(Array(review.fixes.enumerated()), id: \.element.id) { index, fix in FixCard(store: store, index: index + 1, fix: fix) }
                if !review.strengths.isEmpty {
                    BoxSectionHeader(title: "Keep doing").padding(.top, 4)
                    ForEach(review.strengths) { point in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(BoxStyle.conditioning).font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(point.title).font(.headline); Spacer(); TimeTag(seconds: point.seconds) }
                                Text(point.detail).font(.subheadline).foregroundStyle(BoxStyle.muted)
                            }
                        }.boxPanel(padding: 14)
                    }
                }
                if !review.moments.isEmpty {
                    BoxSectionHeader(title: "Moments").padding(.top, 4)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(review.moments) { moment in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%.1f", moment.seconds)).boxNumber(15).foregroundStyle(moment.positive ? BoxStyle.conditioning : BoxStyle.accent).frame(width: 40, alignment: .leading)
                                Text(moment.text).font(.subheadline)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(BoxStyle.border).frame(height: 1) }
                        }
                    }.padding(.horizontal, 14).boxPanel(padding: 0)
                }
                if !review.unobservable.isEmpty {
                    DisclosureGroup("What the coach couldn't judge") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(review.unobservable, id: \.self) { Label($0, systemImage: "eye.slash").font(.footnote).foregroundStyle(BoxStyle.muted) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.font(.subheadline).boxPanel(padding: 14)
                }
                actions
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let setting = review.setting { BoxChip(text: "\(setting.title)", symbol: setting.symbol, color: BoxStyle.coach) }
                BoxChip(text: "\(review.confidence.capitalized) confidence", color: review.confidence == "high" ? BoxStyle.conditioning : review.confidence == "medium" ? BoxStyle.strength : BoxStyle.dim)
            }
            Text(review.headline).boxDisplay(34, relativeTo: .title).fixedSize(horizontal: false, vertical: true)
            Text(review.summary).font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
        .boxHero(padding: 18, ropes: false)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            PrimaryButton(title: "Practise these fixes", symbol: "figure.boxing", action: practise).disabled(review.drillIDs.isEmpty)
            Label("Your next program will include these fixes.", systemImage: "calendar.badge.checkmark").font(.caption).foregroundStyle(BoxStyle.muted)
            if let notice { BoxInlineNotice(text: "\(notice)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
        }.padding(.top, 6)
    }

    private func practise() {
        guard let session = FocusSession.build(title: String(localized: "Fix: \(review.fixes.first?.title ?? "Technique")"), drillIDs: review.drillIDs,
                                               equipment: store.activityEquipment, openSpace: store.hasOpenSpace, difficulty: store.activityDifficulty,
                                               budgetSeconds: max(10, store.profile.sessionMinutes) * 60) else {
            notice = String(localized: "These drills don't fit your level or equipment yet. Open them from the fix cards instead."); return
        }
        store.start(session)
    }
}

private struct TimeTag: View {
    let seconds: Double?
    var body: some View {
        if let seconds { Text(String(format: "%.1fs", seconds)).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(BoxStyle.coach)
            .padding(.horizontal, 7).padding(.vertical, 3).background(BoxStyle.coach.opacity(0.14), in: .capsule) }
    }
}

private struct ScoreCard: View {
    let scores: ClipReview.Scores
    let basis: String?
    @State private var shown = false
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                BoxRing(progress: shown ? Double(scores.overall) / 100 : 0, lineWidth: 9, color: BoxStyle.coach)
                VStack(spacing: 0) {
                    Text("\(scores.overall)").boxNumber(34, italic: true)
                    Text("Overall").boxEyebrow()
                }
            }.frame(width: 104, height: 104)
            VStack(spacing: 8) {
                bar("Offense", scores.offense); bar("Defense", scores.defense); bar("Footwork", scores.footwork); bar("Guard", scores.guardScore)
            }
        }
        .padding(.bottom, 10)
        .boxPanel(padding: 16, tint: BoxStyle.coach)
        .overlay(alignment: .bottomTrailing) {
            Text("Coach estimate, not a measurement").font(.system(size: 9, weight: .semibold)).foregroundStyle(BoxStyle.dim).padding(.trailing, 14).padding(.bottom, 8)
        }
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) { shown = true } }
        .accessibilityElement(children: .combine)
    }
    private func bar(_ title: LocalizedStringResource, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title).font(.caption.weight(.semibold)); Spacer(); Text("\(value)").font(.caption.monospacedDigit().weight(.bold)) }
            BoxProgressTrack(value: shown ? Double(value) / 100 : 0, color: value >= 70 ? BoxStyle.conditioning : value >= 50 ? BoxStyle.strength : BoxStyle.accent, height: 5)
        }
    }
}

/// What the iPhone measured itself, kept visibly separate from the coach's opinion.
struct MotionCard: View {
    let motion: ClipMotion
    let stance: BoxMaxxingJudge.Stance
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BoxFeatureLabel(title: "Measured on your iPhone", symbol: "figure.boxing", color: BoxStyle.accent)
                Spacer()
                Text("\(Int(motion.trackedShare * 100))% tracked").font(.caption).foregroundStyle(BoxStyle.muted)
            }
            HStack(spacing: 8) {
                stat("\(motion.punches.count)", "Punches")
                stat(motion.punchesPerMinute.map { "\(Int($0.rounded()))" } ?? "–", "Per min")
                stat(motion.guardShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "Guard up")
                stat("\(motion.defenses.count)", "Dodges")
            }
            if !motion.moves.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(motion.counts(stance: stance), id: \.0) { BoxChip(text: "\($0.0) ×\($0.1)") }
                    }
                }
            }
            if let low = motion.otherHandLowShare, low > 0.2 {
                Label("Other hand dropped on \(Int((low * 100).rounded()))% of punches", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.strength)
            }
            Text("Camera estimates from one angle. They can miss or misread fast moves.").font(.caption2).foregroundStyle(BoxStyle.dim)
        }
        .boxPanel(padding: 16)
    }
    private func stat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).boxNumber(22)
            Text(label).boxEyebrow()
        }.frame(maxWidth: .infinity).padding(.vertical, 10).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 12))
    }
}

private struct FixCard: View {
    let store: AppStore
    let index: Int
    let fix: ClipReview.Fix
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index)").boxNumber(26, italic: true).foregroundStyle(BoxStyle.accent)
                Text(fix.title).font(.headline)
                Spacer()
                TimeTag(seconds: fix.seconds)
            }
            Text(fix.why).font(.subheadline).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
            Label(fix.cue, systemImage: "quote.opening").font(.subheadline.weight(.bold)).foregroundStyle(BoxStyle.ink)
                .padding(.horizontal, 12).padding(.vertical, 8).background(BoxStyle.accent.opacity(0.16), in: .capsule)
            if let id = fix.drillID, let drill = ActivityCatalog.find(id) {
                NavigationLink { ActivityDetailView(store: store, activity: drill) } label: {
                    BoxRow(symbol: "figure.boxing", color: BoxStyle.accent, title: drill.title, subtitle: String(localized: "Drill for this fix"))
                        .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14))
                }.buttonStyle(BoxPressStyle())
            }
        }
        .boxPanel(padding: 16)
        .overlay(alignment: .leading) { Capsule().fill(BoxStyle.accent).frame(width: 3).padding(.vertical, 18) }
    }
}

// MARK: - Fighter style report

struct FighterStyleReport: View {
    let store: AppStore
    let style: FighterStyle
    @State private var building = false
    @State private var sparring: SparringConfiguration?
    @State private var notice: String?
    private var stance: BoxMaxxingJudge.Stance { store.stance == "Southpaw" ? .southpaw : .orthodox }
    private var isActive: Bool { store.styleFocus?.fighter == style.fighter }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if style.isRejected {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "video.slash.fill").font(.title).foregroundStyle(BoxStyle.accent)
                    Text("Couldn't study this footage").boxSection(24)
                    Text(style.rejectReason ?? "").font(.subheadline).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 18)
            } else {
                hero
                emphasis
                BoxSectionHeader(title: "How they fight")
                ForEach(style.traits) { trait in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(trait.title).font(.headline)
                            Spacer()
                            if trait.source == "clip", let s = trait.seconds { TimeTag(seconds: s) }
                            else { BoxChip(text: trait.source == "clip" ? "In the clip" : "Known style", color: BoxStyle.dim) }
                        }
                        Text(trait.detail).font(.subheadline).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }.boxPanel(padding: 14)
                }
                if !style.signatureCombos.isEmpty {
                    BoxSectionHeader(title: "Signature combinations").padding(.top, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(style.signatureCombos.enumerated()), id: \.offset) { _, combo in
                            HStack(spacing: 6) {
                                ForEach(Array(combo.enumerated()), id: \.offset) { i, token in
                                    if i > 0 { Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(BoxStyle.dim) }
                                    Text(FighterStyle.action(token, stance: stance)?.shortTitle(stance: stance) ?? token)
                                        .font(.caption.weight(.heavy)).padding(.horizontal, 9).padding(.vertical, 6)
                                        .background(BoxStyle.strength.opacity(0.18), in: .capsule)
                                }
                            }
                        }
                        Text("Shown for your \(stance == .orthodox ? "orthodox" : "southpaw") stance.").font(.caption2).foregroundStyle(BoxStyle.dim)
                    }.boxPanel(padding: 14)
                }
                BoxSectionHeader(title: "Drills to build it").padding(.top, 4)
                BoxRowGroup {
                    ForEach(style.drillIDs.compactMap(ActivityCatalog.find)) { drill in
                        NavigationLink { ActivityDetailView(store: store, activity: drill) } label: {
                            BoxRow(symbol: "figure.boxing", color: BoxStyle.strength, title: drill.title, subtitle: drill.objective)
                        }.buttonStyle(BoxPressStyle(scale: 0.985))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    if !style.conditioning.isEmpty { Label(style.conditioning, systemImage: "heart.fill").font(.subheadline) }
                    if !style.fuelNote.isEmpty { Label(style.fuelNote, systemImage: "fork.knife").font(.subheadline) }
                }.foregroundStyle(BoxStyle.ink).frame(maxWidth: .infinity, alignment: .leading).boxPanel(padding: 14)
                if !style.caution.isEmpty { BoxInlineNotice(text: "\(style.caution)", symbol: "exclamationmark.shield.fill", color: BoxStyle.strength) }
                actions
            }
        }
        .sheet(isPresented: $building) { NavigationStack { ProgramBuilderView(store: store) }.preferredColorScheme(.dark).tint(BoxStyle.accent) }
        .fullScreenCover(item: Binding(get: { sparring.map(IdentifiedConfiguration.init) }, set: { sparring = $0?.configuration })) { item in
            SparringArenaView(store: store, configuration: item.configuration).preferredColorScheme(.dark)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                BoxChip(text: "\(style.archetype)", symbol: "person.fill.viewfinder", onHero: true)
                if style.stance != "unclear" { BoxChip(text: "\(style.stance.capitalized)", onHero: true) }
                if isActive { BoxChip(text: "Your style focus", symbol: "scope", onHero: true) }
            }
            Text(style.fighter).boxDisplay(42, relativeTo: .largeTitle).fixedSize(horizontal: false, vertical: true)
            Text(style.summary).font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
        .boxHero(padding: 18)
    }

    private var emphasis: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style emphasis").boxEyebrow()
            ForEach(style.emphasis.ranked.sorted { $0.1 > $1.1 }, id: \.0) { item in
                HStack(spacing: 10) {
                    Text(item.0).font(.caption.weight(.semibold)).frame(width: 104, alignment: .leading)
                    BoxProgressTrack(value: Double(item.1) / 100, color: item.1 >= 75 ? BoxStyle.strength : BoxStyle.dim, height: 6)
                }
            }
            Text("How central each element is to this style, not how good the fighter is.").font(.caption2).foregroundStyle(BoxStyle.dim)
        }.boxPanel(padding: 16, tint: BoxStyle.strength)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            PrimaryButton(title: "Build my program in this style", symbol: "sparkles") {
                store.styleFocus = style.planFocus; building = true
            }
            HStack(spacing: 8) {
                Button {
                    if let config = style.sparringConfiguration(userStance: stance) { sparring = config }
                    else { notice = String(localized: "No combinations to spar yet.") }
                } label: { Label("Spar like \(style.fighter)", systemImage: "flame.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxSecondaryStyle()).disabled(style.signatureCombos.isEmpty)
                Button(action: practise) { Label("Practise drills", systemImage: "figure.boxing").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxSecondaryStyle())
            }
            if isActive {
                Button("Stop training toward this style") { store.styleFocus = nil }.font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.muted)
            }
            if let notice { BoxInlineNotice(text: "\(notice)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
        }.padding(.top, 6)
    }

    private func practise() {
        guard let session = FocusSession.build(title: String(localized: "\(style.fighter) style"), drillIDs: style.drillIDs, equipment: store.activityEquipment,
                                               openSpace: store.hasOpenSpace, difficulty: store.activityDifficulty, budgetSeconds: max(10, store.profile.sessionMinutes) * 60) else {
            notice = String(localized: "These drills don't fit your level or equipment yet."); return
        }
        store.start(session)
    }
}

private struct IdentifiedConfiguration: Identifiable {
    let configuration: SparringConfiguration
    var id: String { configuration.drillTitle ?? "style" }
}

// MARK: - Legacy frame reports (saved before review-2)

private struct LegacyReportContent: View {
    let store: AppStore
    let draft: VideoReviewDraft
    let start: Double
    let end: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BoxChip(text: "Earlier frame review", symbol: "sparkles", color: BoxStyle.coach)
            Text(draft.summary).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(draft.observations) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(item.observation).font(.headline); Spacer(); TimeTag(seconds: item.seconds) }
                    Text(item.suggestion).font(.subheadline)
                    Text(item.uncertainty).font(.footnote).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 14)
            }
        }
    }
}
