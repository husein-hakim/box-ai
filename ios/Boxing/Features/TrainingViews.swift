import SwiftUI

private enum TrainDiscipline: String, CaseIterable { case boxing, strength }

struct TrainView: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    @Binding var selectedTab: AppTab
    @State private var discipline: TrainDiscipline = .boxing
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    BoxPageHeader(title: "Train", subtitle: "Pick a practice. Put in the rounds.")
                    GlassPillButton(title: "History", symbol: "clock.arrow.circlepath") { selectedTab = .progress }
                }.boxEntrance()
                BoxSegmented(options: TrainDiscipline.allCases, selection: $discipline,
                             title: { $0 == .boxing ? "Boxing" : "Strength" },
                             symbol: { $0 == .boxing ? "figure.boxing" : "dumbbell.fill" })
                    .boxEntrance(1)
                Group {
                    if discipline == .boxing { boxing } else { strength }
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .boxPage()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: discipline)
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Train").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var boxing: some View {
        VStack(alignment: .leading, spacing: 10) {
            CameraTrainingCard(store: store).boxEntrance(2)
            NavigationLink { WeeklyPlanView(store: store, sheet: $sheet) } label: {
                TrainingPlanRow(store: store)
            }.buttonStyle(BoxPressStyle()).boxEntrance(3)
            BoxSectionHeader(title: "Training tools").padding(.top, 14)
            LazyVGrid(columns: columns, spacing: 10) {
                Button { sheet = .builder } label: {
                    BoxActionTile(title: "Guided rounds", subtitle: "Bell, rounds & spoken cues", symbol: "timer", color: BoxStyle.timer)
                }.buttonStyle(BoxPressStyle())
                NavigationLink { DrillLibraryView(store: store) } label: {
                    BoxActionTile(title: "Drill library", subtitle: "Punches, movement & defense", symbol: "square.grid.2x2.fill")
                }.buttonStyle(BoxPressStyle())
                NavigationLink { WorkoutLibraryView(store: store) } label: {
                    BoxActionTile(title: "Workouts", subtitle: "Strength, core & conditioning", symbol: "dumbbell.fill", color: BoxStyle.strength)
                }.buttonStyle(BoxPressStyle())
                Button { sheet = .coach } label: {
                    BoxActionTile(title: "Coach", subtitle: "Questions & training advice", symbol: "bubble.left.and.text.bubble.right.fill", color: BoxStyle.coach)
                }.buttonStyle(BoxPressStyle())
            }.boxEntrance(4)
        }
    }

    @ViewBuilder private var strength: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Label("Strength & conditioning", systemImage: "dumbbell.fill").boxEyebrow(.white.opacity(0.85))
                Text("Build the\nengine.").boxDisplay(38, relativeTo: .title).padding(.top, 10)
                Text("Guided workouts with timed sets, rest and check-ins.").font(.subheadline).foregroundStyle(.white.opacity(0.82))
                    .padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                NavigationLink { WorkoutLibraryView(store: store) } label: {
                    Label("Choose a workout", systemImage: "play.fill")
                }.buttonStyle(BoxHeroButtonStyle()).padding(.top, 18)
            }.boxHero()
            BoxSectionHeader(title: "Strength tools").padding(.top, 14)
            LazyVGrid(columns: columns, spacing: 10) {
                NavigationLink { ActivityLibraryView(store: store) } label: {
                    BoxActionTile(title: "Exercise library", subtitle: "Strength, core & mobility", symbol: "figure.strengthtraining.functional", color: BoxStyle.strength)
                }.buttonStyle(BoxPressStyle())
                NavigationLink { WeeklyPlanView(store: store, sheet: $sheet) } label: {
                    BoxActionTile(title: "Your plan", subtitle: "Sessions & recovery days", symbol: "calendar", color: BoxStyle.conditioning)
                }.buttonStyle(BoxPressStyle())
                Button { sheet = .coach } label: {
                    BoxActionTile(title: "Coach", subtitle: "Ask about a workout", symbol: "bubble.left.and.text.bubble.right.fill", color: BoxStyle.coach)
                }.buttonStyle(BoxPressStyle())
                Button { selectedTab = .progress } label: {
                    BoxActionTile(title: "Logged work", subtitle: "Workouts in Progress", symbol: "chart.bar.fill", color: BoxStyle.timer)
                }.buttonStyle(BoxPressStyle())
            }
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

private struct CameraTrainingCard: View {
    let store: AppStore
    var body: some View {
        let last = store.history.first { $0.pad != nil }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Camera · Live pads", systemImage: "camera.viewfinder").boxEyebrow(.white.opacity(0.85))
                    Text("See it.\nSend it.").boxDisplay(38, relativeTo: .title).padding(.top, 10)
                    Text("React to jab and cross cues. Reset, then go again.").font(.subheadline).foregroundStyle(.white.opacity(0.82))
                        .padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                BoxChip(text: "Beta", onHero: true)
            }
            NavigationLink { PadTrainingSetupView(store: store, activityID: nil) } label: {
                Label(last == nil ? "Start camera practice" : "Go again", systemImage: "play.fill")
            }.buttonStyle(BoxHeroButtonStyle()).padding(.top, 18)
            Text(last.map { String(localized: "Last session · \($0.date.formatted(.dateTime.month(.abbreviated).day()))") } ?? String(localized: "Experimental recognition · Noncontact"))
                .font(.caption2).foregroundStyle(.white.opacity(0.7)).padding(.top, 10)
        }.boxHero()
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
