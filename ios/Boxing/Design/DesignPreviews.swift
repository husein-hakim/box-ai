#if DEBUG
import SwiftUI

/// Debug-only design QA. Launch with `-boxScreen <name>` to open one screen on an in-memory store.
struct DesignQARouter: View {
    let name: String
    @State private var store: AppStore? = try? AppStore(container: LocalDatabase.open(inMemory: true), defaults: UserDefaults(suiteName: "box.design-qa") ?? .standard)

    static var requested: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-boxScreen"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private var drill: CatalogActivity { ActivityCatalog.find("jab-reset-v1") ?? ActivityCatalog.all[0] }
    private var guidedLaunch: SessionLaunch {
        let session = GuidedSession(title: "Jab foundations", type: .technique, activities: [
            .init(id: "a", activityID: drill.id, mode: .shadowboxing, sets: 2, reps: 0, workSeconds: 60, restSeconds: 30),
            .init(id: "b", activityID: ActivityCatalog.find("cross-reset-v1")?.id ?? drill.id, mode: .shadowboxing, sets: 2, reps: 0, workSeconds: 60, restSeconds: 30)
        ])
        return SessionLaunch(configuration: .init(), focus: .mixed, execution: .init(session: session))
    }

    var body: some View {
        if let store {
            switch name {
            case "rounds": SessionPlayer(launch: SessionLaunch(configuration: .init(), focus: .mixed), voiceEnabled: false, store: store)
            case "rounds-live": LiveRoundQA(store: store)
            case "guided": SessionPlayer(launch: guidedLaunch, voiceEnabled: false, store: store)
            case "guided-live": GuidedLiveQA(store: store, launch: guidedLaunch)
            case "pads": NavigationStack { PadTrainingSetupView(store: store, activityID: nil) }
            case "settings": NavigationStack { SettingsSheet(store: store) }
            case "coach": NavigationStack { CoachChatView(store: store) }
            case "workouts": NavigationStack { WorkoutLibraryView(store: store) }
            case "plan": NavigationStack { WeeklyPlanView(store: store, sheet: .constant(nil)) }
            case "builder": NavigationStack { SessionBuilderSheet(store: store) }
            case "schedule": NavigationStack { ScheduleSheet(store: store) }
            case "profile": NavigationStack { TrainingProfileEditor(store: store) }
            case "meal": NavigationStack { MealEditor(store: store, date: .now) }
            case "estimate": NavigationStack { FoodEstimateView(store: store, date: .now) }
            case "nutrition": NavigationStack { NutritionPlanningView(store: store) }
            case "barcode": NavigationStack { BarcodeFoodView(store: store, date: .now) }
            case "subscription": NavigationStack { SubscriptionView() }
            case "camera": NavigationStack { CameraCaptureView(store: store) }
            case "drill": NavigationStack { ActivityDetailView(store: store, activity: drill) }
            default: AppShell(store: store)
            }
        } else {
            Text("Design QA store unavailable")
        }
    }
}

private struct LiveRoundQA: View {
    let store: AppStore
    var body: some View {
        SessionPlayer(launch: SessionLaunch(configuration: .init(rounds: 3, workSeconds: 60, restSeconds: 30, cueInterval: 5), focus: .mixed), voiceEnabled: false, store: store, autoBegin: true)
    }
}

private struct GuidedLiveQA: View {
    let store: AppStore
    let launch: SessionLaunch
    var body: some View {
        SessionPlayer(launch: launch, voiceEnabled: false, store: store, autoBegin: true)
    }
}
#endif
