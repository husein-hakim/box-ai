import SwiftUI

struct TrainingProfileEditor: View {
    let store: AppStore
    @State private var name = ""
    @State private var experience = "Beginner"
    @State private var goal = "Build consistency"
    @State private var equipment: Set<String> = []
    @State private var space = "Small indoor space"
    @State private var minutes = 10
    @State private var seeded = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("About you") {
                TextField("Name (optional)", text: $name)
                Picker("Experience", selection: $experience) { ForEach(["Beginner", "Some experience", "Experienced"], id: \.self) { Text($0).tag($0) } }
                Picker("Goal", selection: $goal) { ForEach(["Build consistency", "Straight punches", "Conditioning", "General boxing"], id: \.self) { Text($0).tag($0) } }
            }
            Section("Your setup") {
                Picker("Space", selection: $space) { ForEach(["Small indoor space", "Larger indoor space", "Outdoor space"], id: \.self) { Text($0).tag($0) } }
                ForEach(["Heavy bag", "Focus pads", "Pad partner", "Gloves", "Hand wraps", "Skipping rope", "Dumbbells", "Stable wall", "Outdoor space"], id: \.self) { item in
                    Toggle(item, isOn: Binding(get: { equipment.contains(item) }, set: { if $0 { equipment.insert(item) } else { equipment.remove(item) } }))
                }
                Stepper("Session budget: \(minutes) min", value: $minutes, in: 4...60, step: 1)
            }
            Section {
                Text("Your coach uses this setup, your stance, training days and recent completion history to propose training. You review and accept each plan. Timers and check-ins do not measure boxing ability.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .boxFormStyle()
        .navigationTitle("Training profile").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if store.saveProfile(name: name, experience: experience, goal: goal, equipment: equipment.sorted(), space: space, minutes: minutes) { BoxHaptics.success(); dismiss() } }
            }
        }
        .onAppear {
            guard !seeded else { return }; seeded = true
            name = store.profile.name; experience = store.profile.experience; goal = store.profile.goal
            equipment = Set(store.profile.equipment); space = store.profile.space; minutes = store.profile.sessionMinutes
        }
    }
}

struct WeeklyPlanView: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    @State private var showingAI = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Your plan", subtitle: "A week that fits your life and your boxing.").boxEntrance()
                if store.selectedDays.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Step 1 · Your week", systemImage: "calendar").boxEyebrow(.white.opacity(0.85))
                        Text("Make room\nfor training.").boxDisplay(38, relativeTo: .title).padding(.top, 10)
                        Text("Choose your training days and check your setup before creating a week.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button { sheet = .schedule } label: { Label("Pick days", systemImage: "calendar").frame(maxWidth: .infinity) }.buttonStyle(BoxHeroButtonStyle())
                            Button { sheet = .profile } label: { Label("Profile", systemImage: "person.fill").frame(maxWidth: .infinity) }.buttonStyle(BoxHeroButtonStyle(kind: .ghost))
                        }.padding(.top, 18)
                    }.boxHero().boxEntrance(1)
                } else if store.plan.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Coach · Personalized plan", systemImage: "sparkles").boxEyebrow(.white.opacity(0.85))
                        Text("Your next week\nstarts here.").boxDisplay(38, relativeTo: .title).padding(.top, 10)
                        Text("Your coach proposes the sessions. You review and accept them before they appear on Today.").font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { showingAI = true } label: { Label("Create my plan", systemImage: "sparkles").frame(maxWidth: .infinity) }
                            .buttonStyle(BoxHeroButtonStyle()).padding(.top, 18)
                    }.boxHero().boxEntrance(1)
                }
                if !store.plan.isEmpty {
                    BoxSectionHeader(title: "Accepted sessions") {
                        Button("New plan", systemImage: "plus") { showingAI = true }
                            .foregroundStyle(BoxStyle.accent).frame(minHeight: 44).disabled(store.selectedDays.isEmpty)
                    }.padding(.top, 6)
                    LazyVStack(spacing: 10) {
                        ForEach(store.plan) { item in
                            PlanItemView(store: store, practice: item, isNext: item.id == store.plan.first(where: { !store.assignmentIsComplete($0) && $0.session?.activities.isEmpty != true })?.id)
                        }
                    }
                }
                DevelopmentNote(text: "Drafts require an online connection. Accepted sessions stay on this iPhone and can be followed offline. Original instructions are pending coach review; no demonstration media is available.")
            }.boxPage()
        }.boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Your plan").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Training profile", systemImage: "person.crop.circle") { sheet = .profile }
                    Button("Training days", systemImage: "calendar") { sheet = .schedule }
                } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Plan preferences")
            }
        }
        .sheet(isPresented: $showingAI) { NavigationStack { PlanProposalView(store: store) } }
    }
}

private struct PlanItemView: View {
    let store: AppStore
    let practice: PlannedPractice
    var isNext = false
    @State private var changingDate = false
    @State private var date = Date.now
    @State private var confirmingRemoval = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(practice.date, format: .dateTime.weekday(.wide).month(.abbreviated).day()).boxEyebrow(isNext ? BoxStyle.accent : BoxStyle.muted)
                Spacer()
                if store.assignmentIsComplete(practice) { BoxChip(text: "Done", symbol: "checkmark", color: BoxStyle.conditioning) }
                else if isNext { BoxChip(text: "Up next", color: BoxStyle.accent) }
            }
            Text(practice.displayTitle).boxSection(24)
            if let session = practice.session {
                Text("\(session.activities.count) activities · \(Duration.seconds(session.estimatedSeconds).formatted(.time(pattern: .minuteSecond))) work & rest")
                    .font(.subheadline).foregroundStyle(BoxStyle.muted)
                DisclosureGroup("See session sequence") {
                    VStack(alignment: .leading, spacing: 14) {
                        if !practice.note.isEmpty { Text(practice.note).font(.subheadline).foregroundStyle(BoxStyle.muted) }
                        SessionBriefing(session: session, embedded: true)
                    }.padding(.top, 12)
                }
            } else if practice.sessionData != nil {
                Text("This session could not be opened. Its saved data has been kept.").font(.subheadline).foregroundStyle(BoxStyle.muted)
            } else {
                Text("\(practice.rounds) rounds · Guided audio").font(.subheadline).foregroundStyle(BoxStyle.muted)
                Text("Earlier foundation assignment").font(.caption).foregroundStyle(BoxStyle.muted)
            }
            if practice.session == nil && !practice.note.isEmpty { Text(practice.note).font(.subheadline).foregroundStyle(BoxStyle.muted) }
            if practice.session?.activities.isEmpty == true {
                Label("Rest day · No guided work prescribed", systemImage: "moon").font(.subheadline).foregroundStyle(BoxStyle.muted)
                Button("Remove assignment", role: .destructive) { confirmingRemoval = true }
            } else if store.assignmentIsComplete(practice) {
                Label("Completed · Saved to Progress", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.conditioning)
            } else {
                if let progress = store.assignmentProgress(practice) { Text(progress).font(.caption).foregroundStyle(BoxStyle.muted) }
                if practice.completionID != nil { Text("Partial attempt saved in Progress").font(.caption).foregroundStyle(BoxStyle.muted) }
                if isNext || store.pendingSession?.assignmentID == practice.id {
                    PrimaryButton(title: store.pendingSession?.assignmentID == practice.id ? "Resume session" : practice.completionID == nil ? "Start session" : "Repeat session") { store.startAssignment(practice) }.disabled(practice.sessionData != nil && practice.session == nil)
                } else {
                    Button { store.startAssignment(practice) } label: {
                        Label(practice.completionID == nil ? "Start session" : "Repeat session", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(BoxSecondaryStyle()).disabled(practice.sessionData != nil && practice.session == nil)
                }
                Menu("Session options", systemImage: "ellipsis") {
                    if practice.sessionData == nil { Button("Reschedule") { date = practice.date; changingDate = true } }
                    if practice.completionID == nil { Button("Remove assignment", role: .destructive) { confirmingRemoval = true } }
                }.font(.caption).frame(minHeight: 44)
            }
        }
        .tint(BoxStyle.muted)
        .boxPanel(padding: 18, tint: isNext ? BoxStyle.accent : nil)
        .confirmationDialog("Remove this assignment?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove assignment", role: .destructive) { store.removePlanItem(practice) }
        }
        .sheet(isPresented: $changingDate) {
            NavigationStack {
                Form { DatePicker("Training date", selection: $date, displayedComponents: .date) }
                    .navigationTitle("Reschedule")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { changingDate = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.reschedule(practice, to: date) { changingDate = false } } }
                    }
            }.presentationDetents([.medium])
        }
    }
}

struct WorkoutLibraryView: View {
    let store: AppStore
    @State private var generating = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Workouts", subtitle: "Build the engine behind your boxing.").boxEntrance()
                VStack(alignment: .leading, spacing: 0) {
                    Label("Coach · Strength & conditioning", systemImage: "sparkles").boxEyebrow(.white.opacity(0.85))
                    Text("A workout that\nfits your setup.").boxDisplay(36, relativeTo: .title).padding(.top, 10)
                    Button { generating = true } label: { Label("Create a workout", systemImage: "sparkles").frame(maxWidth: .infinity) }
                        .buttonStyle(BoxHeroButtonStyle()).padding(.top, 18)
                }.boxHero().boxEntrance(1)
                if !store.workoutPlans.isEmpty { BoxSectionHeader(title: "Your workouts").padding(.top, 8) }
                ForEach(store.workoutPlans) { plan in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(plan.title).boxSection(22)
                        BoxChip(text: "Personalized · Accepted by you", symbol: "sparkles", color: BoxStyle.coach)
                        if let session = plan.guidedSession {
                            Button { store.start(session) } label: { Label("Start workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(BoxSecondaryStyle()).disabled(!store.sessionErrors(session).isEmpty)
                        }
                        DisclosureGroup("Workout details & options") {
                        Text(plan.reason).font(.subheadline).foregroundStyle(BoxStyle.muted)
                        ForEach(plan.routineIDs, id: \.self) { id in
                            if let routine = WorkoutRoutine.all.first(where: { $0.id == id }) {
                                NavigationLink { WorkoutDetailView(store: store, routine: routine) } label: { Text(routine.title) }
                            }
                        }
                        Button("Remove plan", role: .destructive) { store.deleteWorkoutPlan(plan) }.frame(minHeight: 44)
                        }.font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
                    }.boxPanel(padding: 18, tint: BoxStyle.strength)
                }
                NavigationLink { ActivityLibraryView(store: store) } label: {
                    BoxRow(symbol: "square.grid.2x2.fill", color: BoxStyle.strength, title: String(localized: "Exercise library"),
                           subtitle: String(localized: "Strength, core, conditioning and mobility"))
                        .boxPanel(padding: 0, tint: BoxStyle.strength)
                }.buttonStyle(BoxPressStyle())
                BoxSectionHeader(title: "Ready to follow") { Text("\(WorkoutRoutine.all.count)") }.padding(.top, 8)
                BoxRowGroup {
                    ForEach(WorkoutRoutine.all) { routine in
                        NavigationLink { WorkoutDetailView(store: store, routine: routine) } label: {
                            BoxRow(symbol: "dumbbell.fill", color: BoxStyle.strength, title: String(localized: routine.title),
                                   subtitle: "\(String(localized: routine.category)) · \(routine.equipmentDescription)")
                        }.buttonStyle(BoxPressStyle(scale: 0.985))
                    }
                }
                DevelopmentNote(text: "Original routines pending coach review. Follow a comfortable pace and stop if a movement hurts. Check off only work you actually completed.")
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Workouts").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $generating) { NavigationStack { WorkoutProposalView(store: store) } }
    }
}

private struct WorkoutDetailView: View {
    let store: AppStore
    let routine: WorkoutRoutine
    @State private var completed: Set<String> = []
    @State private var saved = false
    @State private var notes = ""
    @State private var seeded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let errors = store.sessionErrors(routine.guidedSession)
                VStack(alignment: .leading, spacing: 0) {
                    Label("Workout · \(String(localized: routine.category))", systemImage: "dumbbell.fill").boxEyebrow(.white.opacity(0.85))
                    Text(routine.title).boxDisplay(38, relativeTo: .title).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        BoxValueChip(text: String(localized: "About \(routine.estimatedMinutes) min"), onHero: true)
                        BoxValueChip(text: String(localized: "\(routine.exercises.count) exercises"), onHero: true)
                    }.padding(.top, 14)
                    Button { store.start(routine.guidedSession) } label: { Label("Start guided workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(BoxHeroButtonStyle()).disabled(!errors.isEmpty).opacity(errors.isEmpty ? 1 : 0.5).padding(.top, 18)
                }.boxHero().boxEntrance()
                if !errors.isEmpty { BoxInlineNotice(text: "\(errors.joined(separator: "\n"))", symbol: "exclamationmark.triangle", color: BoxStyle.strength) }
                BoxSectionHeader(title: "The sequence").padding(.top, 8)
                SessionBriefing(session: routine.guidedSession).boxEntrance(1)
                DisclosureGroup("Log a workout done separately") {
                Text("Use this checklist for work you completed outside the guided session.").font(.caption).foregroundStyle(BoxStyle.muted).padding(.top, 12)
                if let equipment = routine.equipment, !store.profile.equipment.contains(equipment) {
                    Text("This routine needs \(equipment). Your profile doesn't list it yet.").font(.subheadline).foregroundStyle(BoxStyle.muted).boxPanel()
                }
                ForEach(routine.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(exercise.title).font(.headline)
                        Text(exercise.prescription).font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.strength)
                        Text(exercise.instruction).font(.subheadline).foregroundStyle(BoxStyle.muted)
                        Toggle("I completed this", isOn: Binding(get: { completed.contains(exercise.id) }, set: {
                            if $0 { completed.insert(exercise.id) } else { completed.remove(exercise.id) }
                            saved = false
                            store.saveWorkoutDraft(routine, exerciseIDs: completed, notes: notes)
                        })).disabled(saved).tint(BoxStyle.conditioning)
                    }.boxPanel()
                }
                TextField("Notes, sets or reps you completed", text: $notes, axis: .vertical).lineLimit(3...8).padding().background(BoxStyle.surface, in: .rect(cornerRadius: 16)).disabled(saved)
                PrimaryButton(title: saved ? "Saved to Progress" : "Save completed work", symbol: "checkmark") {
                    saved = store.completeWorkout(routine, exerciseIDs: completed, notes: notes)
                    if saved { BoxHaptics.success() }
                }.disabled(completed.isEmpty || saved)
                Text("You can save a partial workout. Only checked exercises are recorded. Your checklist and notes are saved locally so you can resume. For timed intervals and set-by-set guidance, use Start guided workout above.")
                    .font(.footnote).foregroundStyle(BoxStyle.muted)
                }.font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Workout").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onAppear {
            guard !seeded else { return }; seeded = true
            if let draft = store.workoutDrafts.first(where: { $0.routineID == routine.id }) { completed = Set(draft.exerciseIDs); notes = draft.notes }
        }
        .onChange(of: notes) { _, _ in if seeded && !saved { store.saveWorkoutDraft(routine, exerciseIDs: completed, notes: notes) } }
    }
}

private struct PlanProposalView: View {
    let store: AppStore
    @State private var working = false
    @State private var proposal: TrainingPlanProposal?
    @State private var generatedContext: PlanningContext?
    @State private var startDate = Date.now
    @State private var feedback = ""
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Build your week", subtitle: "Personal training. Reviewed by you.")
                BoxInlineNotice(text: "Generating shares your training profile, stance, schedule, recent completion and feedback with the AI coach. Nothing changes until you accept.", symbol: "sparkles", color: BoxStyle.coach)
                DatePicker("Starting", selection: $startDate, in: Date.now..., displayedComponents: .date).tint(BoxStyle.ink).disabled(working)
                    .font(.subheadline.weight(.semibold)).boxPanel(padding: 12)
                TextField("Anything to adjust? Easier pace, focus, feedback…", text: $feedback, axis: .vertical)
                    .lineLimit(3...6).padding(16).background(BoxStyle.surface, in: .rect(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(BoxStyle.border) }.disabled(working)
                if working {
                    HStack(spacing: 10) { ProgressView().tint(BoxStyle.coach); Text("Building your week…").font(.subheadline) }
                        .frame(maxWidth: .infinity, alignment: .leading).boxPanel(tint: BoxStyle.coach)
                    Button("Cancel request") { request?.cancel() }.buttonStyle(BoxSecondaryStyle())
                } else {
                    PrimaryButton(title: proposal == nil ? "Generate draft" : "Regenerate draft", symbol: "sparkles") { generate() }
                }
                if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
                if let proposal, let context = generatedContext {
                    VStack(alignment: .leading, spacing: 6) {
                        BoxChip(text: "AI draft · Review before accepting", symbol: "sparkles", color: BoxStyle.coach)
                        Text(proposal.title).boxSection(26).padding(.top, 6)
                        Text(proposal.progression).font(.subheadline).foregroundStyle(BoxStyle.muted)
                    }.padding(.top, 8)
                    ForEach(proposal.days.sorted(by: { $0.offset < $1.offset })) { day in
                        VStack(alignment: .leading, spacing: 14) {
                            if let date = Calendar.current.date(byAdding: .day, value: day.offset, to: context.startDate) { Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated)).boxEyebrow(BoxStyle.coach) }
                            Text(day.session.title).font(.headline)
                            Text(day.rationale).font(.subheadline).foregroundStyle(BoxStyle.muted)
                            Text("\(day.session.activities.count) activities · \(Duration.seconds(day.session.estimatedSeconds).formatted(.time(pattern: .minuteSecond))) work & rest").font(.caption).foregroundStyle(BoxStyle.muted)
                            DisclosureGroup("Review sequence") { SessionBriefing(session: day.session, embedded: true).padding(.top, 12) }
                                .font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
                        }.boxPanel(padding: 18)
                    }
                    PrimaryButton(title: "Accept this week", symbol: "checkmark") {
                        if store.acceptTrainingPlan(proposal, context: context) { BoxHaptics.success(); dismiss() }
                        else { error = store.storageNotice; store.storageNotice = nil }
                    }.disabled(working || !Calendar.current.isDate(startDate, inSameDayAs: context.startDate))
                    Text("Existing accepted assignments are protected. To change this draft, update your preferences or feedback and regenerate.")
                        .font(.footnote).foregroundStyle(BoxStyle.muted)
                }
            }.boxPage()
        }.boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Personalized plan").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onDisappear { request?.cancel() }
    }
    private func generate() {
        request?.cancel(); error = nil; working = true; proposal = nil; generatedContext = nil
        let context = store.planningContext(feedback: feedback, from: startDate)
        request = Task {
            defer { working = false }
            do {
                let result = try await QwenClient().proposeTrainingPlan(context: context)
                try Task.checkCancellation(); proposal = result; generatedContext = context
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct WorkoutProposalView: View {
    let store: AppStore
    @State private var working = false
    @State private var proposal: WorkoutProposal?
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Plan a workout", subtitle: "Supporting work that fits your setup.")
                BoxInlineNotice(text: "Generating shares your experience, goal, equipment, space, time budget and eligible routine list. It chooses from the original catalog; prescriptions stay unchanged. Durations are estimates. Review before saving.", symbol: "sparkles", color: BoxStyle.coach)
                if working {
                    HStack(spacing: 10) { ProgressView().tint(BoxStyle.coach); Text("Preparing a workout draft…").font(.subheadline); Spacer(); Button("Cancel") { request?.cancel() } }
                        .boxPanel(tint: BoxStyle.coach)
                }
                else { PrimaryButton(title: "Generate workout draft", symbol: "sparkles") { generate() } }
                if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
                if let proposal {
                    BoxChip(text: "AI draft · Review before saving", symbol: "sparkles", color: BoxStyle.coach).padding(.top, 8)
                    Text(proposal.title).boxSection(26)
                    Text(proposal.reason).font(.subheadline).foregroundStyle(BoxStyle.muted)
                    ForEach(proposal.routineIDs, id: \.self) { id in
                        if let routine = WorkoutRoutine.all.first(where: { $0.id == id }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(routine.title).font(.headline)
                                Text("About \(routine.estimatedMinutes) min · \(routine.equipmentDescription)").font(.caption).foregroundStyle(BoxStyle.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).boxPanel()
                        }
                    }
                    if let session = proposal.guidedSession { SessionBriefing(session: session) }
                    PrimaryButton(title: "Accept & save workout", symbol: "checkmark") {
                        if store.saveWorkoutPlan(proposal) { BoxHaptics.success(); dismiss() }
                        else { error = "This draft no longer fits your setup or could not be saved." }
                    }
                }
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Workout with your coach").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { DismissButton() } }
        .onDisappear { request?.cancel() }
    }
    private func generate() {
        let routines = store.eligibleWorkouts
        let allowed = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0.guidedSession.estimatedSeconds) })
        guard !allowed.isEmpty else { error = "No routine fits this time budget and equipment. Update your profile first."; return }
        let minutes = store.profile.sessionMinutes
        let catalog = routines.map { "\($0.id): \(String(localized: $0.title)), \($0.guidedSession.estimatedSeconds) scheduled seconds" }.joined(separator: "; ")
        let context = "Experience: \(store.profile.experience). Goal: \(store.profile.goal). Equipment: \(store.profile.equipment). Space: \(store.profile.space). Budget: \(minutes) minutes. Allowed catalog: \(catalog)"
        working = true; error = nil; proposal = nil
        request = Task { @MainActor in
            defer { working = false }
            do { proposal = try await QwenClient().proposeWorkout(context: context, allowedSeconds: allowed, minutes: minutes) }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
