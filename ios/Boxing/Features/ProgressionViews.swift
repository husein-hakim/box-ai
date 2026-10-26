import SwiftUI

// MARK: - Styling

enum ProgressionStyle {
    /// Bronze → silver → gold → red-gold as ranks climb.
    static func metal(_ rank: BoxRank) -> [Color] {
        switch rank.index {
        case 0...2: [Color(red: 0.86, green: 0.55, blue: 0.33), Color(red: 0.55, green: 0.3, blue: 0.16)]
        case 3...5: [Color(red: 0.88, green: 0.9, blue: 0.94), Color(red: 0.5, green: 0.53, blue: 0.6)]
        case 6...8: [Color(red: 1.0, green: 0.84, blue: 0.38), Color(red: 0.72, green: 0.5, blue: 0.1)]
        default: [Color(red: 1.0, green: 0.45, blue: 0.3), Color(red: 0.62, green: 0.06, blue: 0.1)]
        }
    }
    static func color(_ group: BadgeDefinition.Group) -> Color {
        switch group { case .training: BoxStyle.accent; case .sparring: BoxStyle.strength; case .fuel: BoxStyle.conditioning }
    }
    static func title(_ group: BadgeDefinition.Group) -> String {
        switch group { case .training: String(localized: "Training"); case .sparring: String(localized: "Sparring"); case .fuel: String(localized: "Fuel") }
    }
}

/// Rank medal: metallic ring, dark core, rank symbol.
struct RankEmblem: View {
    let rank: BoxRank
    var size: CGFloat = 96
    var locked = false
    var body: some View {
        let metal = ProgressionStyle.metal(rank)
        ZStack {
            Circle().fill(LinearGradient(colors: locked ? [Color(white: 0.3), Color(white: 0.16)] : metal, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.05)], center: .topLeading, startRadius: 0, endRadius: size))
                .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                .padding(size * 0.09)
            Image(systemName: rank.symbol).font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(LinearGradient(colors: locked ? [Color(white: 0.45), Color(white: 0.3)] : metal, startPoint: .top, endPoint: .bottom))
            Circle().trim(from: 0.55, to: 0.75).stroke(.white.opacity(locked ? 0.05 : 0.35), style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                .padding(size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: locked ? .clear : metal[0].opacity(0.45), radius: size * 0.16)
        .accessibilityElement().accessibilityLabel(Text(rank.title))
    }
}

/// Apple Fitness–style award medal.
struct BadgeMedal: View {
    let badge: BadgeState
    var size: CGFloat = 76
    var body: some View {
        let color = ProgressionStyle.color(badge.definition.group)
        ZStack {
            if badge.earned {
                Circle().fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(Color(white: 0.07))
                    .overlay { Circle().strokeBorder(color.opacity(0.6), lineWidth: 1.5) }
                    .padding(size * 0.08)
                Image(systemName: badge.definition.symbol).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(color)
            } else {
                Circle().fill(Color(white: 0.1))
                Circle().stroke(Color(white: 0.2), lineWidth: size * 0.05)
                Circle().trim(from: 0, to: badge.progress).stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: badge.definition.symbol).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(Color(white: 0.32))
            }
            if badge.definition.repeatable && badge.count > 1 {
                Text("×\(badge.count)").font(.system(size: size * 0.17, weight: .heavy)).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(color, in: .capsule)
                    .offset(x: size * 0.32, y: size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: badge.earned ? color.opacity(0.35) : .clear, radius: 10)
        .accessibilityElement().accessibilityLabel(Text(badge.definition.title))
        .accessibilityValue(Text(badge.earned ? (badge.count > 1 ? "Earned \(badge.count) times" : "Earned") : "Locked"))
    }
}

// MARK: - Progress tab sections

struct RankCard: View {
    let state: ProgressionState
    var unlocks: UnlockState? = nil
    var body: some View {
        NavigationLink { RankLadderView(state: state, unlocks: unlocks) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    RankEmblem(rank: state.rank, size: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rank").boxEyebrow()
                        Text(state.rank.title).boxDisplay(32, relativeTo: .title).foregroundStyle(BoxStyle.ink)
                        Text("Level \(state.level) · \(state.totalXP.formatted()) XP").font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
                }
                VStack(alignment: .leading, spacing: 6) {
                    BoxProgressTrack(value: state.levelProgress, color: ProgressionStyle.metal(state.rank)[0], height: 8)
                    HStack {
                        Text("\(state.xpToNextLevel.formatted()) XP to level \(state.level + 1)").font(.caption.weight(.semibold))
                        Spacer()
                        if let next = state.nextRank { Text("\(next.title) at level \(next.minimumLevel)").font(.caption).foregroundStyle(BoxStyle.muted) }
                    }.foregroundStyle(BoxStyle.ink)
                    if let next = unlocks?.next {
                        Label("Next unlock: \(next.title) · level \(next.minimumLevel)", systemImage: "lock.open.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(ProgressionStyle.metal(state.rank)[0]).padding(.top, 2)
                    }
                }
            }
            .boxPanel(padding: 18, tint: ProgressionStyle.metal(state.rank)[0])
        }
        .buttonStyle(BoxPressStyle())
    }
}

struct AwardsSection: View {
    let state: ProgressionState
    @State private var selected: BadgeState?
    var body: some View {
        let earned = state.badges.filter(\.earned).count
        VStack(alignment: .leading, spacing: 12) {
            BoxSectionHeader(title: "Awards") { Text("\(earned) of \(state.badges.count)") }
            ForEach(BadgeDefinition.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(ProgressionStyle.title(group)).boxEyebrow(ProgressionStyle.color(group))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                        ForEach(state.badges.filter { $0.definition.group == group }) { badge in
                            Button { selected = badge } label: {
                                VStack(spacing: 6) {
                                    BadgeMedal(badge: badge, size: 64)
                                    Text(badge.definition.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                                        .foregroundStyle(badge.earned ? BoxStyle.ink : BoxStyle.muted)
                                }
                            }.buttonStyle(BoxPressStyle(scale: 0.92))
                        }
                    }
                }
            }
        }
        .sheet(item: $selected) { badge in BadgeDetailSheet(badge: badge).presentationDetents([.medium]) }
    }
}

private struct BadgeDetailSheet: View {
    let badge: BadgeState
    var body: some View {
        VStack(spacing: 14) {
            BadgeMedal(badge: badge, size: 130).padding(.top, 30)
            Text(badge.definition.title).boxDisplay(32).foregroundStyle(BoxStyle.ink)
            Text(badge.definition.detail).font(.subheadline).foregroundStyle(BoxStyle.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
            if badge.earned {
                Text(badge.count > 1 ? "Earned \(badge.count) times" : badge.earnedAt.map { "Earned \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Earned")
                    .font(.footnote.weight(.semibold)).foregroundStyle(ProgressionStyle.color(badge.definition.group))
            } else if let text = badge.progressText {
                VStack(spacing: 6) {
                    BoxProgressTrack(value: badge.progress, color: ProgressionStyle.color(badge.definition.group)).frame(width: 180)
                    Text(text).font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.muted)
                }
            }
            Text("+\(Progression.Rules.badgeBonus) XP each time").font(.caption).foregroundStyle(BoxStyle.dim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .boxScreen(tint: ProgressionStyle.color(badge.definition.group))
    }
}

struct RecentXPSection: View {
    let state: ProgressionState
    var body: some View {
        let recent = Array(state.events.prefix(8))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                BoxSectionHeader(title: "Recent XP") { Text("+\(state.xp(on: .now)) today") }
                BoxRowGroup {
                    ForEach(recent) { event in
                        BoxRow(symbol: symbol(event.category), color: color(event.category), title: event.title,
                               subtitle: event.date.formatted(.dateTime.month(.abbreviated).day()), showsChevron: false) {
                            Text("+\(event.amount)").boxNumber(17).foregroundStyle(BoxStyle.ink)
                        }
                    }
                }
            }
        }
    }
    private func symbol(_ c: XPEvent.Category) -> String {
        switch c { case .training: "figure.boxing"; case .plan: "calendar.badge.checkmark"; case .sparring: "flame.fill"; case .fuel: "fork.knife"; case .streak: "flame"; case .badge: "medal.fill" }
    }
    private func color(_ c: XPEvent.Category) -> Color {
        switch c { case .training, .plan: BoxStyle.accent; case .sparring, .streak: BoxStyle.strength; case .fuel: BoxStyle.conditioning; case .badge: BoxStyle.coach }
    }
}

struct RankLadderView: View {
    let state: ProgressionState
    var unlocks: UnlockState? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Ranks", subtitle: "Earn XP from real training, fuel and sparring. Every rank is a few levels further.")
                VStack(alignment: .leading, spacing: 6) {
                    Text("How you earn XP").boxEyebrow()
                    ForEach(Self.howTo, id: \.0) { item in
                        HStack { Text(item.0).font(.subheadline); Spacer(); Text(item.1).font(.subheadline.weight(.bold)).foregroundStyle(BoxStyle.strength) }
                    }
                }.boxPanel(padding: 16)
                ForEach(Progression.ranks) { rank in
                    let reached = rank.index <= state.rank.index
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            RankEmblem(rank: rank, size: 56, locked: !reached)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.title).boxSection(20).foregroundStyle(reached ? BoxStyle.ink : BoxStyle.muted)
                                Text("Level \(rank.minimumLevel) · \(Progression.xpRequired(forLevel: rank.minimumLevel).formatted()) XP").font(.caption).foregroundStyle(BoxStyle.muted)
                            }
                            Spacer()
                            if rank == state.rank { BoxChip(text: "You", color: ProgressionStyle.metal(rank)[0]) }
                            else if reached { Image(systemName: "checkmark.circle.fill").foregroundStyle(BoxStyle.conditioning) }
                        }
                        ForEach(RankUnlocks.unlocks(for: rank)) { unlock in
                            let open = unlocks?.isUnlocked(unlock) ?? reached
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: open ? unlock.symbol : "lock.fill").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(open ? ProgressionStyle.metal(rank)[0] : BoxStyle.dim).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(unlock.title).font(.subheadline.weight(.semibold)).foregroundStyle(open ? BoxStyle.ink : BoxStyle.muted)
                                    Text(unlock.detail + (!open ? unlock.challenge.map { " Unlock early: \($0.text)." } ?? "" : "")).font(.caption).foregroundStyle(BoxStyle.muted)
                                }
                            }.padding(.leading, 70)
                        }
                    }
                    .boxPanel(padding: 12, tint: rank == state.rank ? ProgressionStyle.metal(rank)[0] : nil)
                }
            }.boxPage()
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Ranks").navigationBarTitleDisplayMode(.inline)
    }
    static let howTo: [(String, String)] = [
        (String(localized: "Training, per minute"), "+10"),
        (String(localized: "First training of the day"), "+40"),
        (String(localized: "Planned session complete"), "+150"),
        (String(localized: "Sparring (score, streak, difficulty)"), "+60–750"),
        (String(localized: "Meal logged (up to 3 a day)"), "+10"),
        (String(localized: "Protein / water target hit"), "+25 / +15"),
        (String(localized: "Streaks: 3, 7, 14, 30 days"), "+75–1000"),
        (String(localized: "Perfect program week"), "+500"),
        (String(localized: "Each badge"), "+100")
    ]
}

/// Compact level chip with a ring, for headers.
struct LevelChip: View {
    let state: ProgressionState
    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                BoxRing(progress: state.levelProgress, lineWidth: 3, color: ProgressionStyle.metal(state.rank)[0])
                Image(systemName: state.rank.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(ProgressionStyle.metal(state.rank)[0])
            }.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("Lv \(state.level)").font(.caption.weight(.heavy)).foregroundStyle(BoxStyle.ink)
                Text(state.rank.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(BoxStyle.muted).lineLimit(1)
            }
        }
        .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
        .background(BoxStyle.surfaceRaised, in: .capsule)
        .overlay { Capsule().strokeBorder(BoxStyle.border) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Celebration

struct ProgressionCelebrationView: View {
    let celebration: ProgressionSeen.Celebration
    let state: ProgressionState
    let dismiss: () -> Void
    @State private var shown = false
    @State private var burst = false
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.75)).background(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture(perform: dismiss)
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) / 24 * 2 * .pi
                Capsule().fill(i.isMultiple(of: 3) ? BoxStyle.strength : i.isMultiple(of: 2) ? BoxStyle.accent : .white)
                    .frame(width: 6, height: 16)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: cos(angle) * (burst ? 190 : 20), y: sin(angle) * (burst ? 190 : 20) - 60)
                    .opacity(burst ? 0 : 1)
            }
            VStack(spacing: 16) {
                Group {
                    switch celebration.kind {
                    case .level, .rank: RankEmblem(rank: state.rank, size: 170)
                    case .badge(let badge): BadgeMedal(badge: badge, size: 170)
                    }
                }
                .scaleEffect(shown ? 1 : 0.3).rotation3DEffect(.degrees(shown ? 0 : 180), axis: (0, 1, 0))
                Text(eyebrow).boxEyebrow(BoxStyle.strength)
                Text(title).boxDisplay(46).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal, 30)
                if case .rank(let rank) = celebration.kind, !RankUnlocks.unlocks(for: rank).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unlocked").boxEyebrow(BoxStyle.strength)
                        ForEach(RankUnlocks.unlocks(for: rank)) { u in Label(u.title, systemImage: u.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white) }
                    }
                    .padding(14).background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
                }
                PrimaryButton(title: "Nice", symbol: "checkmark", action: dismiss).frame(maxWidth: 240).padding(.top, 10)
            }
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            BoxHaptics.success()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { shown = true }
            withAnimation(.easeOut(duration: 1.1)) { burst = true }
        }
    }
    private var eyebrow: String {
        switch celebration.kind { case .level: String(localized: "Level up"); case .rank: String(localized: "New rank"); case .badge: String(localized: "Award earned") }
    }
    private var title: String {
        switch celebration.kind {
        case .level(let n): String(localized: "Level \(n)")
        case .rank(let r): r.title
        case .badge(let b): b.definition.title
        }
    }
    private var detail: String {
        switch celebration.kind {
        case .level: String(localized: "\(state.xpToNextLevel.formatted()) XP to level \(state.level + 1).")
        case .rank(let r): String(localized: "You reached level \(r.minimumLevel). \(state.nextRank.map { "\($0.title) is next." } ?? "The top of the ladder.")")
        case .badge(let b): b.definition.detail
        }
    }
}

// MARK: - XP on result screens

/// "+XP" for one saved session, with the level bar it moved.
struct XPEarnedCard: View {
    let store: AppStore
    let sessionID: UUID
    @State private var shown = false
    var body: some View {
        let state = store.progression
        let earned = state.xp(forSession: sessionID)
        let color = ProgressionStyle.metal(state.rank)[0]
        HStack(spacing: 14) {
            RankEmblem(rank: state.rank, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("+\(earned) XP").boxNumber(26, italic: true).foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(shown ? earned : 0)))
                    Spacer()
                    Text("Level \(state.level)").font(.caption.weight(.heavy)).foregroundStyle(color)
                }
                BoxProgressTrack(value: shown ? state.levelProgress : 0, color: color, height: 6)
                Text("\(state.xpToNextLevel.formatted()) XP to level \(state.level + 1) · \(state.rank.title)")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(0.35)) }
        .accessibilityElement(children: .combine)
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.3)) { shown = true } }
    }
}

// MARK: - Celebration host

/// Watches saved progress and celebrates each new level, rank or award once.
struct ProgressionCelebrationHost: View {
    let store: AppStore
    @State private var queue: [ProgressionSeen.Celebration] = []
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let state = store.progression
        ZStack {
            if let current = queue.first {
                ProgressionCelebrationView(celebration: current, state: state) {
                    withAnimation(.easeOut(duration: 0.25)) { _ = queue.removeFirst() }
                }
                .id(current.id)
                .transition(.opacity)
            }
        }
        .onAppear { check(state) }
        .onChange(of: state.totalXP) { _, _ in check(store.progression) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { check(store.progression) } }
    }
    private func check(_ state: ProgressionState) {
        let new = ProgressionSeen.update(with: state).filter { item in !queue.contains(item) }
        guard !new.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) { queue.append(contentsOf: new.prefix(4)) }
    }
}
