import SwiftUI

struct TodayView: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    @Binding var selectedTab: AppTab

    private var trainedDays: Set<Date> {
        Set(store.history.map { Calendar.current.startOfDay(for: $0.date) })
    }

    var body: some View {
        let assignment = store.plan.first { Calendar.current.isDateInToday($0.date) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TodayHeader { sheet = .settings }.boxEntrance()
                WeekStrip(selectedDays: store.selectedDays, trainedDays: trainedDays) { sheet = .schedule }.boxEntrance(1)
                if let pending = store.pendingSession {
                    Button { store.activeSession = pending } label: {
                        Label("Continue saved practice", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(BoxSecondaryStyle()).boxEntrance(2)
                }
                Group {
                    if let assignment, let session = assignment.session {
                        AssignmentHero(store: store, assignment: assignment, session: session)
                    } else if assignment?.sessionData != nil {
                        BoxInlineNotice(text: "Today's saved session could not be opened. Its data has been kept; you can still use the drill library.", symbol: "exclamationmark.triangle", color: BoxStyle.strength)
                    } else {
                        TodaySessionCard(configuration: assignment?.configuration ?? .init(), focus: assignment?.focus) {
                            if let assignment { store.startAssignment(assignment) } else { store.start() }
                        }
                    }
                }.boxEntrance(2)
                TodayStats(store: store).boxEntrance(3)
                TodayChecklist(store: store, assignment: assignment, selectedTab: $selectedTab).boxEntrance(4)
                SessionShortcuts(store: store, build: { sheet = .builder }, coach: { sheet = .coach }).boxEntrance(5)
                if let notice = store.storageNotice {
                    BoxInlineNotice(text: "\(notice)", symbol: "exclamationmark.triangle", color: BoxStyle.accent)
                }
            }
            .boxPage()
        }
        .boxScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Header

private struct TodayHeader: View {
    let openProfile: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BOX").font(.system(size: 24, weight: .black).width(.compressed)).modifier(BoxOblique())
                        .tracking(1).foregroundStyle(BoxStyle.accent)
                        .accessibilityAddTraits(.isHeader)
                    Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide)).boxEyebrow()
                }
                Spacer()
                GlassIconButton(symbol: "person.fill", label: "Profile and settings", action: openProfile)
                    .foregroundStyle(BoxStyle.ink)
            }
            Text("Your next\nround.").boxDisplay(50)
                .foregroundStyle(BoxStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Week

struct CalendarDay: Identifiable {
    let date: Date
    let weekday: Int
    var id: Date { date }

    static func currentWeek() -> [CalendarDay] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return CalendarDay(date: date, weekday: calendar.component(.weekday, from: date))
        }
    }
}

struct WeekStrip: View {
    let selectedDays: Set<Int>
    var trainedDays: Set<Date> = []
    let edit: () -> Void
    private let days = CalendarDay.currentWeek()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            BoxSectionHeader(title: "This week") {
                Button(action: edit) {
                    HStack(spacing: 3) {
                        Text(selectedDays.isEmpty ? "Set days" : "Edit days")
                        Image(systemName: "chevron.right").font(.caption2.bold())
                    }.foregroundStyle(BoxStyle.accent)
                }
                .frame(minHeight: 44)
            }
            Group {
                if typeSize.isAccessibilitySize {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { cells.frame(minWidth: 64) }
                    }
                } else {
                    HStack(spacing: 6) { cells }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Current week")
        }
    }

    private var cells: some View {
        ForEach(days) { day in
            WeekDayCell(day: day, isScheduled: selectedDays.contains(day.weekday), trained: trainedDays.contains(Calendar.current.startOfDay(for: day.date)))
        }
    }
}

private struct WeekDayCell: View {
    let day: CalendarDay
    let isScheduled: Bool
    let trained: Bool
    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 4) {
            Text(day.date, format: .dateTime.weekday(.narrow))
                .font(.caption2.weight(.semibold)).foregroundStyle(isToday ? BoxStyle.accent : BoxStyle.dim)
            Text(day.date, format: .dateTime.day()).boxNumber(20, relativeTo: .headline)
                .foregroundStyle(BoxStyle.ink)
            Circle().fill(trained ? BoxStyle.accent : isScheduled ? BoxStyle.dim : .clear).frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
        .background {
            if isToday {
                shape.fill(LinearGradient(colors: [BoxStyle.accent.opacity(0.28), BoxStyle.accent.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(BoxStyle.surface)
            }
        }
        .overlay { shape.strokeBorder(isToday ? BoxStyle.accent.opacity(0.65) : BoxStyle.border, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).month().day()))
        .accessibilityValue(trained ? Text("Trained") : isScheduled ? Text("Scheduled training day") : Text("No training scheduled"))
        .accessibilityAddTraits(isToday ? .isSelected : [])
    }
}

// MARK: - Hero

private struct TodaySessionCard: View {
    let configuration: RoundConfiguration
    let focus: TrainingFocus?
    let start: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Today · Reaction training", systemImage: "waveform").boxEyebrow(.white.opacity(0.85))
            Text("Read. React.\nReset.").boxDisplay(40, relativeTo: .title)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text(focus?.title ?? "Hear the cue. Make your move.").font(.subheadline).foregroundStyle(.white.opacity(0.82))
                .padding(.top, 6)
            HStack(spacing: 6) {
                BoxValueChip(text: Duration.seconds(configuration.totalSeconds).formatted(.time(pattern: .minuteSecond)) + " min", onHero: true)
                BoxValueChip(text: String(localized: "\(configuration.rounds) rounds"), onHero: true)
                BoxChip(text: "No equipment", onHero: true)
            }.padding(.top, 14)
            Button(action: start) {
                Label("Start session", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(BoxHeroButtonStyle())
            .accessibilityIdentifier("today.start")
            .padding(.top, 18)
            Text("Guided audio · Unscored").font(.caption2).foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity).padding(.top, 10)
        }
        .boxHero()
    }
}

private struct AssignmentHero: View {
    let store: AppStore
    let assignment: PlannedPractice
    let session: GuidedSession
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Today · Your plan", systemImage: "calendar").boxEyebrow(.white.opacity(0.85))
            Text(session.title).boxDisplay(38, relativeTo: .title)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            HStack(spacing: 6) {
                BoxValueChip(text: String(localized: "\(session.activities.count) activities"), onHero: true)
                BoxValueChip(text: Duration.seconds(session.estimatedSeconds).formatted(.time(pattern: .minuteSecond)) + " min", onHero: true)
            }.padding(.top, 14)
            Group {
                if session.activities.isEmpty {
                    Label("Rest & recover · No guided work prescribed", systemImage: "moon.fill")
                        .font(.subheadline.weight(.semibold)).padding(.top, 18)
                } else if store.assignmentIsComplete(assignment) {
                    Label("Completed · Saved to Progress", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).padding(.top, 18)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if let progress = store.assignmentProgress(assignment) { Text(progress).font(.caption).foregroundStyle(.white.opacity(0.8)) }
                        if assignment.completionID != nil { Text("Partial attempt saved in Progress").font(.caption).foregroundStyle(.white.opacity(0.8)) }
                        Button { store.startAssignment(assignment) } label: {
                            Label(store.pendingSession?.assignmentID == assignment.id ? "Resume session" : assignment.completionID == nil ? "Start session" : "Repeat session", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(BoxHeroButtonStyle())
                    }.padding(.top, 18)
                }
            }
        }
        .boxHero()
    }
}

// MARK: - Stats

private struct TodayStats: View {
    let store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let streak = store.activityStreak()
        let active = store.activeDays()
        let goal = max(store.selectedDays.count, 1)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            BoxStatTile(label: "Streak", value: streak.formatted(), unit: streak == 1 ? "day" : "days", symbol: "flame.fill", color: BoxStyle.strength,
                        caption: streak == 0 ? "Train today to start one" : "Keep it alive today")
            BoxStatTile(label: "Last 7 days", value: active.formatted(), unit: "/ \(goal) days", symbol: "calendar", color: BoxStyle.accent,
                        progress: Double(active) / Double(goal))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Checklist

private struct TodayChecklist: View {
    let store: AppStore
    let assignment: PlannedPractice?
    @Binding var selectedTab: AppTab
    @State private var waterBump = 0

    var body: some View {
        let trained = store.history.contains { Calendar.current.isDateInToday($0.date) }
        let meals = store.meals(on: .now)
        let water = store.totals(on: .now).water
        let waterTarget = store.targets.water
        let waterDone = waterTarget > 0 && water >= waterTarget
        let done = [trained, !meals.isEmpty, waterDone].filter { $0 }.count
        VStack(spacing: 12) {
            BoxSectionHeader(title: "Today's checklist") {
                Text("\(done) of 3 done")
            }
            BoxRowGroup {
                Button {
                    if let assignment { store.startAssignment(assignment) } else { store.start() }
                } label: {
                    ChecklistRow(done: trained, symbol: "figure.boxing", color: BoxStyle.accent,
                                 title: String(localized: "Train today"),
                                 subtitle: trained ? String(localized: "Saved to Progress") : String(localized: "Start today's session"))
                }.buttonStyle(BoxPressStyle(scale: 0.985))
                Button { selectedTab = .fuel } label: {
                    ChecklistRow(done: !meals.isEmpty, symbol: "fork.knife", color: BoxStyle.strength,
                                 title: String(localized: "Log your meals"),
                                 subtitle: meals.isEmpty ? String(localized: "Nothing logged yet") : String(localized: "\(meals.count) logged today"))
                }.buttonStyle(BoxPressStyle(scale: 0.985))
                HStack(spacing: 0) {
                    ChecklistRow(done: waterDone, symbol: "drop.fill", color: BoxStyle.timer,
                                 title: String(localized: "Drink water"),
                                 subtitle: waterTarget > 0 ? String(localized: "\(water) of \(waterTarget) ml") : String(localized: "\(water) ml logged"),
                                 showsChevron: false)
                    Button {
                        if store.addWater(250, date: .now) { waterBump += 1; BoxHaptics.success() }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                            .symbolEffect(.bounce, value: waterBump)
                            .frame(width: 36, height: 36)
                            .background(BoxStyle.timer.opacity(0.15), in: .circle)
                            .overlay { Circle().strokeBorder(BoxStyle.timer.opacity(0.3)) }
                            .foregroundStyle(BoxStyle.timer)
                    }
                    .buttonStyle(BoxPressStyle(scale: 0.88))
                    .accessibilityLabel("Add 250 ml of water")
                    .padding(.trailing, 14)
                }
            }
        }
    }
}

private struct ChecklistRow: View {
    let done: Bool
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    var showsChevron = true
    var body: some View {
        BoxRow(symbol: done ? "checkmark" : symbol, color: done ? BoxStyle.conditioning : color,
               title: title, subtitle: subtitle, showsChevron: showsChevron && !done)
            .opacity(done ? 0.75 : 1)
            .accessibilityValue(done ? Text("Done") : Text("Not done"))
    }
}

// MARK: - Shortcuts

private struct SessionShortcuts: View {
    let store: AppStore
    let build: () -> Void
    let coach: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BoxSectionHeader(title: "Make it your session")
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                Button(action: build) {
                    BoxActionTile(title: "Build a session", subtitle: "Your pace, your rounds", symbol: "slider.horizontal.3", color: BoxStyle.timer)
                }.buttonStyle(BoxPressStyle())
                NavigationLink { DrillLibraryView(store: store) } label: {
                    BoxActionTile(title: "Drill library", subtitle: "Start with the basics", symbol: "square.grid.2x2.fill")
                }.buttonStyle(BoxPressStyle())
            }
            Button(action: coach) {
                BoxRow(symbol: "bubble.left.and.text.bubble.right.fill", color: BoxStyle.coach,
                       title: String(localized: "A question for your coach?"), subtitle: String(localized: "Talk through your training"))
                    .boxPanel(padding: 0, tint: BoxStyle.coach)
            }.buttonStyle(BoxPressStyle())
        }
    }
}

struct ShortcutLabel: View {
    let symbol: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    var color: Color = BoxStyle.accent
    var body: some View {
        BoxActionTile(title: title, subtitle: subtitle, symbol: symbol, color: color)
    }
}
