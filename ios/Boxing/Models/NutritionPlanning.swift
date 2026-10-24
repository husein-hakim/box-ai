import Foundation

/// App-owned numerical and purpose checks. This is not a clinically reviewed target policy.
/// Target proposals and energy estimates come from the configured AI service, never a local formula.
struct NutritionPlanningInput: Codable, Equatable, Sendable {
    var age = 0
    var heightCm: Double = 0
    var weightKg: Double = 0
    var activity = "Light daily activity"
    var sex = "Prefer not to say"
    var goal = "Fuel training and recovery"
    var notes = ""
    var isValid: Bool {
        (1...120).contains(age) && heightCm.isFinite && weightKg.isFinite && (40...260).contains(heightCm) && (10...400).contains(weightKg) &&
        ["Light daily activity", "Moderate daily activity", "Very active days"].contains(activity) &&
        ["Prefer not to say", "Female", "Male"].contains(sex) && goal == "Fuel training and recovery" && notes.count <= 1000
    }
}

struct NutritionTargetProposal: Codable, Equatable, Sendable {
    enum Purpose: String, Codable, Sendable { case fueling }
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var waterMl: Int
    var explanation: String
    var assumptions: String
    var age: Int
    var purpose: Purpose
    var estimatedEnergyNeed: Double
    var macroCalories: Double { protein * 4 + carbs * 4 + fat * 9 }
    func errors(input: NutritionPlanningInput) -> [String] {
        guard input.isValid, age == input.age else { return ["The proposal must match your current profile."] }
        // Broad corruption/sanity limits only; these do not establish individual dietary suitability.
        guard calories.isFinite, estimatedEnergyNeed.isFinite, (500...10_000).contains(calories),
              (500...10_000).contains(estimatedEnergyNeed), [protein, carbs, fat].allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 2000 }),
              (250...10_000).contains(waterMl) else { return ["The proposed numbers need another review. Regenerate the targets."] }
        guard calories >= estimatedEnergyNeed else { return ["This app supports fueling targets, not calorie deficits or weight cuts."] }
        guard abs(macroCalories - calories) <= calories * 0.05 else { return ["Calories and macronutrients do not agree. Review the numbers or regenerate."] }
        if explanation.isEmpty || explanation.count > 2000 || assumptions.isEmpty || assumptions.count > 2000 { return ["The proposal needs a concise explanation and its assumptions."] }
        return []
    }
}

struct NutritionGenerationResponse: Codable, Sendable {
    enum Status: String, Codable, Sendable { case ready, needsSupport }
    let status: Status
    let proposal: NutritionTargetProposal?
    let message: String
}

extension AppStore {
    @discardableResult func acceptNutritionTargets(_ proposal: NutritionTargetProposal, input: NutritionPlanningInput) -> Bool {
        let errors = proposal.errors(input: input)
        guard errors.isEmpty else { storageNotice = errors.joined(separator: "\n"); return false }
        do {
            targets.calories = proposal.calories; targets.protein = proposal.protein; targets.carbs = proposal.carbs
            targets.fat = proposal.fat; targets.water = proposal.waterMl
            targets.proposalData = try JSONEncoder().encode(proposal); targets.acceptedAt = .now
            targets.policyID = "ai-fueling-v1"; profile.nutritionInputData = try JSONEncoder().encode(input)
            return persist()
        } catch { failedSave(); return false }
    }
}
