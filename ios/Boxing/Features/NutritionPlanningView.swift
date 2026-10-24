import SwiftUI

struct NutritionPlanningView: View {
    let store: AppStore
    @State private var input = NutritionPlanningInput()
    @State private var proposal: NutritionTargetProposal?
    @State private var generatedInput: NutritionPlanningInput?
    @State private var working = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var seeded = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Daily targets", subtitle: "Fuel your training and recovery.").boxEntrance()
                Group {
                    BoxInlineNotice(text: "Your coach estimates daily energy, macros and hydration for training and recovery. Review and edit every number before accepting.", symbol: "sparkles", color: BoxStyle.coach)
                    NutritionInputFields(input: $input).disabled(working)
                    if input.age > 0 && input.age < 18 {
                        BoxInlineNotice(text: "Growing athletes: review these estimates with a parent or guardian and a qualified nutrition professional. Weight-loss targets are not supported.", symbol: "person.2.fill", color: BoxStyle.strength)
                    }
                    Text("Generating shares these details and your training context for AI analysis. The accepted targets and profile stay on this iPhone.")
                        .font(.footnote).foregroundStyle(BoxStyle.muted)
                    if working {
                        HStack(spacing: 10) { ProgressView().tint(BoxStyle.coach); Text("Preparing your targets…").font(.subheadline); Spacer()
                            Button("Cancel") { request?.cancel() }.font(.subheadline.weight(.semibold)) }
                            .boxPanel(tint: BoxStyle.coach)
                    } else {
                        PrimaryButton(title: proposal == nil ? "Generate targets" : "Regenerate targets", symbol: "sparkles") { generate() }.disabled(!input.isValid)
                    }
                    if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
                    if let originalInput = generatedInput, let binding = Binding($proposal) {
                        NutritionProposalEditor(proposal: binding)
                        if let proposal {
                            let errors = proposal.errors(input: originalInput)
                            ForEach(errors, id: \.self) { Text($0).font(.footnote).foregroundStyle(BoxStyle.accent) }
                            PrimaryButton(title: "Accept daily targets", symbol: "checkmark") {
                                if store.acceptNutritionTargets(proposal, input: originalInput) { BoxHaptics.success(); dismiss() }
                                else { error = store.storageNotice; store.storageNotice = nil }
                            }.disabled(!errors.isEmpty || input != originalInput || working)
                            if input != originalInput { Text("Your details changed. Generate a new proposal before accepting.").font(.footnote).foregroundStyle(BoxStyle.muted) }
                        }
                    }
                }
            }.boxPage()
        }.boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Nutrition plan").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear {
            guard !seeded else { return }; seeded = true
            if let data = store.profile.nutritionInputData, let saved = try? JSONDecoder().decode(NutritionPlanningInput.self, from: data) { input = saved }
        }
        .onDisappear { request?.cancel() }
    }
    private func generate() {
        request?.cancel(); working = true; error = nil; proposal = nil; generatedInput = nil
        let details = input
        let training = store.planningContext()
        let acceptedTraining = store.plan.filter { $0.date >= Calendar.current.startOfDay(for: .now) }.prefix(14).map {
            "\($0.date.ISO8601Format()): \($0.displayTitle), \($0.session?.estimatedSeconds ?? $0.configuration.totalSeconds) planned seconds"
        }.joined(separator: "\n")
        request = Task {
            defer { working = false }
            do {
                let result = try await QwenClient().proposeNutritionTargets(input: details, training: training, acceptedTraining: acceptedTraining)
                try Task.checkCancellation(); proposal = result; generatedInput = details
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct NutritionInputFields: View {
    @Binding var input: NutritionPlanningInput
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BoxFeatureLabel(title: "Your starting point", symbol: "person.crop.circle", color: BoxStyle.strength)
            HStack {
                Text("Age").font(.subheadline); Spacer()
                TextField("Years", value: $input.age, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).boxNumber(20).frame(maxWidth: 120)
                Text("yrs").font(.caption).foregroundStyle(BoxStyle.muted).frame(width: 30, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
            NutrientField(title: "Height", unit: "cm", value: $input.heightCm)
            NutrientField(title: "Weight", unit: "kg", value: $input.weightKg)
            Picker("Sex (optional)", selection: $input.sex) { ForEach(["Prefer not to say", "Female", "Male"], id: \.self) { Text($0).tag($0) } }.tint(BoxStyle.ink)
            Picker("Daily activity", selection: $input.activity) { ForEach(["Light daily activity", "Moderate daily activity", "Very active days"], id: \.self) { Text($0).tag($0) } }.tint(BoxStyle.ink)
            BoxChip(text: "\(input.goal)", symbol: "target", color: BoxStyle.strength)
            TextField("Preferences or context", text: $input.notes, axis: .vertical)
                .padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
        }.font(.subheadline).boxPanel(padding: 18)
    }
}

private struct NutritionProposalEditor: View {
    @Binding var proposal: NutritionTargetProposal
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BoxFeatureLabel(title: "Review your targets", symbol: "slider.horizontal.3", color: BoxStyle.coach)
                Spacer()
                BoxChip(text: "AI estimate", color: BoxStyle.coach)
            }
            NutrientField(title: "Calories", unit: "kcal", value: $proposal.calories)
            NutrientField(title: "Protein", unit: "g", value: $proposal.protein)
            NutrientField(title: "Carbohydrate", unit: "g", value: $proposal.carbs)
            NutrientField(title: "Fat", unit: "g", value: $proposal.fat)
            HStack {
                Text("Water").font(.subheadline); Spacer()
                TextField("ml", value: $proposal.waterMl, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).boxNumber(20).frame(maxWidth: 120)
                Text("ml").font(.caption).foregroundStyle(BoxStyle.muted).frame(width: 30, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
            Text(proposal.explanation).font(.subheadline)
            Text(proposal.assumptions).font(.footnote).foregroundStyle(BoxStyle.muted)
            Text("Suggested targets · Not yet accepted").boxEyebrow(BoxStyle.coach)
        }.boxPanel(padding: 18, tint: BoxStyle.coach)
    }
}
