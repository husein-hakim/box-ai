import SwiftUI
import UniformTypeIdentifiers

struct UnavailableFeatureView: View {
    let title: LocalizedStringResource
    let symbol: String
    let description: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BoxIconWell(symbol: symbol, size: 56).padding(.top, 24)
                Text(title).boxDisplay(40)
                Text(description).font(.title3).foregroundStyle(BoxStyle.muted)
                BoxChip(text: "Coming later", color: BoxStyle.accent)
                Text(detail).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.boxPage().frame(maxWidth: .infinity, alignment: .leading)
        }
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle(Text(title)).navigationBarTitleDisplayMode(.inline)
    }
}

private enum ProgressLog: String, CaseIterable { case practices = "Practices", workouts = "Workouts" }

struct ProgressViewScreen: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    @State private var log: ProgressLog = .practices
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    BoxPageHeader(title: "Progress", subtitle: "The work you've actually logged.")
                    GlassIconButton(symbol: "person.fill", label: "Profile and settings") { sheet = .settings }
                        .foregroundStyle(BoxStyle.ink)
                }.boxEntrance()
                WeeklyWorkChart(history: store.history).boxEntrance(1)
                ProgressMetrics(practices: store.history.count, activeDays: store.activeDays(), streak: store.activityStreak()).boxEntrance(2)
                BoxSegmented(options: ProgressLog.allCases, selection: $log, title: { $0 == .practices ? "Practices" : "Workouts" })
                    .padding(.top, 12).boxEntrance(3)
                Group {
                    if log == .practices {
                        if store.history.isEmpty {
                            BoxEmptyState(symbol: "figure.boxing", title: "Your first round starts here.", detail: "Saved sessions appear here with the work you completed and the observations actually measured.")
                        } else {
                            BoxRowGroup {
                                ForEach(store.history) { record in
                                    NavigationLink { PracticeHistoryDetail(record: record) } label: { PracticeHistoryRow(record: record) }
                                        .buttonStyle(BoxPressStyle(scale: 0.985))
                                }
                            }
                        }
                    } else {
                        if store.workouts.isEmpty {
                            BoxEmptyState(symbol: "dumbbell", title: "Make room for stronger rounds.", detail: "Workouts logged outside the guided player appear here. Guided workouts stay in Practices.")
                        } else {
                            BoxRowGroup {
                                ForEach(store.workouts) { workout in
                                    VStack(alignment: .leading, spacing: 0) {
                                        BoxRow(symbol: "dumbbell.fill", color: BoxStyle.strength, title: workout.title,
                                               subtitle: "\(workout.date.formatted(.dateTime.month(.abbreviated).day())) · \(workout.exerciseIDs.count) exercises · Self-reported",
                                               showsChevron: false)
                                        if !workout.notes.isEmpty {
                                            Text(workout.notes).font(.caption).foregroundStyle(BoxStyle.muted)
                                                .padding(.leading, 66).padding(.trailing, 14).padding(.bottom, 12)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
                .boxEntrance(4)
            }
            .boxPage()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: log)
        }.boxScreen().foregroundStyle(BoxStyle.ink)
            .navigationTitle("Progress").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
    }
}

/// Timed work per day for the current week, from saved sessions only.
private struct WeeklyWorkChart: View {
    let history: [SessionRecord]
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let days = CalendarDay.currentWeek()
        let totals = days.map { day in history.filter { Calendar.current.isDate($0.date, inSameDayAs: day.date) }.reduce(0) { $0 + $1.workSeconds } }
        let week = totals.reduce(0, +)
        let peak = max(totals.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 0) {
            Text("Timed work · this week").boxEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Duration.seconds(week).formatted(.time(pattern: .minuteSecond))).boxNumber(54, relativeTo: .largeTitle)
                Text("min:sec").font(.caption).foregroundStyle(BoxStyle.muted)
            }.padding(.top, 6)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(totals[index] > 0 ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.27, blue: 0.23), Color(red: 0.62, green: 0.07, blue: 0.09)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.08)))
                            .frame(height: totals[index] > 0 ? max(10, 92 * (grown || reduceMotion ? totals[index] / peak : 0.02)) : 8)
                            .shadow(color: isToday && totals[index] > 0 ? BoxStyle.accent.opacity(0.5) : .clear, radius: 10)
                            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.75).delay(Double(index) * 0.05), value: grown)
                        Text(day.date, format: .dateTime.weekday(.narrow)).font(.caption2.weight(.semibold))
                            .foregroundStyle(isToday ? BoxStyle.ink : BoxStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 118).padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timed work per day this week")
        }
        .boxPanel(padding: 18)
        .onAppear { grown = true }
    }
}

private struct ProgressMetrics: View {
    let practices: Int
    let activeDays: Int
    let streak: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            metric(practices, "Practices", BoxStyle.ink)
            metric(activeDays, "Active · 7d", BoxStyle.ink)
            metric(streak, "Day streak", BoxStyle.strength)
        }
    }
    private func metric(_ value: Int, _ label: LocalizedStringResource, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .number).boxNumber(30).foregroundStyle(color).contentTransition(.numericText(value: Double(value)))
            Text(label).boxEyebrow().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).boxPanel(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

private struct PracticeHistoryRow: View {
    let record: SessionRecord
    var body: some View {
        let title = record.pad?.configuration.title ?? record.guided?.title ?? String(localized: record.focus.title)
        let date = record.date.formatted(.dateTime.month(.abbreviated).day())
        BoxRow(symbol: record.pad != nil ? "camera.viewfinder" : record.guided != nil ? "list.bullet.rectangle" : "waveform",
               color: record.finished ? BoxStyle.accent : BoxStyle.muted,
               title: title,
               subtitle: "\(date) · \(record.finished ? String(localized: "Completed") : String(localized: "Partial practice"))") {
            Text(Duration.seconds(Int(record.workSeconds)).formatted(.time(pattern: .minuteSecond))).boxNumber(17).foregroundStyle(BoxStyle.ink)
        }
    }
}

private struct PracticeHistoryDetail: View {
    let record: SessionRecord
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(record.date, format: .dateTime.weekday(.wide).month().day().hour().minute()).boxEyebrow(.white.opacity(0.85))
                    Text("Session recap").boxDisplay(38, relativeTo: .title).padding(.top, 10)
                    HStack(spacing: 0) {
                        recapStat(Duration.seconds(Int(record.workSeconds)).formatted(.time(pattern: .minuteSecond)), "Timed work")
                        Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                        recapStat(record.completedRounds.formatted(), "Full rounds")
                        Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                        recapStat(record.finished ? "✓" : "–", record.finished ? "Completed" : "Partial")
                    }.fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                }.boxHero().boxEntrance()
                if let pad = record.pad {
                    PadResultSummary(state: pad)
                } else if let summary = record.guided {
                    BoxSectionHeader(title: "\(summary.title)") {
                        Text("\(summary.completed) complete · \(summary.partial) partial · \(summary.skipped) skipped")
                    }
                    ForEach(Array(summary.execution.session.activities.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(ActivityCatalog.find(item.activityID)?.title ?? item.activityID).font(.headline)
                                Spacer()
                                OutcomeChip(raw: summary.execution.outcome(at: index).rawValue)
                            }
                            Text("\(summary.execution.results[index].confirmedSets) / \(item.sets) sets · \(Int(summary.execution.results[index].timedSeconds)) sec work")
                                .font(.caption).foregroundStyle(BoxStyle.muted)
                            CameraBlockResults(result: summary.execution.results[index])
                        }.frame(maxWidth: .infinity, alignment: .leading).boxPanel()
                    }
                    if let feedback = summary.feedback, !feedback.isEmpty { Text(feedback).font(.subheadline).boxPanel() }
                    Text("Guided sets use your check-ins. Camera observations are experimental and separate from interval completion.")
                        .font(.caption).foregroundStyle(BoxStyle.muted)
                } else {
                    BoxRowGroup {
                        BoxRow(symbol: "waveform", title: String(localized: record.focus.title), subtitle: String(localized: "Audio and timer activity · Unscored"), showsChevron: false)
                        BoxRow(symbol: "megaphone.fill", color: BoxStyle.strength, title: String(localized: "Cues"), showsChevron: false) {
                            Text(record.issuedCues.formatted()).boxNumber(18).foregroundStyle(BoxStyle.ink)
                        }
                    }
                }
            }.boxPage()
        }.boxScreen().foregroundStyle(BoxStyle.ink)
            .navigationTitle("Recap").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

@MainActor private func recapStat(_ value: String, _ label: LocalizedStringResource) -> some View {
    VStack(spacing: 2) {
        Text(verbatim: value).boxNumber(26)
        Text(label).font(.caption2).foregroundStyle(.white.opacity(0.8))
    }.frame(maxWidth: .infinity)
}

/// Completed / partial / skipped status in pillar colors.
struct OutcomeChip: View {
    let raw: String
    var body: some View {
        switch raw {
        case "completed", "complete": BoxChip(text: "Completed", symbol: "checkmark", color: BoxStyle.conditioning)
        case "partial": BoxChip(text: "Partial", color: BoxStyle.strength)
        case "skipped": BoxChip(text: "Skipped", color: BoxStyle.muted)
        case "notStarted": BoxChip(text: "Not started", color: BoxStyle.muted)
        default: BoxValueChip(text: raw.capitalized)
        }
    }
}

struct SettingsSheet: View {
    @Bindable var store: AppStore
    @State private var confirmReset = false
    @State private var editingProfile = false
    @State private var cameraDiagnostics = false
    @State private var export: RecordsDocument?
    @State private var exporting = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Text(verbatim: String(store.profile.name.first ?? "B")).boxDisplay(26, relativeTo: .title2)
                        .frame(width: 60, height: 60)
                        .background(.black.opacity(0.22), in: .circle)
                        .overlay { Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.profile.name.isEmpty ? "Your boxing. Your pace." : store.profile.name).boxDisplay(28, relativeTo: .title2)
                        Text(store.profile.experience + " · " + store.stance).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        Text(store.profile.goal).font(.caption).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .boxHero(padding: 18, ropes: false)
                .listRowInsets(EdgeInsets())
                .accessibilityElement(children: .combine)
            }.listRowBackground(Color.clear)

            Section("Training") {
                Button("Edit training profile") { editingProfile = true }
                Toggle("Spoken cues", isOn: $store.voiceEnabled)
                Picker("Stance", selection: $store.stance) {
                    Text("Not set").tag("Not set")
                    Text("Orthodox").tag("Orthodox")
                    Text("Southpaw").tag("Southpaw")
                    Text("Not sure").tag("Not sure")
                }
                Text("Cues use lead and rear hands, so you can follow them in either stance.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
            }
            Section("About BOX") {
                DisclosureGroup("Feature status") {
                LabeledContent("Guided rounds", value: "Available")
                LabeledContent("Spoken cues", value: "Available")
                LabeledContent("Camera capture", value: "Available · Unscored")
                LabeledContent("Movement recognition", value: "Jab/cross camera practice · Beta")
                LabeledContent("Video playback", value: "Local clips & notes")
                LabeledContent("Coach & meal AI", value: QwenClient().isConfigured ? "Ready" : "Setup pending")
                Text("BOX is a working title. Sample boxing content needs coach review. This app does not assess your technique yet.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
                }
            }
            Section("Advanced") { Button("Camera diagnostics", systemImage: "viewfinder") { cameraDiagnostics = true } }
            Section("Subscription") { NavigationLink("Subscription & purchases") { SubscriptionView() } }
            Section("Your data") {
                Text("Your profile, practices, meals, water, plans, workouts, chat and clip records use local SwiftData. Video files stay in local app storage. No cloud backup or subscription is connected. Explicit AI requests send the disclosed context for AI analysis.")
                    .font(.subheadline).foregroundStyle(BoxStyle.muted)
                Button("Export records (JSON)") {
                    do { export = RecordsDocument(data: try store.exportRecords()); exporting = true }
                    catch { store.storageNotice = "Your records could not be exported. Please try again." }
                }
                Text("Export includes profile, training, food, chat and clip annotations. Video files are not included. Restore/import is not available yet.").font(.footnote).foregroundStyle(BoxStyle.muted)
                Button("Reset local data", role: .destructive) { confirmReset = true }
            }
        }
        .boxFormStyle()
        .navigationTitle("Profile & settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { DismissButton() } }
        .fileExporter(isPresented: $exporting, document: export, contentType: .json, defaultFilename: "BOX-records") { result in
            if case .failure = result { store.storageNotice = "Export could not be saved. Please try again." }
            export = nil
        }
        .fullScreenCover(isPresented: $cameraDiagnostics) { CameraValidationView(store: store) }
        .sheet(isPresented: $editingProfile) { NavigationStack { TrainingProfileEditor(store: store) } }
        .confirmationDialog("Erase this device’s training data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Erase local data", role: .destructive) { store.resetLocalData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes your profile, practices, plans, workouts, meals, water, targets, chat and video files. It cannot be undone.")
        }
    }
}

private struct RecordsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
