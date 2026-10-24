import SwiftUI

private enum FuelDestination: Identifiable {
    case meal, estimate, barcode, targets, nutrition, water, edit(MealEntry)
    var id: String {
        switch self {
        case .meal: "meal"
        case .estimate: "estimate"
        case .barcode: "barcode"
        case .targets: "targets"
        case .nutrition: "nutrition"
        case .water: "water"
        case .edit(let meal): "edit-" + meal.id.uuidString
        }
    }
}

struct FuelView: View {
    let store: AppStore
    @State private var date = Date.now
    @State private var destination: FuelDestination?
    var body: some View {
        let meals = store.meals(on: date)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    BoxPageHeader(title: "Fuel", subtitle: "Eat well. Recover. Go again.")
                    Menu {
                        Button("Edit daily targets", systemImage: "slider.horizontal.3") { destination = .targets }
                        Button("Plan targets with coach", systemImage: "sparkles") { destination = .nutrition }
                    } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .semibold)).foregroundStyle(BoxStyle.ink)
                            .frame(width: 40, height: 40).boxGlassControl(cornerRadius: 20)
                    }.accessibilityLabel("Nutrition targets")
                }.boxEntrance()
                FuelDayStrip(date: $date).boxEntrance(1).padding(.bottom, 4)
                FuelSummary(totals: store.totals(on: date), targets: store.targets).boxEntrance(2)
                WaterSummary(store: store, date: date) { destination = .water }.boxEntrance(3)
                BoxSectionHeader(title: Calendar.current.isDateInToday(date) ? "Today's meals" : "Meals") {
                    Text(meals.count, format: .number)
                }.padding(.top, 12).boxEntrance(4)
                if meals.isEmpty {
                    BoxEmptyState(symbol: "fork.knife", title: "Start with your next meal.", detail: "Log what you know, or review a text or photo estimate before adding it.")
                        .boxEntrance(5)
                } else {
                    BoxRowGroup {
                        ForEach(meals) { meal in
                            Button { destination = .edit(meal) } label: { MealRow(meal: meal) }.buttonStyle(BoxPressStyle(scale: 0.985))
                        }
                    }.boxEntrance(5)
                }
            }
            .boxPage()
            .padding(.bottom, 64)
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button("Log manually", systemImage: "square.and.pencil") { destination = .meal }
                Button("Estimate from text or photo", systemImage: "sparkles") { destination = .estimate }
                Button("Look up barcode", systemImage: "barcode") { destination = .barcode }
            } label: {
                Label("Add food", systemImage: "plus")
                    .font(.system(size: 17, weight: .heavy).width(.condensed)).textCase(.uppercase).tracking(0.6)
                    .modifier(BoxOblique())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).frame(height: 56)
                    .background(BoxStyle.redGradient, in: .capsule)
                    .overlay { Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)) }
                    .shadow(color: BoxStyle.accent.opacity(0.55), radius: 16, y: 10)
            }
            .accessibilityIdentifier("fuel.addFood")
            .padding(.trailing, 20).padding(.bottom, 12)
        }
        .boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Fuel").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $destination) { route in
            NavigationStack {
                switch route {
                case .meal: MealEditor(store: store, date: date)
                case .edit(let meal): MealEditor(store: store, date: meal.date, existing: meal, initial: meal.draft)
                case .estimate: FoodEstimateView(store: store, date: date)
                case .barcode: BarcodeFoodView(store: store, date: date)
                case .targets: TargetsEditor(store: store)
                case .nutrition: NutritionPlanningView(store: store)
                case .water: WaterEditor(store: store, date: date)
                }
            }.presentationDragIndicator(.visible)
        }
    }
}

/// Last seven days, today on the right. Older dates via the calendar button.
private struct FuelDayStrip: View {
    @Binding var date: Date
    @State private var picking = false
    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<6).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }
    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let selected = Calendar.current.isDate(day, inSameDayAs: date)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { date = day }
                    BoxHaptics.selection()
                } label: {
                    VStack(spacing: 3) {
                        Text(day, format: .dateTime.weekday(.narrow)).font(.caption2.weight(.semibold))
                            .foregroundStyle(selected ? .white.opacity(0.85) : BoxStyle.dim)
                        Text(day, format: .dateTime.day()).boxNumber(19, relativeTo: .headline)
                            .foregroundStyle(selected ? .white : BoxStyle.ink)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(selected ? AnyShapeStyle(BoxStyle.redGradient) : AnyShapeStyle(BoxStyle.surface))
                            .shadow(color: selected ? BoxStyle.accent.opacity(0.45) : .clear, radius: 8, y: 4)
                    }
                    .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(selected ? .white.opacity(0.2) : BoxStyle.border) }
                }
                .buttonStyle(BoxPressStyle(scale: 0.92))
                .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month().day()))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button { picking = true } label: {
                Image(systemName: "calendar").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44).frame(maxHeight: .infinity)
                    .background(BoxStyle.surface, in: .rect(cornerRadius: 15, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(BoxStyle.border) }
            }
            .buttonStyle(BoxPressStyle(scale: 0.92))
            .accessibilityLabel("Choose another date")
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $picking) {
            NavigationStack {
                DatePicker("Log date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding().tint(BoxStyle.accent)
                    .navigationTitle("Choose a day").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { picking = false } } }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct FuelSummary: View {
    let totals: NutritionTotals
    let targets: NutritionTargets
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let hasTarget = targets.calories > 0
        let remaining = max(0, targets.calories - totals.calories)
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hasTarget ? "Calories left" : "Calories logged").boxEyebrow(.white.opacity(0.85))
                        Text(hasTarget ? remaining : totals.calories, format: .number.precision(.fractionLength(0)))
                            .boxNumber(62, relativeTo: .largeTitle)
                            .contentTransition(.numericText(value: hasTarget ? remaining : totals.calories))
                            .minimumScaleFactor(0.6).lineLimit(1)
                        if hasTarget {
                            BoxChip(text: totals.calories > targets.calories ? "Over target" : "Within target", onHero: true)
                        }
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        BoxRing(progress: hasTarget ? totals.calories / targets.calories : 0, lineWidth: 9, color: .white, track: .black.opacity(0.22))
                        Image(systemName: "flame.fill").font(.system(size: 26, weight: .semibold))
                    }.frame(width: 100, height: 100)
                }
                HStack(spacing: 0) {
                    heroStat(totals.calories, "Eaten")
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                    heroStat(targets.calories, "Goal")
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                    heroStat(remaining, "Remaining")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.2)).frame(height: 1) }
                .padding(.top, 16)
                if !hasTarget {
                    Text("Add daily targets from the controls above.").font(.caption).foregroundStyle(.white.opacity(0.8)).padding(.top, 10)
                }
            }
            .boxHero()
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: totals.calories)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                FuelMacroCard(title: "Protein", value: totals.protein, target: targets.protein, color: BoxStyle.accent)
                FuelMacroCard(title: "Carbs", value: totals.carbs, target: targets.carbs, color: BoxStyle.strength)
                FuelMacroCard(title: "Fat", value: totals.fat, target: targets.fat, color: BoxStyle.timer)
            }
        }
    }
    private func heroStat(_ value: Double, _ label: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.precision(.fractionLength(0))).boxNumber(22).contentTransition(.numericText(value: value))
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.8))
        }.frame(maxWidth: .infinity)
    }
}

private struct FuelMacroCard: View {
    let title: LocalizedStringResource
    let value: Double
    let target: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).boxEyebrow(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value, format: .number.precision(.fractionLength(0))).boxNumber(24).contentTransition(.numericText(value: value))
                Text(target > 0 ? "/ \(target.formatted(.number.precision(.fractionLength(0))))g" : "g").font(.caption2).foregroundStyle(BoxStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            BoxProgressTrack(value: target > 0 ? value / target : 0, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .boxPanel(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

private struct MealRow: View {
    let meal: MealEntry
    var body: some View {
        let estimated = meal.source.lowercased().contains("estimate")
        BoxRow(symbol: estimated ? "sparkles" : "fork.knife", color: estimated ? BoxStyle.coach : BoxStyle.strength,
               title: meal.name,
               subtitle: estimated ? String(localized: "Estimated · Reviewed by you") : (meal.serving.isEmpty ? String(localized: "Logged meal") : meal.serving),
               showsChevron: false) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(meal.calories, format: .number.precision(.fractionLength(0))).boxNumber(19)
                Text("kcal").font(.caption2).foregroundStyle(BoxStyle.muted)
            }.foregroundStyle(BoxStyle.ink)
        }
    }
}

private struct WaterSummary: View {
    let store: AppStore
    let date: Date
    let edit: () -> Void
    @State private var bump = 0
    var body: some View {
        let water = store.totals(on: date).water
        let target = store.targets.water
        let filled = target > 0 ? min(10, Int((Double(water) / Double(target) * 10).rounded(.down))) : 0
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    BoxIconWell(symbol: "drop.fill", color: BoxStyle.timer)
                        .symbolEffect(.bounce, value: bump)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Water").font(.subheadline.weight(.semibold))
                            Text(target > 0 ? "\(water) / \(target) ml" : "\(water) ml logged").font(.caption).foregroundStyle(BoxStyle.muted)
                                .contentTransition(.numericText(value: Double(water)))
                        }
                        if target > 0 {
                            HStack(spacing: 3) {
                                ForEach(0..<10, id: \.self) { index in
                                    Capsule().fill(index < filled ? BoxStyle.timer : .white.opacity(0.08)).frame(height: 6)
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: filled)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(BoxStyle.ink)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the water log")
            Button {
                if store.addWater(250, date: date) { bump += 1; BoxHaptics.success() }
            } label: { Text("+250 ml") }
            .buttonStyle(BoxSecondaryStyle())
        }
        .boxPanel(padding: 14, tint: BoxStyle.timer)
    }
}

struct MealEditor: View {
    let store: AppStore
    let date: Date
    var existing: MealEntry?
    // Intentional one-time seed for a cancellable editor, never an autosaved model binding.
    var initial = MealDraft()
    @State private var draft = MealDraft()
    @State private var seeded = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            BoxPageHeader(title: existing == nil ? "Log a meal" : "Edit meal", subtitle: "Your serving. Your numbers. Your record.")
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Meal")
                TextField("Name", text: $draft.name).padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
                TextField("Serving, e.g. 1 bowl", text: $draft.serving).padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .boxPanel()
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Nutrition for this serving")
                NutrientField(title: "Calories", unit: "kcal", value: $draft.calories)
                NutrientField(title: "Protein", unit: "g", value: $draft.protein)
                NutrientField(title: "Carbohydrate", unit: "g", value: $draft.carbs)
                NutrientField(title: "Fat", unit: "g", value: $draft.fat)
            }
            .boxPanel()
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Source & notes")
                Text(draft.source.lowercased().contains("estimate") ? "AI estimate · Check before saving" : draft.source).font(.subheadline)
                TextField("Assumptions or notes", text: $draft.assumptions, axis: .vertical).padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
                if draft.source.lowercased().contains("estimate") { Text("AI estimate. Check the serving and numbers before saving.").font(.footnote).foregroundStyle(.secondary) }
            }
            .boxPanel()
            PrimaryButton(title: "Save meal", symbol: "checkmark") { if store.saveMeal(draft, date: date, existing: existing) { BoxHaptics.success(); dismiss() } }.disabled(!draft.isValid)
            if existing != nil { Button("Delete meal", role: .destructive) { confirmDelete = true }.frame(minHeight: 44) }
          }.boxPage()
        }
        .scrollDismissesKeyboard(.interactively).boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink)
        .navigationTitle(existing == nil ? "Log meal" : "Edit meal").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .onAppear { if !seeded { draft = initial; seeded = true } }
        .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete meal", role: .destructive) { if let existing { store.deleteMeal(existing); if store.storageNotice == nil { dismiss() } } }
        }
    }
}

struct NutrientField: View {
    let title: LocalizedStringKey
    let unit: LocalizedStringKey
    @Binding var value: Double
    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            TextField("0", value: $value, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                .boxNumber(20).frame(maxWidth: 120)
            Text(unit).font(.caption).foregroundStyle(BoxStyle.muted).frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct TargetsEditor: View {
    let store: AppStore
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    @State private var water = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            BoxPageHeader(title: "Edit daily targets", subtitle: "Set the numbers you want to track.")
            VStack(alignment: .leading, spacing: 18) {
                NutrientField(title: "Calories", unit: "kcal", value: $calories)
                NutrientField(title: "Protein", unit: "g", value: $protein)
                NutrientField(title: "Carbohydrate", unit: "g", value: $carbs)
                NutrientField(title: "Fat", unit: "g", value: $fat)
                HStack { Text("Water (ml)"); TextField("0", value: $water, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            .boxPanel()
            Text("Use targets you have chosen or agreed with your nutrition professional. Leave a target at zero to hide it. Or ask your coach for an estimated nutrition plan, review the numbers and accept it. ")
                .font(.footnote).foregroundStyle(BoxStyle.muted)
          }.boxPage()
        }
        .scrollDismissesKeyboard(.interactively).boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Daily targets").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if store.saveTargets(calories: calories, protein: protein, carbs: carbs, fat: fat, water: water) { BoxHaptics.success(); dismiss() } }
                    .disabled(![calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 100_000 } || !(0...20_000).contains(water))
            }
        }
        .onAppear { calories = store.targets.calories; protein = store.targets.protein; carbs = store.targets.carbs; fat = store.targets.fat; water = store.targets.water }
    }
}

private struct WaterEditor: View {
    let store: AppStore
    let date: Date
    @State private var amount = 250
    var body: some View {
        Form {
            Section("Add water") {
                HStack { TextField("Amount in ml", value: $amount, format: .number).keyboardType(.numberPad); Text("ml") }
                Button("Add water") { if store.addWater(amount, date: date) { BoxHaptics.success() } }.disabled(!(1...10_000).contains(amount))
            }
            Section("Water log") {
                ForEach(store.water(on: date)) { entry in
                    HStack {
                        Text("\(entry.millilitres) ml"); Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { store.deleteWater(entry) }.labelStyle(.iconOnly)
                    }
                }
                if store.water(on: date).isEmpty { Text("No water logged for this day.").foregroundStyle(.secondary) }
            }
        }
        .boxFormStyle(tint: BoxStyle.timer)
        .navigationTitle("Water").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { DismissButton() } }
    }
}
