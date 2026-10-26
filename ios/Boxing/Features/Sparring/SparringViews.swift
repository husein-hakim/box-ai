import SwiftUI

// MARK: - Setup

struct SparringSetupView: View {
    let store: AppStore
    @State private var configuration = SparringConfiguration()
    @State private var acknowledged = false
    @State private var launch: SparringConfiguration?
    @State private var locked: RankUnlock?
    var body: some View {
        let unlocks = store.unlocks
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Label("Camera · Sparring", systemImage: "flame.fill").boxEyebrow(.white.opacity(0.85))
                        Spacer()
                        BoxChip(text: "Beta", onHero: true)
                    }
                    Text("Fight\nthe pads.").boxDisplay(48, relativeTo: .title).padding(.top, 10)
                    Text("Jabs, crosses, hooks, uppercuts, slips and ducks, coming at you fast. Stay on beat, stack your streak.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        BoxChip(text: "Best \(UserDefaults.standard.integer(forKey: SparringSession.highScoreKey(configuration.difficulty)))", symbol: "trophy.fill", onHero: true)
                        BoxValueChip(text: String(localized: "\(configuration.rounds) × \(configuration.roundSeconds)s"), onHero: true)
                    }.padding(.top, 14)
                }.boxHero().boxEntrance()

                VStack(alignment: .leading, spacing: 14) {
                    DifficultyPicker(selection: $configuration.difficulty, unlocks: unlocks) { locked = $0 }
                    Text(difficultyBlurb).font(.footnote).foregroundStyle(BoxStyle.muted)
                    HStack {
                        Text("Rounds").font(.subheadline).foregroundStyle(BoxStyle.muted)
                        Spacer()
                        Stepper(value: $configuration.rounds, in: 1...unlocks.maxRounds) { Text("\(configuration.rounds)").boxNumber(22) }.fixedSize()
                    }
                    Picker("Round length", selection: $configuration.roundSeconds) {
                        ForEach(unlocks.roundSeconds, id: \.self) { Text($0 < 60 ? "\($0) sec" : "\($0 / 60) min").tag($0) }
                    }.tint(BoxStyle.ink).font(.subheadline)
                    if unlocks.proCombos {
                        Toggle(isOn: Binding(get: { configuration.proCombos == true }, set: { configuration.proCombos = $0 ? true : nil })) {
                            Label("Pro combinations", systemImage: "medal.fill").font(.subheadline)
                        }.tint(BoxStyle.strength)
                    }
                    if unlocks.suddenDeath {
                        Toggle(isOn: Binding(get: { configuration.suddenDeath == true }, set: { configuration.suddenDeath = $0 ? true : nil })) {
                            Label("Sudden death (one life)", systemImage: "heart.slash.fill").font(.subheadline)
                        }.tint(BoxStyle.accent)
                    }
                    if let next = unlocks.next {
                        Label("Next unlock: \(next.title) at \(next.rank.title) (level \(next.minimumLevel))", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(BoxStyle.dim)
                    }
                }.boxPanel(padding: 18).boxEntrance(1)

                BoxSectionHeader(title: "Moves in the mix") { Text("\(configuration.kinds.count) of 5") }.padding(.top, 6)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(FightAction.Kind.allCases, id: \.self) { kind in
                        let on = configuration.kinds.contains(kind)
                        Button {
                            if on { if configuration.kinds.count > 1 { configuration.kinds.remove(kind) } } else { configuration.kinds.insert(kind) }
                            BoxHaptics.selection()
                        } label: {
                            HStack {
                                Image(systemName: SparringStyle.symbol(kind)).font(.system(size: 15, weight: .bold)).foregroundStyle(SparringStyle.color(kind))
                                Text(SparringStyle.title(kind)).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? SparringStyle.color(kind) : BoxStyle.dim)
                            }
                            .foregroundStyle(BoxStyle.ink).padding(.horizontal, 14).frame(minHeight: 50)
                            .background(BoxStyle.surface, in: .rect(cornerRadius: 16, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? SparringStyle.color(kind).opacity(0.5) : BoxStyle.border) }
                        }
                        .buttonStyle(BoxPressStyle(scale: 0.95))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }.boxEntrance(2)

                Button { acknowledged.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: acknowledged ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(acknowledged ? BoxStyle.conditioning : BoxStyle.dim).contentTransition(.symbolEffect(.replace))
                        Text("Noncontact only. My phone is propped about 2 m away, out of reach, with room around me to move.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.contentShape(.rect)
                }.buttonStyle(.plain).padding(.top, 6)

                PrimaryButton(title: "Fight", symbol: "flame.fill") {
                    var c = RankUnlocks.clamp(configuration, to: unlocks); c.goldTargets = unlocks.goldTargets ? true : nil; c.mode = .arcade; c.stance = store.stance == "Southpaw" ? .southpaw : .orthodox; launch = c
                }.disabled(!acknowledged || !configuration.isValid)
                Button {
                    var c = configuration; c.mode = .check; c.rounds = 1; c.stance = store.stance == "Southpaw" ? .southpaw : .orthodox; launch = c
                } label: { Label("Detection check", systemImage: "checklist").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxSecondaryStyle()).disabled(!acknowledged)
                Text("Detection check calls each move four times, slowly, and shows exactly what the camera recognised, so you can see how reliable each move is on your phone.")
                    .font(.caption).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Sparring").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .fullScreenCover(item: $launch) { configuration in
            SparringArenaView(store: store, configuration: configuration)
        }
        .onAppear { configuration = RankUnlocks.clamp(configuration, to: store.unlocks) }
        .alert(locked.map { "\($0.title) is locked" } ?? "", isPresented: Binding(get: { locked != nil }, set: { if !$0 { locked = nil } })) {
            Button("OK") { locked = nil }
        } message: {
            if let locked { Text("Reach \(locked.rank.title) (level \(locked.minimumLevel))\(locked.challenge.map { ", \($0.text)" } ?? "").") }
        }
    }
    private var difficultyBlurb: String {
        switch configuration.difficulty {
        case .rookie: String(localized: "Single moves and short combos, generous timing, 5 lives.")
        case .contender: String(localized: "Real combinations at a steady pace, 4 lives.")
        case .champion: String(localized: "Long, fast combinations and tight timing, 3 lives.")
        case .undisputed: String(localized: "The fastest targets and tightest windows in BOX, 3 lives.")
        }
    }
}

/// Difficulty choice with locked levels shown, tappable to explain how to unlock them.
private struct DifficultyPicker: View {
    @Binding var selection: SparringConfiguration.Difficulty
    let unlocks: UnlockState
    let showLocked: (RankUnlock) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(SparringConfiguration.Difficulty.allCases, id: \.self) { d in
                let open = unlocks.allows(d)
                Button {
                    if open { selection = d; BoxHaptics.selection() }
                    else if let u = RankUnlocks.all.first(where: { $0.kind == .difficulty(d) }) { showLocked(u) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: open ? (selection == d ? "flame.fill" : "flame") : "lock.fill").font(.system(size: 13, weight: .bold))
                        Text(d.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .foregroundStyle(open ? (selection == d ? .white : BoxStyle.ink) : BoxStyle.dim)
                    .background(selection == d ? AnyShapeStyle(BoxStyle.redGradient) : AnyShapeStyle(BoxStyle.surfaceRaised), in: .rect(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BoxStyle.border) }
                }
                .buttonStyle(BoxPressStyle(scale: 0.95))
                .accessibilityLabel(Text(open ? d.title : "\(d.title), locked"))
            }
        }
    }
}

extension SparringConfiguration: Identifiable { var id: String { "\(difficulty.rawValue)-\(mode.rawValue)-\(rounds)-\(roundSeconds)" } }

enum SparringStyle {
    static func color(_ kind: FightAction.Kind) -> Color {
        switch kind {
        case .straight: BoxStyle.accent
        case .hook: BoxStyle.strength
        case .uppercut: BoxStyle.coach
        case .slip, .duck: BoxStyle.timer
        }
    }
    static func symbol(_ kind: FightAction.Kind) -> String {
        switch kind {
        case .straight: "arrow.up.forward"
        case .hook: "arrow.turn.up.left"
        case .uppercut: "arrow.up"
        case .slip: "arrow.left.and.right"
        case .duck: "arrow.down"
        }
    }
    static func title(_ kind: FightAction.Kind) -> String {
        switch kind {
        case .straight: String(localized: "Jab & cross")
        case .hook: String(localized: "Hooks")
        case .uppercut: String(localized: "Uppercuts")
        case .slip: String(localized: "Slips")
        case .duck: String(localized: "Ducks")
        }
    }
    static func gradeColor(_ grade: SparringGrade) -> Color {
        switch grade {
        case .perfect: BoxStyle.strength
        case .great: BoxStyle.conditioning
        case .good: BoxStyle.timer
        case .miss, .wrong: BoxStyle.accent
        }
    }
}

// MARK: - Arena

struct SparringArenaView: View {
    let store: AppStore?
    /// When set (a drill inside a guided session), results go back to the caller
    /// instead of being saved as a separate practice.
    var onFinish: ((SparringSummary) -> Void)? = nil
    @State private var session: SparringSession
    @State private var saved = false
    @State private var newRecord = false
    @State private var savedID: UUID?
    @Environment(\.dismiss) private var dismiss
    init(store: AppStore?, configuration: SparringConfiguration, demo: Bool = false, onFinish: ((SparringSummary) -> Void)? = nil) {
        self.store = store; self.onFinish = onFinish
        let session = SparringSession(configuration: configuration)
        #if DEBUG
        session.debugAutoplay = demo
        #endif
        _session = State(initialValue: session)
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PadMirroredPreview(session: session.camera.engine.session, imageSize: session.camera.imageSize, rotationDegrees: session.camera.rotationDegrees)
                .ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { session.setViewport($0) }
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).frame(height: 220)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).frame(height: 240)
            }.ignoresSafeArea().allowsHitTesting(false)

            if session.stage == .fighting || session.stage == .paused {
                SparringTargetsLayer(session: session).ignoresSafeArea().allowsHitTesting(false)
            }
            SparringHitFlash(session: session).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 8) {
                SparringTopHUD(session: session, end: { session.pause() }, pause: { session.pause() })
                SparringStreakHUD(session: session)
                Spacer()
                SparringCentreHUD(session: session)
                Spacer()
                SparringFeedbackToast(session: session)
                SparringUpNext(session: session)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            if session.stage == .paused {
                SparringPauseMenu(resume: { session.resume() }, end: { session.end() })
            }
            if session.stage == .finished {
                SparringResultsView(session: session, newRecord: newRecord, saved: saved, store: store, savedID: savedID,
                                    again: { dismiss() }, done: { onFinish?(session.engine.summary); dismiss() })
                    .transition(.opacity)
                    .onAppear { finish() }
            }
        }
        .statusBarHidden().persistentSystemOverlays(.hidden)
        .task { await session.start() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                session.tick()
            }
        }
        .onDisappear { session.stop() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.stage)
    }
    private func finish() {
        guard !saved else { return }
        session.stop()
        newRecord = session.commitHighScore()
        let summary = session.engine.summary
        if onFinish == nil, let store, summary.attempts > 0 {
            let record = session.record()
            saved = store.record(record)
            if saved { savedID = record.id }
        }
        if newRecord { BoxHaptics.success() }
    }
}

// MARK: Targets

private struct SparringTargetsLayer: View {
    let session: SparringSession
    var body: some View {
        TimelineView(.animation) { timeline in
            let clock = SparringSession.now + 0 * timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(session.engine.active) { beat in
                    SparringTarget(beat: beat, session: session, clockMs: clock)
                }
                ForEach(session.effects) { effect in
                    SparringHitEffect(effect: effect, clockMs: clock, scale: session.screenScale)
                }
            }
        }
    }
}

private struct SparringTarget: View {
    let beat: SparringBeat
    let session: SparringSession
    let clockMs: Double
    var body: some View {
        let progress = min(1.15, max(0, (clockMs - beat.spawnMs) / max(1, beat.hitMs - beat.spawnMs)))
        let anchor = session.screenPoint(for: beat.action)
        let size = max(70, min(170, session.screenScale * 0.95))
        let color = session.configuration.goldTargets == true ? Color(red: 1, green: 0.8, blue: 0.3) : SparringStyle.color(beat.action.kind)
        let label = beat.action.shortTitle(stance: session.configuration.stance)
        Group {
            switch beat.action.kind {
            case .straight, .hook, .uppercut:
                ZStack {
                    // Approach ring closes onto the pad exactly on the beat.
                    Circle().stroke(color.opacity(0.9), lineWidth: 4)
                        .frame(width: size * (1 + 1.6 * max(0, 1 - progress)), height: size * (1 + 1.6 * max(0, 1 - progress)))
                        .shadow(color: color, radius: 8)
                    SparringMitt(size: size, tint: color, kind: beat.action.kind, side: beat.action.side)
                        .scaleEffect(0.45 + 0.55 * min(1, progress))
                    targetLabel(label, color: color, step: beat.comboLength > 1 ? beat.step + 1 : nil)
                        .offset(y: size * 0.72)
                }
            case .slip:
                SparringIncomingGlove(progress: progress, size: size, color: color, dodgeLeft: beat.action.side == .left)
                    .overlay(alignment: .bottom) { targetLabel(label, color: color, step: nil).offset(y: size * 0.9) }
            case .duck:
                SparringDuckBar(progress: progress, color: color, viewportWidth: session.viewport.width, label: label)
            }
        }
        .position(beat.action.kind == .duck ? CGPoint(x: session.viewport.width / 2, y: anchor.y) : anchor)
        .opacity(min(1, progress * 3))
    }
    private func targetLabel(_ text: String, color: Color, step: Int?) -> some View {
        HStack(spacing: 5) {
            if let step { Text("\(step)").boxNumber(13).foregroundStyle(.black).frame(width: 18, height: 18).background(color, in: .circle) }
            Text(text).font(.system(size: 15, weight: .black).width(.condensed)).textCase(.uppercase).modifier(BoxOblique())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.65), in: .capsule)
        .overlay { Capsule().strokeBorder(color.opacity(0.7)) }
    }
}

/// Focus mitt with a direction hint for hooks (curved) and uppercuts (up).
private struct SparringMitt: View {
    let size: CGFloat
    let tint: Color
    let kind: FightAction.Kind
    let side: FightAction.Side
    var body: some View {
        ZStack {
            Canvas { context, canvas in
                context.withCGContext { PadMittArt.draw(in: CGRect(origin: .zero, size: canvas).insetBy(dx: canvas.width * 0.08, dy: canvas.width * 0.08), context: $0) }
            }
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(kind == .hook ? (side == .left ? 38 : -38) : kind == .uppercut ? 40 : 0),
                              axis: kind == .uppercut ? (1, 0, 0) : (0, 1, 0))
            if kind == .hook {
                // On the mirrored screen the fighter's left hand sweeps from screen-left inward.
                Image(systemName: side == .left ? "arrow.turn.down.right" : "arrow.turn.down.left")
                    .font(.system(size: size * 0.32, weight: .heavy)).foregroundStyle(tint)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(x: side == .left ? size * 0.55 : -size * 0.55, y: -size * 0.45)
            } else if kind == .uppercut {
                Image(systemName: "arrow.up").font(.system(size: size * 0.34, weight: .heavy)).foregroundStyle(tint)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(y: size * 0.62)
            }
        }
    }
}

private struct SparringIncomingGlove: View {
    let progress: Double
    let size: CGFloat
    let color: Color
    let dodgeLeft: Bool
    var body: some View {
        let p = min(1, progress)
        ZStack {
            // The attack aims at the head; the arrow shows which way to move it.
            Circle().fill(color.opacity(0.18)).frame(width: size * 1.4, height: size * 1.4)
                .overlay { Circle().stroke(color, style: StrokeStyle(lineWidth: 3, dash: [10, 8])) }
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size * (0.35 + 0.65 * p), weight: .black))
                .foregroundStyle(.white)
                .shadow(color: color, radius: 14)
                .rotationEffect(.degrees(dodgeLeft ? -20 : 20))
            Image(systemName: dodgeLeft ? "arrow.left" : "arrow.right")
                .font(.system(size: size * 0.45, weight: .black)).foregroundStyle(color)
                .offset(x: dodgeLeft ? -size * 0.95 : size * 0.95)
                .shadow(color: .black.opacity(0.6), radius: 3)
        }
    }
}

private struct SparringDuckBar: View {
    let progress: Double
    let color: Color
    let viewportWidth: CGFloat
    let label: String
    var body: some View {
        let p = min(1, progress)
        ZStack {
            Capsule().fill(LinearGradient(colors: [color.opacity(0.5), color, color.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                .frame(width: viewportWidth * (0.2 + 0.85 * p), height: 14 + 10 * p)
                .shadow(color: color, radius: 16)
            HStack(spacing: 6) {
                Image(systemName: "arrow.down").font(.system(size: 18, weight: .black))
                Text(label).font(.system(size: 18, weight: .black).width(.condensed)).textCase(.uppercase).modifier(BoxOblique())
            }
            .foregroundStyle(.white).offset(y: 34)
        }
    }
}

private struct SparringHitEffect: View {
    let effect: SparringSession.Effect
    let clockMs: Double
    let scale: CGFloat
    var body: some View {
        let t = min(1, max(0, (clockMs - effect.startMs) / 900))
        let grade = effect.result.grade
        let color = SparringStyle.gradeColor(grade)
        ZStack {
            if grade.isHit {
                ForEach(0..<10, id: \.self) { i in
                    let angle = Double(i) / 10 * 2 * .pi
                    Circle().fill(color).frame(width: 9, height: 9)
                        .offset(x: cos(angle) * scale * 0.9 * t, y: sin(angle) * scale * 0.9 * t)
                        .opacity(1 - t)
                }
                Circle().stroke(color, lineWidth: 5).frame(width: scale * (0.8 + 1.2 * t), height: scale * (0.8 + 1.2 * t)).opacity(1 - t)
            } else {
                Image(systemName: "xmark").font(.system(size: scale * 0.5, weight: .black)).foregroundStyle(color).opacity(1 - t)
            }
            VStack(spacing: 0) {
                Text(grade.title).font(.system(size: 26, weight: .black).width(.compressed)).textCase(.uppercase).modifier(BoxOblique())
                    .foregroundStyle(color).shadow(color: color.opacity(0.8), radius: 10)
                if effect.result.points > 0 {
                    Text("+\(effect.result.points)\(effect.result.multiplier > 1 ? "  ×\(effect.result.multiplier)" : "")")
                        .font(.system(size: 18, weight: .heavy).width(.condensed)).monospacedDigit().foregroundStyle(.white)
                }
            }
            .offset(y: -scale * 0.6 - 60 * t)
            .opacity(t < 0.75 ? 1 : (1 - t) * 4)
            .scaleEffect(t < 0.12 ? 0.6 + t * 3.3 : 1)
        }
        .position(effect.anchor)
    }
}

/// Red vignette when an attack lands (missed dodge).
private struct SparringHitFlash: View {
    let session: SparringSession
    @State private var flash = 0.0
    var body: some View {
        RadialGradient(colors: [.clear, BoxStyle.accent.opacity(0.75)], center: .center, startRadius: 120, endRadius: 520)
            .opacity(flash)
            .onChange(of: session.resultID) { _, _ in
                guard let result = session.lastResult, !result.grade.isHit,
                      result.beat.action.kind == .slip || result.beat.action.kind == .duck else { return }
                flash = 1
                withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            }
    }
}

// MARK: HUD

private struct SparringTopHUD: View {
    let session: SparringSession
    let end: () -> Void
    let pause: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            hudButton("xmark", label: "End", action: end)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.configuration.drillTitle.map { LocalizedStringResource(stringLiteral: $0) } ?? (session.configuration.mode == .check ? "Detection check" : "Round \(max(1, session.engine.round)) of \(session.configuration.rounds)"))
                    .boxEyebrow(.white.opacity(0.8))
                Text(Duration.seconds(Int(session.engine.roundRemainingMs / 1000)).formatted(.time(pattern: .minuteSecond)))
                    .boxNumber(22, italic: true).foregroundStyle(.white)
                    .opacity(session.configuration.mode == .check ? 0 : 1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Score").boxEyebrow(.white.opacity(0.8))
                Text(session.engine.score, format: .number).boxNumber(34, italic: true).foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(session.engine.score)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: session.engine.score)
                if session.configuration.mode == .arcade {
                    HStack(spacing: 3) {
                        ForEach(0..<session.configuration.startingLives, id: \.self) { i in
                            Image(systemName: i < session.engine.lives ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(i < session.engine.lives ? BoxStyle.accent : .white.opacity(0.4))
                                .symbolEffect(.bounce, value: session.engine.lives)
                        }
                    }
                    .accessibilityLabel(Text("\(session.engine.lives) lives"))
                }
            }
            hudButton("pause.fill", label: "Pause", action: pause)
        }
        .padding(.top, 4)
    }
    private func hudButton(_ symbol: String, label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.45), in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.18)) }
        }
        .buttonStyle(BoxPressStyle(scale: 0.88)).accessibilityLabel(Text(label))
    }
}

private struct SparringStreakHUD: View {
    let session: SparringSession
    var body: some View {
        let streak = session.engine.streak
        HStack(spacing: 8) {
            if streak >= 3 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [BoxStyle.strength, BoxStyle.accent], startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.bounce, value: streak)
                    Text("\(streak)").boxNumber(26, italic: true).foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(streak)))
                    Text("streak").boxEyebrow(.white.opacity(0.8))
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.black.opacity(0.55), in: .capsule)
                .overlay { Capsule().strokeBorder(BoxStyle.strength.opacity(0.6)) }
                .shadow(color: BoxStyle.strength.opacity(streak >= 16 ? 0.7 : 0.3), radius: streak >= 16 ? 16 : 6)
                .transition(.scale.combined(with: .opacity))
            }
            if session.engine.multiplier > 1 {
                Text("×\(session.engine.multiplier)").boxNumber(26, italic: true)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(BoxStyle.strength, in: .capsule)
                    .shadow(color: BoxStyle.strength, radius: 10)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                    .id(session.engine.multiplier)
            }
            Spacer()
        }
        .frame(height: 40)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: session.engine.multiplier)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: streak >= 3)
    }
}

private struct SparringCentreHUD: View {
    let session: SparringSession
    var body: some View {
        Group {
            if let error = session.camera.error {
                Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
            } else {
                switch session.stage {
                case .framing:
                    VStack(spacing: 12) {
                        ZStack {
                            ViewfinderCorners().frame(width: 230, height: 270)
                            Image(systemName: "figure.boxing").font(.system(size: 96, weight: .light)).foregroundStyle(.white.opacity(0.35))
                        }
                        Text(session.camera.readiness == .inView ? "Hold your guard" : "Step into frame").boxDisplay(40).foregroundStyle(.white)
                        Text("Head, shoulders and both arms in view, with room to move. We start automatically.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                case .countdown(let n):
                    ZStack {
                        Circle().stroke(BoxStyle.accent, lineWidth: 8).frame(width: 210, height: 210).shadow(color: BoxStyle.accent, radius: 16)
                        Text("\(n)").boxNumber(150, relativeTo: .largeTitle, italic: true).foregroundStyle(.white)
                    }
                    .id(n).transition(.scale(scale: 1.6).combined(with: .opacity))
                case .fighting:
                    if session.engine.phase == .rest {
                        VStack(spacing: 6) {
                            Text("Rest").boxEyebrow(BoxStyle.timer)
                            Text("\(Int(session.engine.roundRemainingMs / 1000))").boxNumber(110, italic: true).foregroundStyle(.white)
                            Text("Round \(session.engine.round + 1) next. Breathe.").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: session.stage)
    }
}

private struct SparringFeedbackToast: View {
    let session: SparringSession
    @State private var visible = false
    var body: some View {
        ZStack {
            if visible, let text = session.feedback {
                Text(text).font(.subheadline.weight(.bold)).foregroundStyle(.black).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(BoxStyle.strength, in: .capsule)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(minHeight: 44)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: visible)
        .task(id: session.feedbackID) {
            guard session.feedback != nil else { return }
            visible = true
            try? await Task.sleep(for: .seconds(1.6))
            visible = false
        }
    }
}

/// The next few moves, so a fighter can read the combination coming.
private struct SparringUpNext: View {
    let session: SparringSession
    var body: some View {
        let upcoming = Array(session.engine.active.sorted { $0.hitMs < $1.hitMs }.prefix(4))
        HStack(spacing: 8) {
            if !upcoming.isEmpty {
                Text("Up next").boxEyebrow(.white.opacity(0.7))
                ForEach(upcoming) { beat in
                    HStack(spacing: 4) {
                        Image(systemName: SparringStyle.symbol(beat.action.kind)).font(.system(size: 11, weight: .black))
                        Text(beat.action.shortTitle(stance: session.configuration.stance)).font(.caption.weight(.heavy)).textCase(.uppercase)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(SparringStyle.color(beat.action.kind).opacity(0.35), in: .capsule)
                    .overlay { Capsule().strokeBorder(SparringStyle.color(beat.action.kind).opacity(0.8)) }
                }
            } else if let detected = session.lastDetected, session.stage == .fighting {
                Text("Seen: \(detected.title(stance: session.configuration.stance))").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    .id(session.detectedID)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: upcoming.map(\.id))
    }
}

private struct SparringPauseMenu: View {
    let resume: () -> Void
    let end: () -> Void
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.6)).background(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Paused").boxDisplay(56).foregroundStyle(.white)
                PrimaryButton(title: "Resume", symbol: "play.fill", action: resume)
                Button(action: end) { Label("End and see results", systemImage: "flag.checkered").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxSecondaryStyle())
            }.padding(24).frame(maxWidth: 420)
        }
    }
}

// MARK: - Results

private struct SparringResultsView: View {
    let session: SparringSession
    let newRecord: Bool
    let saved: Bool
    var store: AppStore? = nil
    var savedID: UUID? = nil
    let again: () -> Void
    let done: () -> Void
    var body: some View {
        let summary = session.engine.summary
        let check = session.configuration.mode == .check
        ZStack {
            Rectangle().fill(.black.opacity(0.7)).background(.ultraThinMaterial).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 8) {
                        if newRecord { BoxChip(text: "New high score", symbol: "trophy.fill", color: BoxStyle.strength) }
                        Text(check ? "Detection check" : summary.knockedOut ? "Knocked out" : "Fight over")
                            .boxEyebrow(summary.knockedOut ? BoxStyle.accent : BoxStyle.conditioning)
                        Text(check ? "\(Int(summary.accuracy * 100))%" : summary.score.formatted())
                            .boxNumber(84, relativeTo: .largeTitle, italic: true).foregroundStyle(.white)
                        Text(check ? "of moves recognised as asked" : "points").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }.frame(maxWidth: .infinity).padding(.top, 24)
                    if !check {
                        HStack(spacing: 8) {
                            stat("\(Int(summary.accuracy * 100))%", "Accuracy")
                            stat("\(summary.maxStreak)", "Best streak")
                            stat("\(summary.perfects)", "Perfect")
                        }
                    }
                    BoxSectionHeader(title: check ? "What the camera saw" : "By move")
                    VStack(spacing: 0) {
                        ForEach(summary.moves.keys.sorted(), id: \.self) { name in
                            let stats = summary.moves[name]!
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(stats.hit)/\(stats.asked)").boxNumber(18)
                                        .foregroundStyle(stats.hit == stats.asked ? BoxStyle.conditioning : stats.hit * 2 >= stats.asked ? BoxStyle.strength : BoxStyle.accent)
                                }
                                let misreads = stats.detectedAs.filter { $0.key != name }.sorted { $0.value > $1.value }
                                if !misreads.isEmpty {
                                    Text(misreads.map { "\($0.key) ×\($0.value)" }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(BoxStyle.muted)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(BoxStyle.border).frame(height: 1) }
                        }
                    }
                    .boxPanel(padding: 0)
                    if check {
                        Text("A move counts only when the camera recognised exactly that move within the window. Misreads show what it saw instead; \"Nothing\" means no move was recognised.")
                            .font(.caption).foregroundStyle(BoxStyle.muted)
                    }
                    if let store, let savedID {
                        XPEarnedCard(store: store, sessionID: savedID)
                        CoachDebriefCard(store: store, recordID: savedID, onDark: true)
                    }
                    if saved { Label("Saved to Progress", systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.conditioning) }
                    PrimaryButton(title: "Done", symbol: "checkmark", action: done).padding(.top, 6)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
        }
    }
    private func stat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).boxNumber(28).foregroundStyle(.white)
            Text(label).boxEyebrow(.white.opacity(0.7))
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
    }
}
