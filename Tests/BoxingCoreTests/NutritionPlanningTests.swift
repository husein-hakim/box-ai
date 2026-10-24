import Foundation
import Testing
@testable import BoxingCore

struct NutritionPlanningTests {
    func proposal(age: Int = 30) -> NutritionTargetProposal {
        .init(calories: 2000, protein: 100, carbs: 265, fat: 60, waterMl: 2000, explanation: "Test only", assumptions: "Test only", age: age, purpose: .fueling, estimatedEnergyNeed: 2000)
    }
    @Test func numbersAgeEnergyAndNoDeficitAreValidated() {
        let input = NutritionPlanningInput(age: 30, heightCm: 170, weightKg: 70)
        var value = proposal()
        #expect(value.errors(input: input).isEmpty)
        #expect(!value.errors(input: .init(age: 16, heightCm: 170, weightKg: 60)).isEmpty)
        value.calories = 4000
        #expect(!value.errors(input: input).isEmpty)
        value = proposal(); value.estimatedEnergyNeed = 2200
        #expect(!value.errors(input: input).isEmpty)
        value = proposal(); value.protein = .infinity
        #expect(!value.errors(input: input).isEmpty)
    }
    @Test @MainActor func onlyExplicitValidAcceptanceChangesTargetsAndPersists() throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let store = try AppStore(container: LocalDatabase.open(url: url))
        #expect(store.saveTargets(calories: 1234, protein: 50, carbs: 100, fat: 40, water: 1000))
        var draft = proposal(age: 16)
        let input = NutritionPlanningInput(age: 16, heightCm: 170, weightKg: 60)
        draft.calories = 100
        #expect(!store.acceptNutritionTargets(draft, input: input))
        #expect(store.targets.calories == 1234)
        #expect(store.acceptNutritionTargets(proposal(age: 16), input: input))
        let reopened = try AppStore(container: LocalDatabase.open(url: url))
        #expect(reopened.targets.calories == 2000 && reopened.targets.proposalData != nil)
        #expect(reopened.profile.nutritionInputData != nil)
    }
}
