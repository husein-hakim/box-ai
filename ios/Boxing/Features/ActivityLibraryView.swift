import SwiftUI

private enum LibraryFilter: String, CaseIterable {
    case all = "All", foundation = "Foundation", camera = "Camera", strength = "Strength", conditioning = "Conditioning", core = "Core", mobility = "Mobility"
}

struct ActivityLibraryView: View {
    let store: AppStore
    var boxingOnly = false
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var visible: [CatalogActivity] = []
    private var filters: [LibraryFilter] { boxingOnly ? [.all, .foundation, .camera] : [.all, .strength, .conditioning, .core, .mobility] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: boxingOnly ? "Drills" : "Exercises", subtitle: boxingOnly ? "Build one skill at a time." : "Strength and movement for your boxing.")
                    .boxEntrance()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { item in
                            let selected = item == filter
                            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { filter = item } } label: {
                                Text(item.rawValue).font(.footnote.weight(.semibold))
                                    .foregroundStyle(selected ? BoxStyle.ink : BoxStyle.muted)
                                    .padding(.horizontal, 14).frame(minHeight: 36)
                                    .background(selected ? (boxingOnly ? BoxStyle.accent : BoxStyle.strength).opacity(0.16) : BoxStyle.surface, in: .capsule)
                                    .overlay { Capsule().strokeBorder(selected ? (boxingOnly ? BoxStyle.accent : BoxStyle.strength).opacity(0.6) : BoxStyle.border) }
                            }
                            .buttonStyle(BoxPressStyle(scale: 0.94))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .scrollClipDisabled()
                .boxEntrance(1)
                Text("\(visible.count) \(boxingOnly ? "drills" : "exercises")").boxEyebrow().padding(.top, 4)
                if visible.isEmpty {
                    BoxEmptyState(symbol: "magnifyingglass", title: "Try another search.", detail: "Search by movement, skill or equipment, or change the filter.")
                }
                LazyVStack(spacing: 10) {
                    ForEach(visible) { activity in
                        NavigationLink { ActivityDetailView(store: store, activity: activity) } label: { CatalogActivityRow(activity: activity) }
                            .buttonStyle(BoxPressStyle())
                    }
                }.boxEntrance(2)
                Text("Original instructions · Coach review pending · No demonstration media").font(.caption).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }.boxScreen(tint: boxingOnly ? BoxStyle.accent : BoxStyle.strength).foregroundStyle(BoxStyle.ink)
            .navigationTitle(boxingOnly ? "Drill library" : "Exercise library").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .searchable(text: $query, prompt: "Find a movement")
            .onAppear { updateResults() }
            .onChange(of: query) { _, _ in updateResults() }
            .onChange(of: filter) { _, _ in updateResults(); BoxHaptics.selection() }
    }
    private func updateResults() {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = ActivityCatalog.all.filter { activity in
            guard boxingOnly ? activity.kind == .boxing : activity.kind != .boxing else { return false }
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .foundation: matches = activity.difficulty == .beginner
            case .camera: matches = CameraPlanningCapability.supports(activity.id)
            case .strength: matches = activity.kind == .strength
            case .conditioning: matches = activity.kind == .conditioning
            case .core: matches = activity.kind == .core
            case .mobility: matches = [ActivityKind.warmup, .mobility, .cooldown].contains(activity.kind)
            }
            return matches && (search.isEmpty || ([activity.title, activity.objective] + activity.equipment).joined(separator: " ").localizedStandardContains(search))
        }
    }
}

private struct CatalogActivityRow: View {
    let activity: CatalogActivity
    private var color: Color {
        switch activity.kind {
        case .boxing: BoxStyle.accent
        case .strength, .core: BoxStyle.strength
        case .conditioning: BoxStyle.conditioning
        default: BoxStyle.timer
        }
    }
    private var symbol: String {
        switch activity.kind {
        case .boxing: "figure.boxing"
        case .strength: "dumbbell.fill"
        case .core: "figure.core.training"
        case .conditioning: "figure.run"
        default: "figure.flexibility"
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            BoxIconWell(symbol: symbol, size: 46, color: color)
            VStack(alignment: .leading, spacing: 5) {
                Text(activity.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                Text(activity.objective).font(.caption).foregroundStyle(BoxStyle.muted).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    BoxChip(text: activity.difficulty == .beginner ? "Foundation" : "Intermediate",
                            color: activity.difficulty == .beginner ? BoxStyle.conditioning : BoxStyle.strength)
                    if CameraPlanningCapability.supports(activity.id) { BoxChip(text: "Camera · Beta", symbol: "camera.fill", color: BoxStyle.accent) }
                }.padding(.top, 2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
        }.foregroundStyle(BoxStyle.ink).boxPanel(padding: 14)
    }
}

struct ActivityDetailView: View {
    let store: AppStore
    let activity: CatalogActivity
    @State private var mode: TrainingMode
    @State private var sets = 1
    @State private var seconds = 60
    @State private var reps = 8
    @State private var rest = 30
    init(store: AppStore, activity: CatalogActivity) {
        self.store = store; self.activity = activity
        _mode = State(initialValue: activity.modes[0])
    }
    private var session: GuidedSession {
        .init(title: activity.title, type: activity.kind == .boxing ? .technique : .mixed, activities: [
            .init(id: "practice", activityID: activity.id, mode: mode, sets: sets, reps: activity.support.kind == .repetitions ? reps : 0, workSeconds: seconds, restSeconds: rest)
        ])
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let errors = store.sessionErrors(session)
                VStack(alignment: .leading, spacing: 0) {
                    Label(activity.kind == .boxing ? "Drill" : "Exercise", systemImage: activity.kind == .boxing ? "figure.boxing" : "dumbbell.fill")
                        .boxEyebrow(.white.opacity(0.85))
                    Text(activity.title).boxDisplay(38, relativeTo: .title).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                    Text(activity.objective).font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        BoxValueChip(text: String(localized: "\(sets) sets"), onHero: true)
                        BoxValueChip(text: activity.support.kind == .repetitions ? String(localized: "\(reps) reps") : String(localized: "\(seconds)s work"), onHero: true)
                        BoxChip(text: activity.difficulty == .beginner ? "Foundation" : "Intermediate", onHero: true)
                    }.padding(.top, 14)
                    Button { store.start(session) } label: {
                        Label(mode == .camera ? "Start camera practice" : "Start practice", systemImage: mode == .camera ? "camera.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BoxHeroButtonStyle())
                    .disabled(!errors.isEmpty).opacity(errors.isEmpty ? 1 : 0.5)
                    .padding(.top, 18)
                }.boxHero().boxEntrance()
                if !errors.isEmpty { BoxInlineNotice(text: "\(errors.joined(separator: "\n"))", symbol: "exclamationmark.triangle", color: BoxStyle.strength) }
                BoxSectionHeader(title: "Your set").padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    if activity.modes.count > 1 {
                        BoxSegmented(options: activity.modes, selection: $mode, title: { LocalizedStringResource(stringLiteral: $0.title) })
                            .padding(.bottom, 8)
                    }
                    PrescriptionStepper(label: "Sets", value: $sets, range: 1...activity.support.maxSets, step: 1, unit: nil)
                    PrescriptionStepper(label: activity.support.kind == .timed ? "Work" : "Time allowance", value: $seconds, range: activity.support.minWork...activity.support.maxWork, step: 10, unit: "sec")
                    if activity.support.kind == .repetitions {
                        PrescriptionStepper(label: activity.repsPerSide ? "Reps per side" : "Reps", value: $reps, range: 1...activity.support.maxReps, step: 1, unit: nil)
                    }
                    if sets > 1 { PrescriptionStepper(label: "Rest", value: $rest, range: 15...activity.support.maxRest, step: 15, unit: "sec") }
                }.boxPanel().boxEntrance(1)
                ActivityInstructions(activity: activity, mode: mode).boxEntrance(2)
                DevelopmentNote(text: "Guided completion is confirmed by you. Supported camera practice stores experimental observations separately. Instructions are pending coach review; no demonstration video is available.")
            }.boxPage()
        }.boxScreen().foregroundStyle(BoxStyle.ink).navigationTitle("Practice").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

/// Label, big condensed value and round − / + controls for one prescription field.
private struct PrescriptionStepper: View {
    let label: LocalizedStringResource
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: LocalizedStringResource?
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(BoxStyle.muted)
            Spacer()
            control("minus", enabled: value - step >= range.lowerBound) { value = max(range.lowerBound, value - step) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value, format: .number).boxNumber(22).contentTransition(.numericText(value: Double(value)))
                if let unit { Text(unit).font(.caption2).foregroundStyle(BoxStyle.muted) }
            }
            .frame(minWidth: 64)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
            control("plus", enabled: value + step <= range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
    private func control(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); BoxHaptics.selection() } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .frame(width: 36, height: 36)
                .background(BoxStyle.surfaceRaised, in: .circle)
                .overlay { Circle().strokeBorder(BoxStyle.borderStrong) }
        }
        .buttonStyle(BoxPressStyle(scale: 0.88))
        .disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}
