import SwiftUI

struct TrainView: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    @Binding var selectedTab: AppTab
    @State private var building = false
    @State private var buildingNext = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    BoxPageHeader(title: "Train", subtitle: "Your program first. Everything else when you want it.")
                    GlassPillButton(title: "History", symbol: "clock.arrow.circlepath") { selectedTab = .progress }
                }.boxEntrance()

                ProgramHero(store: store, sheet: $sheet, build: { building = true }, buildNext: { buildingNext = true }).boxEntrance(1)

                BoxSectionHeader(title: "Fight") { Text("Camera") }.padding(.top, 10).boxEntrance(2)
                LazyVGrid(columns: columns, spacing: 10) {
                    NavigationLink { SparringSetupView(store: store) } label: {
                        let best = SparringConfiguration.Difficulty.allCases.map { UserDefaults.standard.integer(forKey: SparringSession.highScoreKey($0)) }.max() ?? 0
                        BoxActionTile(title: "Sparring", subtitle: best > 0 ? "Best \(best) · every move, fast" : "Every move, fast, scored", symbol: "flame.fill", color: BoxStyle.strength)
                    }.buttonStyle(BoxPressStyle())
                    NavigationLink { PadTrainingSetupView(store: store, activityID: nil) } label: {
                        BoxActionTile(title: "Live pads", subtitle: "Aim jab and cross, one at a time", symbol: "camera.viewfinder")
                    }.buttonStyle(BoxPressStyle())
                }.boxEntrance(3)

                BoxSectionHeader(title: "Practise").padding(.top, 10).boxEntrance(4)
                LazyVGrid(columns: columns, spacing: 10) {
                    NavigationLink { DrillLibraryView(store: store) } label: {
                        BoxActionTile(title: "Drills", subtitle: "Punches, defense, combos, footwork", symbol: "square.grid.2x2.fill")
                    }.buttonStyle(BoxPressStyle())
                    NavigationLink { WorkoutLibraryView(store: store) } label: {
                        BoxActionTile(title: "Strength & conditioning", subtitle: "Weights, core, skipping, runs", symbol: "dumbbell.fill", color: BoxStyle.conditioning)
                    }.buttonStyle(BoxPressStyle())
                    Button { sheet = .builder } label: {
                        BoxActionTile(title: "Guided rounds", subtitle: "Bell, rounds & spoken cues", symbol: "timer", color: BoxStyle.timer)
                    }.buttonStyle(BoxPressStyle())
                    Button { sheet = .coach } label: {
                        BoxActionTile(title: "Coach", subtitle: "Questions & training advice", symbol: "bubble.left.and.text.bubble.right.fill", color: BoxStyle.coach)
                    }.buttonStyle(BoxPressStyle())
                }.boxEntrance(5)
            }
            .boxPage()
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Train").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $building) { NavigationStack { ProgramBuilderView(store: store) } }
        .sheet(isPresented: $buildingNext) { NavigationStack { ProgramBuilderView(store: store, nextWeek: true) } }
    }
}

/// The one red hero on Train: the next session of the programme, or the call to build one.
private struct ProgramHero: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    let build: () -> Void
    var buildNext: () -> Void = {}
    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let week = store.plan.filter { $0.date >= today }.sorted { $0.date < $1.date }
        let next = week.first { !store.assignmentIsComplete($0) && $0.session?.activities.isEmpty == false }
        if let next, let session = next.session {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Your program · next session", systemImage: "calendar").boxEyebrow(.white.opacity(0.85))
                    Spacer()
                    Text(Calendar.current.isDateInToday(next.date) ? String(localized: "Today") : Calendar.current.isDateInTomorrow(next.date) ? String(localized: "Tomorrow") : next.date.formatted(.dateTime.weekday(.wide)))
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                }
                Text(session.title).boxDisplay(36, relativeTo: .title).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                let mix = ProgramMix(sessions: [session])
                HStack(spacing: 6) {
                    BoxValueChip(text: Duration.seconds(session.estimatedSeconds).formatted(.time(pattern: .minuteSecond)) + " min", onHero: true)
                    ForEach(mix.parts.filter { $0.label != String(localized: "Mobility") }.prefix(3), id: \.label) { part in
                        BoxValueChip(text: part.label, onHero: true)
                    }
                }.padding(.top, 12)
                HStack(spacing: 4) {
                    ForEach(week.prefix(7), id: \.id) { item in
                        let done = store.assignmentIsComplete(item)
                        let rest = item.session?.activities.isEmpty != false
                        Capsule().fill(done ? .white : rest ? .white.opacity(0.18) : .white.opacity(0.45))
                            .frame(height: 5)
                    }
                }.padding(.top, 14).accessibilityHidden(true)
                HStack(spacing: 8) {
                    Button { store.startAssignment(next) } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(BoxHeroButtonStyle())
                    NavigationLink { WeeklyPlanView(store: store, sheet: $sheet) } label: { Text("Full week") }
                        .buttonStyle(BoxHeroButtonStyle(kind: .ghost))
                }.padding(.top, 16)
            }.boxHero()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Label("Your program", systemImage: "sparkles").boxEyebrow(.white.opacity(0.85))
                let due = store.nextWeekDue
                Text(due ? "Week done.\nBuild the next." : "One program.\nEverything in it.").boxDisplay(38, relativeTo: .title).padding(.top, 10)
                Text(due ? "Your next week adapts to what you finished, how hard it felt, your camera accuracy and your review fixes."
                         : "Drills, camera training, sparring, footwork, conditioning, strength and nutrition, planned together around your week.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                Button(action: due ? buildNext : build) { Label(due ? "Build next week" : "Build my program", systemImage: due ? "arrow.triangle.2.circlepath" : "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxHeroButtonStyle()).padding(.top, 18)
                if due {
                    Button(action: build) { Text("Start over with new details") }.buttonStyle(BoxHeroButtonStyle(kind: .ghost)).padding(.top, 8)
                }
            }.boxHero()
        }
    }
}

private struct TrainingPlanRow: View {
    let store: AppStore
    var body: some View {
        let upcoming = store.plan.filter { $0.date >= Calendar.current.startOfDay(for: .now) }
        let done = store.plan.filter { $0.completionID != nil }.count
        HStack(spacing: 12) {
            ZStack {
                BoxRing(progress: store.plan.isEmpty ? 0 : Double(done) / Double(store.plan.count), lineWidth: 4)
                Text(store.plan.isEmpty ? "–" : "\(done)/\(store.plan.count)").boxNumber(14, relativeTo: .caption)
            }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your plan").boxEyebrow(BoxStyle.accent)
                Text(verbatim: upcoming.first?.displayTitle ?? String(localized: "Build a week around your goals"))
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(upcoming.isEmpty ? "No sessions scheduled" : "\(upcoming.count) upcoming sessions").font(.caption).foregroundStyle(BoxStyle.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
        }.foregroundStyle(BoxStyle.ink).boxPanel(padding: 14)
    }
}

struct DrillLibraryView: View {
    let store: AppStore
    var body: some View {
        ActivityLibraryView(store: store, boxingOnly: true)
    }
}

struct SessionBuilderSheet: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = RoundConfiguration()
    @State private var focus: TrainingFocus = .mixed

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Guided rounds", systemImage: "timer").boxEyebrow(.white.opacity(0.85))
                    Text("Your pace.\nYour rounds.").boxDisplay(36, relativeTo: .title).padding(.top, 10)
                    Text("Choose your focus and listen for each cue. This session is unscored.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Duration.seconds(configuration.totalSeconds).formatted(.time(pattern: .minuteSecond))).boxNumber(34)
                            .contentTransition(.numericText(value: Double(configuration.totalSeconds)))
                        Text("total").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }.padding(.top, 14)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: configuration.totalSeconds)
                }.boxHero(ropes: true)
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section("Session") {
                Picker("Focus", selection: $focus) {
                    ForEach(TrainingFocus.allCases) { item in Text(item.title).tag(item) }
                }
                Stepper("Rounds: \(configuration.rounds)", value: $configuration.rounds, in: 1...6)
                Picker("Work per round", selection: $configuration.workSeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                Picker("Rest between rounds", selection: $configuration.restSeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
                .disabled(configuration.rounds == 1)
                Picker("Time between cues", selection: $configuration.cueInterval) {
                    Text("Steady · 8 seconds").tag(8)
                    Text("Easy · 12 seconds").tag(12)
                    Text("Quick · 5 seconds").tag(5)
                }
            }
            Section {
                LabeledContent("Total time", value: Duration.seconds(configuration.totalSeconds).formatted(.time(pattern: .minuteSecond)))
                Text("Includes 1 minute to prepare and 1 minute to reset. Rest is only between work rounds.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
                Text("Original development session. Boxing content is pending coach review.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
            }
        }
        .tint(BoxStyle.muted)
        .boxFormStyle(tint: BoxStyle.timer)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                PrimaryButton(title: "Start guided session") {
                    store.queuedSession = SessionLaunch(configuration: configuration, focus: focus)
                    dismiss()
                }
                Text("Guided audio · No camera scoring")
                    .font(.caption).foregroundStyle(BoxStyle.muted)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(LinearGradient(colors: [BoxStyle.background.opacity(0), BoxStyle.background], startPoint: .top, endPoint: .center))
        }
        .navigationTitle("Build a session").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

struct ScheduleSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let days: [(id: Int, name: LocalizedStringResource)] = [
        (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"),
        (6, "Friday"), (7, "Saturday"), (1, "Sunday")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Training days", subtitle: "Choose days that fit your week. You can change them any time.")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.selectedDays.count)").boxNumber(40).contentTransition(.numericText(value: Double(store.selectedDays.count)))
                    Text("days a week").font(.subheadline).foregroundStyle(BoxStyle.muted)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.selectedDays.count)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(days, id: \.id) { day in
                        let selected = store.selectedDays.contains(day.id)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { store.selectedDays.formSymmetricDifference([day.id]) }
                            BoxHaptics.selection()
                        } label: {
                            HStack {
                                Text(day.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected ? .white : BoxStyle.dim)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .foregroundStyle(selected ? .white : BoxStyle.ink)
                            .padding(16).frame(minHeight: 60)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(selected ? AnyShapeStyle(BoxStyle.heroGradient) : AnyShapeStyle(BoxStyle.surface))
                                    .shadow(color: selected ? BoxStyle.accent.opacity(0.35) : .clear, radius: 10, y: 6)
                            }
                            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? .white.opacity(0.2) : BoxStyle.border) }
                        }
                        .buttonStyle(BoxPressStyle(scale: 0.95))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Text("Saved on this device. Your plan uses these training days. Reminders are not enabled.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }
        .boxScreen()
        .navigationTitle("Your training days").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
