import Foundation
import Testing
@testable import BoxingCore

// Opt in only. Fictional profiles are sent; credentials and response text are never printed.
struct LiveAIIntegrationTests {
    private func client() -> QwenClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 150; configuration.timeoutIntervalForResource = 180
        return QwenClient(transport: URLSession(configuration: configuration))
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BOX_RUN_AI_INTEGRATION"] == "1"))
    @MainActor func liveTrainingDraftUsesOnlyExecutableCatalog() async throws {
        let store = try AppStore(container: LocalDatabase.open(inMemory: true))
        store.selectedDays = [2, 4, 6]; store.stance = "Orthodox"
        let context = store.planningContext(feedback: "Integration test with a fictional beginner. Easy shadowboxing. No injuries or medical needs.")
        let proposal = try await client().proposeTrainingPlan(context: context)
        #expect(proposal.errors(context: context).isEmpty)
        #expect(store.acceptTrainingPlan(proposal, context: context))
        #expect(store.plan.count == 7 && store.plan.allSatisfy { $0.session != nil })
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BOX_RUN_AI_INTEGRATION"] == "1"))
    @MainActor func liveNutritionEstimateUsesTypedReviewContract() async throws {
        let store = try AppStore(container: LocalDatabase.open(inMemory: true))
        let input = NutritionPlanningInput(age: 30, heightCm: 175, weightKg: 75, activity: "Moderate daily activity", sex: "Male", notes: "Fictional integration-test profile. Healthy adult, no medical concerns; easy boxing three days a week.")
        let proposal = try await client().proposeNutritionTargets(input: input, training: store.planningContext(), acceptedTraining: "No assignments accepted. Fictional easy beginner practice planned three times a week.")
        #expect(proposal.errors(input: input).isEmpty)
        #expect(store.acceptNutritionTargets(proposal, input: input))
        #expect(store.targets.proposalData != nil)
    }
}
