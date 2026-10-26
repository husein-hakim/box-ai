import SwiftUI

/// One flow for the whole programme: profile → one AI-generated training week
/// (boxing technique, camera drills, sparring rounds, footwork, conditioning,
/// strength) → nutrition targets that fuel that week → one review → one accept.
struct ProgramBuilderView: View {
    let store: AppStore
    /// Next week from the saved profile and recent training, after a short check-in.
    var nextWeek = false
    enum Step { case about, checkIn, building, review }
    @State private var step: Step = .about
    @State private var feeling: Int?
    @State private var checkInNotes = ""
    // About you
    @State private var experience = "Beginner"
    @State private var goal = "General boxing"
    @State private var stance = "Orthodox"
    @State private var days: Set<Int> = []
    @State private var minutes = 30
    @State private var equipment: Set<String> = []
    @State private var space = "Small indoor space"
    @State private var nutrition = NutritionPlanningInput()
    @State private var includeNutrition = true
    @State private var feedback = ""
    // Results
    @State private var context: PlanningContext?
    @State private var plan: TrainingPlanProposal?
    @State private var targets: NutritionTargetProposal?
    @State private var nutritionInput: NutritionPlanningInput?
    @State private var planError: String?
    @State private var nutritionError: String?
    @State private var building: Task<Void, Never>?
    @State private var replaceUpcoming = false
    @State private var acceptError: String?
    @State private var seeded = false
    @Environment(\.dismiss) private var dismiss

    static let goals = ["General boxing", "Build consistency", "Learn every punch & defense", "Conditioning", "Strength & power", "Straight punches"]
    static let equipmentOptions = ["Gloves", "Hand wraps", "Heavy bag", "Focus pads", "Pad partner", "Skipping rope", "Dumbbells", "Stable wall", "Outdoor space"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch step {
                case .about: about
                case .checkIn: checkIn
                case .building: buildingView
                case .review: review
                }
            }.boxPage()
        }
        .scrollDismissesKeyboard(.interactively)
        .boxScreen().foregroundStyle(BoxStyle.ink)
        .navigationTitle("Your program").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { building?.cancel(); dismiss() } } }
        .onAppear(perform: seed)
        .onDisappear { building?.cancel() }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    // MARK: About you

    @ViewBuilder private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Boxing · strength · nutrition", systemImage: "sparkles").boxEyebrow(.white.opacity(0.85))
            Text("One program.\nEverything in it.").boxDisplay(40, relativeTo: .title).padding(.top, 10)
            Text("Your coach builds a week that mixes drills, camera training, sparring rounds, footwork, conditioning and strength, then sets nutrition targets that fuel it. You review everything before it's added.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
        }.boxHero().boxEntrance()
        if let focus = store.styleFocus {
            HStack(spacing: 12) {
                BoxIconWell(symbol: "person.fill.viewfinder", size: 40, color: BoxStyle.strength)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Style focus: \(focus.fighter)").font(.subheadline.weight(.semibold))
                    Text("\(focus.archetype) · \(focus.emphasis.prefix(3).joined(separator: ", "))").font(.caption).foregroundStyle(BoxStyle.muted)
                }
                Spacer()
                Button("Remove") { store.styleFocus = nil }.font(.caption.weight(.semibold))
            }.boxPanel(padding: 12, tint: BoxStyle.strength).boxEntrance(1)
        }
        if !store.reviewFocus.isEmpty {
            Label("Includes drills for your latest review fixes", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(BoxStyle.coach)
        }

        BoxSectionHeader(title: "You").padding(.top, 8)
        VStack(alignment: .leading, spacing: 12) {
            BoxSegmented(options: ["Beginner", "Some experience", "Experienced"], selection: $experience, title: { LocalizedStringResource(stringLiteral: $0) })
            BoxSegmented(options: ["Orthodox", "Southpaw"], selection: $stance, title: { LocalizedStringResource(stringLiteral: $0) })
            Picker("Main goal", selection: $goal) { ForEach(Self.goals, id: \.self) { Text($0).tag($0) } }.tint(BoxStyle.ink)
        }.font(.subheadline).boxPanel(padding: 18)

        BoxSectionHeader(title: "Your week") { Text("\(days.count) days") }.padding(.top, 8)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach([(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")], id: \.0) { day in
                    let on = days.contains(day.0)
                    Button { if on { days.remove(day.0) } else { days.insert(day.0) }; BoxHaptics.selection() } label: {
                        Text(day.1).boxNumber(18).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(on ? .white : BoxStyle.muted)
                            .background(on ? AnyShapeStyle(BoxStyle.redGradient) : AnyShapeStyle(BoxStyle.surfaceRaised), in: .rect(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(BoxPressStyle(scale: 0.92)).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Stepper(value: $minutes, in: 10...60, step: 5) {
                HStack { Text("Session length"); Spacer(); Text("\(minutes) min").boxNumber(20) }
            }
            Picker("Space", selection: $space) {
                ForEach(["Small indoor space", "Larger indoor space", "Outdoor space"], id: \.self) { Text($0).tag($0) }
            }.tint(BoxStyle.ink)
        }.font(.subheadline).boxPanel(padding: 18)

        BoxSectionHeader(title: "Equipment") { Text("\(equipment.count)") }.padding(.top, 8)
        FlowChips(options: Self.equipmentOptions, selection: $equipment)

        BoxSectionHeader(title: "Nutrition") {
            Toggle("Include", isOn: $includeNutrition).labelsHidden().tint(BoxStyle.conditioning)
        }.padding(.top, 8)
        if includeNutrition {
            VStack(alignment: .leading, spacing: 10) {
                numberRow("Age", value: Binding(get: { Double(nutrition.age) }, set: { nutrition.age = Int($0) }), unit: "yrs")
                numberRow("Height", value: $nutrition.heightCm, unit: "cm")
                numberRow("Weight", value: $nutrition.weightKg, unit: "kg")
                Picker("Sex (optional)", selection: $nutrition.sex) { ForEach(["Prefer not to say", "Female", "Male"], id: \.self) { Text($0).tag($0) } }.tint(BoxStyle.ink)
                Picker("Daily activity", selection: $nutrition.activity) { ForEach(["Light daily activity", "Moderate daily activity", "Very active days"], id: \.self) { Text($0).tag($0) } }.tint(BoxStyle.ink)
                if nutrition.age > 0 && nutrition.age < 18 {
                    BoxInlineNotice(text: "Growing athletes: review targets with a parent or guardian and a qualified nutrition professional. Weight-loss targets are not supported.", symbol: "person.2.fill", color: BoxStyle.strength)
                }
            }.font(.subheadline).boxPanel(padding: 18)
        }
        TextField("Anything else? Injuries to work around, things you enjoy…", text: $feedback, axis: .vertical)
            .lineLimit(2...5).padding(14)
            .background(BoxStyle.surface, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BoxStyle.border) }
        BoxInlineNotice(text: "Building shares this profile, your schedule, recent training and feedback with the AI coach. Nothing changes until you accept.", symbol: "sparkles", color: BoxStyle.coach)
        PrimaryButton(title: "Build my program", symbol: "sparkles", action: build)
            .disabled(days.isEmpty || (includeNutrition && !nutrition.isValid))
        if days.isEmpty { Text("Pick at least one training day.").font(.caption).foregroundStyle(BoxStyle.muted) }
        else if includeNutrition && !nutrition.isValid { Text("Add age, height and weight for nutrition, or turn nutrition off.").font(.caption).foregroundStyle(BoxStyle.muted) }
    }

    private func numberRow(_ label: LocalizedStringResource, value: Binding<Double>, unit: LocalizedStringResource) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).boxNumber(20).frame(maxWidth: 110)
            Text(unit).font(.caption).foregroundStyle(BoxStyle.muted).frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: Building

    @ViewBuilder private var buildingView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Building your program").boxDisplay(38).padding(.top, 24)
            progressRow("Training week", done: plan != nil, failed: planError != nil, active: plan == nil && planError == nil)
            if includeNutrition {
                progressRow("Nutrition targets for that week", done: targets != nil, failed: nutritionError != nil,
                            active: plan != nil && targets == nil && nutritionError == nil)
            }
            Text("This can take up to a minute.").font(.footnote).foregroundStyle(BoxStyle.muted)
            Button("Cancel") { building?.cancel(); step = nextWeek ? .checkIn : .about }.buttonStyle(BoxSecondaryStyle())
        }
    }

    private func progressRow(_ title: LocalizedStringResource, done: Bool, failed: Bool, active: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(BoxStyle.conditioning) }
                else if failed { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BoxStyle.accent) }
                else if active { ProgressView().tint(BoxStyle.coach) }
                else { Image(systemName: "circle").foregroundStyle(BoxStyle.dim) }
            }.font(.title3).frame(width: 28)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
        }.boxPanel(padding: 14)
    }

    // MARK: Review

    @ViewBuilder private var review: some View {
        if let plan, let context {
            VStack(alignment: .leading, spacing: 6) {
                BoxChip(text: "AI draft · Review before accepting", symbol: "sparkles", color: BoxStyle.coach)
                Text(plan.title).boxDisplay(34).padding(.top, 6)
                Text(plan.progression).font(.subheadline).foregroundStyle(BoxStyle.muted)
            }
            ProgramWeekMix(plan: plan)
            ForEach(plan.days.sorted { $0.offset < $1.offset }) { day in
                ProgramDayCard(day: day, date: Calendar.current.date(byAdding: .day, value: day.offset, to: context.startDate))
            }
        } else if let planError {
            BoxInlineNotice(text: "\(planError)", symbol: "exclamationmark.triangle", color: BoxStyle.accent)
        }
        if includeNutrition {
            if let targets {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { BoxFeatureLabel(title: "Daily nutrition", symbol: "fork.knife", color: BoxStyle.strength); Spacer(); BoxChip(text: "AI estimate", color: BoxStyle.coach) }
                    HStack(spacing: 8) {
                        macro(targets.calories, "kcal", BoxStyle.ink)
                        macro(targets.protein, "protein g", BoxStyle.accent)
                        macro(targets.carbs, "carbs g", BoxStyle.strength)
                        macro(targets.fat, "fat g", BoxStyle.timer)
                    }
                    Text("Water \(targets.waterMl) ml").font(.caption.weight(.semibold)).foregroundStyle(BoxStyle.timer)
                    Text(targets.explanation).font(.footnote).foregroundStyle(BoxStyle.muted)
                }.boxPanel(padding: 18, tint: BoxStyle.strength)
            } else if let nutritionError {
                BoxInlineNotice(text: "Nutrition: \(nutritionError) You can accept the training and plan nutrition later from Fuel.", symbol: "exclamationmark.triangle", color: BoxStyle.strength)
            }
        }
        if plan != nil, store.plan.contains(where: { $0.date >= Calendar.current.startOfDay(for: .now) }) {
            Toggle(isOn: $replaceUpcoming) {
                Text("Replace my current upcoming sessions. Completed work is kept.").font(.footnote.weight(.semibold))
            }.tint(BoxStyle.accent).boxPanel(padding: 14)
        }
        if let acceptError { BoxInlineNotice(text: "\(acceptError)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
        PrimaryButton(title: "Accept program", symbol: "checkmark", action: accept)
            .disabled(plan == nil)
        HStack(spacing: 10) {
            Button { build() } label: { Text("Regenerate").frame(maxWidth: .infinity) }
            Button { step = nextWeek ? .checkIn : .about } label: { Text(nextWeek ? "Back to check-in" : "Change details").frame(maxWidth: .infinity) }
        }.buttonStyle(BoxSecondaryStyle())
    }

    private func macro(_ value: Double, _ label: LocalizedStringResource, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.precision(.fractionLength(0))).boxNumber(20).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(BoxStyle.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 8).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 12))
    }

    // MARK: Actions

    @ViewBuilder private var checkIn: some View {
        let summary = store.adaptiveSummary
        let lastWeek = summary.weeks.last
        VStack(alignment: .leading, spacing: 0) {
            Label("Adaptive program", systemImage: "arrow.triangle.2.circlepath").boxEyebrow(.white.opacity(0.85))
            Text("Next week,\nbuilt on this one.").boxDisplay(40, relativeTo: .title).padding(.top, 10)
            Text("Your coach looks at what you finished, how hard it felt, your camera accuracy per move and your review fixes, then adjusts.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
        }.boxHero().boxEntrance()
        VStack(alignment: .leading, spacing: 12) {
            Text("What your coach will use").boxEyebrow()
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
            let trained = store.history.filter { $0.date >= weekAgo }.count
            HStack(spacing: 8) {
                checkInStat(lastWeek.map { $0.plannedSessions > 0 ? "\($0.completedSessions)/\($0.plannedSessions)" : "\(trained)" } ?? "\(trained)",
                            lastWeek.map { $0.plannedSessions > 0 } == true ? "Planned done" : "Sessions")
                checkInStat("\(lastWeek?.trainedMinutes ?? 0)", "Minutes")
                checkInStat("\(summary.streakDays)", "Day streak")
            }
            if let weak = summary.moves.first, weak.accuracy < 0.7 {
                Label("Working on: \(weak.move) (\(Int(weak.accuracy * 100))% in camera drills)", systemImage: "scope").font(.subheadline)
            }
            if let strong = summary.moves.last, strong.accuracy >= 0.8 {
                Label("Strong: \(strong.move) (\(Int(strong.accuracy * 100))%)", systemImage: "checkmark.seal.fill").font(.subheadline)
            }
            if !store.reviewFocus.isEmpty { Label("Review fixes: \(store.reviewFocus.count)", systemImage: "sparkles").font(.subheadline) }
            if let focus = store.styleFocus { Label("Style: \(focus.fighter)", systemImage: "person.fill.viewfinder").font(.subheadline) }
            if !summary.coachNotes.isEmpty {
                DisclosureGroup("Adjustments the coach will make") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.coachNotes, id: \.self) { Label($0, systemImage: "arrow.turn.down.right").font(.caption).foregroundStyle(BoxStyle.muted) }
                    }.padding(.top, 8)
                }.font(.subheadline)
            }
        }.boxPanel(padding: 16).boxEntrance(1)
        VStack(alignment: .leading, spacing: 10) {
            Text("How did this week feel?").boxEyebrow()
            HStack(spacing: 6) {
                ForEach(Array(["Too easy", "Just right", "Too hard"].enumerated()), id: \.offset) { i, label in
                    Button { feeling = i; BoxHaptics.selection() } label: {
                        Text(LocalizedStringResource(stringLiteral: label)).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(feeling == i ? .white : BoxStyle.ink)
                            .background(feeling == i ? AnyShapeStyle(BoxStyle.redGradient) : AnyShapeStyle(BoxStyle.surfaceRaised), in: .rect(cornerRadius: 12))
                    }.buttonStyle(BoxPressStyle(scale: 0.95))
                }
            }
            TextField("Anything to change? Sore, busy days, want more sparring…", text: $checkInNotes, axis: .vertical).lineLimit(2...5)
                .padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 12, style: .continuous))
        }.boxPanel(padding: 16).boxEntrance(2)
        Toggle("Update nutrition targets too", isOn: $includeNutrition).font(.subheadline).tint(BoxStyle.accent).boxPanel(padding: 14)
        PrimaryButton(title: "Build next week", symbol: "sparkles") {
            let feelingText = feeling.map { ["too easy", "just right", "too hard"][$0] }.map { "Check-in: last week felt \($0). " } ?? ""
            build(start: store.nextPlanStart, feedback: feelingText + checkInNotes, saveProfile: false)
        }
        Text("Starts \(store.nextPlanStart.formatted(.dateTime.weekday(.wide).day().month())). You review every day before it's added.").font(.caption).foregroundStyle(BoxStyle.muted)
    }

    private func checkInStat(_ value: String, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).boxNumber(24)
            Text(label).boxEyebrow().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 12))
    }

    private func seed() {
        guard !seeded else { return }; seeded = true
        if nextWeek { step = .checkIn }
        experience = store.profile.experience; goal = Self.goals.contains(store.profile.goal) ? store.profile.goal : "General boxing"
        stance = store.stance == "Southpaw" ? "Southpaw" : "Orthodox"
        days = store.selectedDays; minutes = max(10, min(60, store.profile.sessionMinutes))
        equipment = Set(store.profile.equipment); space = store.profile.space
        if let data = store.profile.nutritionInputData, let saved = try? JSONDecoder().decode(NutritionPlanningInput.self, from: data) { nutrition = saved }
    }

    private func build() { build(start: Calendar.current.startOfDay(for: .now), feedback: feedback, saveProfile: true) }

    private func build(start: Date, feedback: String, saveProfile: Bool) {
        building?.cancel()
        // The profile is the single source the plan, validation and acceptance all read.
        if saveProfile {
            guard store.saveProfile(name: store.profile.name, experience: experience, goal: goal, equipment: equipment.sorted(), space: space, minutes: minutes) else { return }
            store.selectedDays = days; store.stance = stance
        }
        plan = nil; targets = nil; planError = nil; nutritionError = nil; acceptError = nil
        let request = store.planningContext(feedback: feedback, from: start)
        context = request; step = .building
        let nutritionRequest = includeNutrition ? nutrition : nil
        nutritionInput = nutritionRequest
        building = Task {
            do {
                let proposal = try await QwenClient().proposeTrainingPlan(context: request)
                try Task.checkCancellation()
                plan = proposal
            } catch is CancellationError { return }
            catch { planError = error.localizedDescription }
            if let nutritionRequest, let plan {
                // Nutrition sees the proposed week, so targets match its training load.
                let week = plan.days.sorted { $0.offset < $1.offset }.map { "Day \($0.offset): \($0.session.title), \($0.session.type.rawValue), \($0.session.estimatedSeconds) planned seconds" }.joined(separator: "\n")
                    + (request.styleFocus.map { "\nStyle focus: \($0.fighter), \($0.archetype). Conditioning demands: \($0.conditioning)" } ?? "")
                do {
                    let proposal = try await QwenClient().proposeNutritionTargets(input: nutritionRequest, training: request, acceptedTraining: week)
                    try Task.checkCancellation()
                    targets = proposal
                } catch is CancellationError { return }
                catch { nutritionError = error.localizedDescription }
            }
            step = .review
        }
    }

    private func accept() {
        guard let plan, let context else { return }
        acceptError = nil
        if replaceUpcoming {
            for item in store.plan where item.date >= context.startDate && item.completionID == nil { store.removePlanItem(item) }
        }
        guard store.acceptTrainingPlan(plan, context: context) else { acceptError = store.storageNotice; store.storageNotice = nil; return }
        if let targets, let nutritionInput, !store.acceptNutritionTargets(targets, input: nutritionInput) {
            acceptError = String(localized: "Training was added, but nutrition targets could not be saved: \(store.storageNotice ?? "")")
            store.storageNotice = nil; return
        }
        BoxHaptics.success(); dismiss()
    }
}

/// Simple wrapping chips for a multi-select list.
private struct FlowChips: View {
    let options: [String]
    @Binding var selection: Set<String>
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = selection.contains(option)
                Button { if on { selection.remove(option) } else { selection.insert(option) }; BoxHaptics.selection() } label: {
                    Text(option).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? BoxStyle.ink : BoxStyle.muted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? BoxStyle.accent.opacity(0.16) : BoxStyle.surface, in: .capsule)
                        .overlay { Capsule().strokeBorder(on ? BoxStyle.accent.opacity(0.6) : BoxStyle.border) }
                }.buttonStyle(BoxPressStyle(scale: 0.94)).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Minutes of each kind of work across the proposed week.
struct ProgramWeekMix: View {
    let plan: TrainingPlanProposal
    var body: some View {
        let mix = ProgramMix(sessions: plan.days.map(\.session))
        VStack(alignment: .leading, spacing: 10) {
            Text("This week's mix").boxEyebrow()
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(mix.parts, id: \.label) { part in
                        Rectangle().fill(part.color).frame(width: max(4, geometry.size.width * part.share))
                    }
                }.clipShape(.capsule)
            }.frame(height: 10)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(mix.parts, id: \.label) { part in
                    HStack(spacing: 6) {
                        Circle().fill(part.color).frame(width: 8, height: 8)
                        Text("\(part.label) · \(part.minutes) min").font(.caption.weight(.semibold))
                    }
                }
            }
        }.boxPanel(padding: 16)
    }
}

struct ProgramMix {
    struct Part { let label: String; let minutes: Int; let share: Double; let color: Color }
    let parts: [Part]
    init(sessions: [GuidedSession]) {
        var totals: [String: Int] = [:]
        let order = [String(localized: "Camera"), String(localized: "Boxing"), String(localized: "Strength"), String(localized: "Conditioning"), String(localized: "Mobility")]
        for session in sessions {
            for item in session.activities {
                guard let activity = ActivityCatalog.find(item.activityID) else { continue }
                let key: String
                if item.mode == .camera { key = order[0] }
                else {
                    switch activity.kind {
                    case .boxing: key = order[1]
                    case .strength, .core: key = order[2]
                    case .conditioning: key = order[3]
                    case .warmup, .mobility, .cooldown: key = order[4]
                    }
                }
                totals[key, default: 0] += item.estimatedSeconds
            }
        }
        let sum = max(1, totals.values.reduce(0, +))
        let colors = [BoxStyle.accent, Color(red: 0.75, green: 0.18, blue: 0.16), BoxStyle.strength, BoxStyle.conditioning, BoxStyle.timer]
        parts = order.enumerated().compactMap { index, key in
            guard let seconds = totals[key], seconds > 0 else { return nil }
            return Part(label: key, minutes: max(1, seconds / 60), share: Double(seconds) / Double(sum), color: colors[index])
        }
    }
}

private struct ProgramDayCard: View {
    let day: TrainingPlanProposal.Day
    let date: Date?
    @State private var expanded = false
    var body: some View {
        let session = day.session
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let date { Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated)).boxEyebrow(session.type == .recovery ? BoxStyle.muted : BoxStyle.accent) }
                Spacer()
                Text(session.activities.isEmpty ? String(localized: "Rest") : Duration.seconds(session.estimatedSeconds).formatted(.time(pattern: .minuteSecond)) + " min")
                    .font(.caption.weight(.semibold)).foregroundStyle(BoxStyle.muted)
            }
            Text(session.title).boxSection(22)
            if !session.activities.isEmpty {
                let highlights = session.activities.compactMap { item -> (String, Color)? in
                    guard let activity = ActivityCatalog.find(item.activityID), ![.warmup, .cooldown].contains(activity.kind) else { return nil }
                    let color: Color = item.mode == .camera ? BoxStyle.accent : activity.kind == .boxing ? BoxStyle.ink : activity.kind == .strength || activity.kind == .core ? BoxStyle.strength : activity.kind == .conditioning ? BoxStyle.conditioning : BoxStyle.timer
                    return ((item.mode == .camera ? "📷 " : "") + activity.title, color)
                }
                FlexibleTags(tags: highlights)
            }
            Text(day.rationale).font(.footnote).foregroundStyle(BoxStyle.muted).lineLimit(expanded ? nil : 2)
            if !session.activities.isEmpty {
                DisclosureGroup("Full sequence", isExpanded: $expanded) { SessionBriefing(session: session, embedded: true).padding(.top, 8) }
                    .font(.subheadline.weight(.semibold)).tint(BoxStyle.muted)
            }
        }.boxPanel(padding: 16)
    }
}

private struct FlexibleTags: View {
    let tags: [(String, Color)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag.0).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(tag.1)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .background(tag.1.opacity(0.1), in: .capsule)
            }
        }
    }
}
