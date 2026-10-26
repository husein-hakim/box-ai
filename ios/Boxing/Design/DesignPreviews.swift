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

    private var arenaLaunch: SessionLaunch {
        var launch = SessionLaunch(configuration: .init(), focus: .mixed)
        var pad = PadTrainingState(configuration: PadConfiguration(level: .intermediate))
        pad.begin()
        launch.pad = pad
        return launch
    }

    var body: some View {
        if let store {
            switch name {
            case "rounds": SessionPlayer(launch: SessionLaunch(configuration: .init(), focus: .mixed), voiceEnabled: false, store: store)
            case "rounds-live": LiveRoundQA(store: store)
            case "guided": SessionPlayer(launch: guidedLaunch, voiceEnabled: false, store: store)
            case "guided-live": GuidedLiveQA(store: store, launch: guidedLaunch)
            case "pads": NavigationStack { PadTrainingSetupView(store: store, activityID: nil) }
            case "arena": SessionPlayer(launch: arenaLaunch, voiceEnabled: false, store: store)
            case "hud-framing": PadArenaGallery(state: "framing")
            case "hud-countdown": PadArenaGallery(state: "countdown")
            case "hud-cue": PadArenaGallery(state: "cue")
            case "hud-hit": PadArenaGallery(state: "hit")
            case "hud-miss": PadArenaGallery(state: "miss")
            case "hud-mitt": PadArenaGallery(state: "mitt")
            case "spar": NavigationStack { SparringSetupView(store: store) }
            case "spar-demo": SparringArenaView(store: store, configuration: .init(difficulty: .contender, rounds: 1, roundSeconds: 45), demo: true)
            case "program": NavigationStack { ProgramBuilderView(store: store) }
            case "debrief": ProgressionQA(store: store) { DebriefQA(store: store) }
            case "next-week": ProgressionQA(store: store) { NavigationStack { ProgramBuilderView(store: store, nextWeek: true) } }
            case "spar-unlocks": ProgressionQA(store: store) { NavigationStack { SparringSetupView(store: store) } }
            case "drills": NavigationStack { DrillLibraryView(store: store) }
            case "train": NavigationStack { TrainView(store: store, sheet: .constant(nil), selectedTab: .constant(.train)) }
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
            case "progression": ProgressionQA(store: store) { NavigationStack { ProgressViewScreen(store: store, sheet: .constant(nil)) } }
            case "today-xp": ProgressionQA(store: store) { NavigationStack { TodayView(store: store, sheet: .constant(nil), selectedTab: .constant(.today)) } }
            case "awards": ProgressionQA(store: store) { ScrollView { VStack { AwardsSection(state: store.progression); RecentXPSection(state: store.progression) }.boxPage() }.boxScreen() }
            case "review-tab": NavigationStack { ReviewLibraryView(store: store, sheet: .constant(nil)) }
            case "review-report": NavigationStack { ScrollView { ClipReviewReport(store: store, review: ReportFixtures.review).boxPage() }.boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink).navigationTitle("Coach review").navigationBarTitleDisplayMode(.inline) }
            case "style-report": NavigationStack { ScrollView { FighterStyleReport(store: store, style: ReportFixtures.style).boxPage() }.boxScreen(tint: BoxStyle.strength).foregroundStyle(BoxStyle.ink).navigationTitle("Style study").navigationBarTitleDisplayMode(.inline) }
            case "ranks": ProgressionQA(store: store) { NavigationStack { RankLadderView(state: store.progression, unlocks: store.unlocks) } }
            case "celebrate": ProgressionQA(store: store) { ProgressionCelebrationView(celebration: .init(kind: .rank(store.progression.rank)), state: store.progression) {} }
            case "drill": NavigationStack { ActivityDetailView(store: store, activity: drill) }
            default: AppShell(store: store)
            }
        } else {
            Text("Design QA store unavailable")
        }
    }
}

enum ReportFixtures {
    static let motion = ClipMotion(durationSeconds: 20, trackedShare: 0.94, feetVisibleShare: 0.9, moves: [
        .init(seconds: 2.1, action: .straight(.left), confidence: 0.9, otherHandLow: false, droppedAfter: false),
        .init(seconds: 2.5, action: .straight(.right), confidence: 0.85, otherHandLow: true, droppedAfter: false),
        .init(seconds: 6.4, action: .hook(.left), confidence: 0.8, otherHandLow: true, droppedAfter: true),
        .init(seconds: 9.0, action: .slip(.right), confidence: 0.7, otherHandLow: false, droppedAfter: false),
        .init(seconds: 12.2, action: .straight(.left), confidence: 0.9, otherHandLow: false, droppedAfter: false),
        .init(seconds: 12.6, action: .straight(.right), confidence: 0.9, otherHandLow: false, droppedAfter: false),
        .init(seconds: 13.0, action: .hook(.left), confidence: 0.8, otherHandLow: true, droppedAfter: false)
    ], guardShare: 0.71, stanceWidth: 1.4, footworkRate: 0.22, headMovement: 0.12)
    static let review = ClipReview(status: "ok", headline: "Sharp one-two, rear hand drifts on hooks", summary: "Your jab–cross is quick and you reset your feet well. When you throw the lead hook your right hand slides down to your chest, which leaves your chin open to a counter. Fix that and your combinations become much safer.",
        scores: .init(overall: 64, offense: 70, defense: 52, footwork: 66, guardScore: 58), scoreBasis: "Clean straights, but the guard opens on hooks.", confidence: "medium",
        strengths: [.init(seconds: 2.3, title: "Snappy one-two", detail: "Both hands come back fast and your weight stays centred.")],
        fixes: [.init(seconds: 6.4, title: "Rear hand drops on the hook", why: "An opponent's left hook lands on an open chin.", cue: "Glove on cheek", drillID: "one-two-hook-v1"),
                .init(seconds: nil, title: "Head stays on the centre line", why: "After punching you're still where they aim.", cue: "Punch, then move your head", drillID: "slip-v1")],
        moments: [.init(seconds: 2.3, text: "Fast jab–cross with a good reset.", positive: true), .init(seconds: 6.4, text: "Right hand at chest height during the hook.", positive: false), .init(seconds: 9.0, text: "Nice small slip, eyes forward.", positive: true)],
        unobservable: ["Feet partly out of frame at the end"], setting: .shadowboxing, motion: motion, segmentStart: 0, segmentEnd: 20)
    static let style = FighterStyle(status: "ok", fighter: "Muhammad Ali", recognised: true, stance: "orthodox", archetype: "Out-boxer",
        summary: "Controls range with constant movement and a fast, stiff jab, then makes opponents miss with pull-backs and lateral footwork before countering with straight punches.",
        traits: [.init(title: "Always moving", detail: "Circle off the centre line after every exchange. Train step-slides and pivots for volume.", seconds: 4.1, source: "clip"),
                 .init(title: "Jab that leads everything", detail: "Double and triple jabs to measure distance and blind. Practise jab–step and double jab.", seconds: 8.7, source: "clip"),
                 .init(title: "Pull-back counter", detail: "Leans back out of range, then fires a straight right. Learn it with slips first.", seconds: nil, source: "known")],
        emphasis: .init(jab: 95, power: 45, combinations: 65, headMovement: 85, footwork: 100, pressure: 15, counters: 85, guardScore: 35),
        signatureCombos: [["jab", "jab", "cross"], ["slipLead", "cross"], ["jab", "cross", "leadHook"]],
        drillIDs: ["step-slide-v1", "pivot-v1", "double-jab-v1", "jab-step-v1", "slip-v1"],
        conditioning: "High aerobic volume and leg endurance for constant movement across every round.",
        fuelNote: "Regular carbohydrate before sessions fuels high-volume footwork.",
        caution: "Ali kept his hands low and leaned back. Keep your guard up while you learn; add pull-backs only once slips are solid.")
}

/// Seeds two weeks of real-looking saved work so progression screens have data.
private struct ProgressionQA<Content: View>: View {
    let store: AppStore
    @ViewBuilder let content: () -> Content
    @State private var seeded = false
    var body: some View {
        Group { if seeded { content() } else { Color.black } }
            .onAppear {
                guard !seeded else { return }
                let calendar = Calendar.current
                for day in 0..<12 where day != 4 {
                    guard let date = calendar.date(byAdding: .day, value: -day, to: .now) else { continue }
                    let sparring = day.isMultiple(of: 3) ? SparringSummary(configuration: .init(difficulty: .contender, rounds: 2, roundSeconds: 60), score: 4200 + day * 300, maxStreak: 28, hits: 60, attempts: 66, perfects: 30, roundsCompleted: 2, activeSeconds: 120) : nil
                    _ = store.record(SessionRecord(id: UUID(), date: date, focus: .mixed, activeSeconds: 1500, workSeconds: 1500, completedRounds: 6, skippedBlocks: 0, issuedCues: 40, finished: true, sparring: sparring))
                }
                seeded = true
            }
    }
}

private struct DebriefQA: View {
    let store: AppStore
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let record = store.history.first(where: { $0.sparring != nil }) {
                    XPEarnedCard(store: store, sessionID: record.id)
                    CoachDebriefCard(store: store, recordID: record.id, onDark: true)
                }
            }.padding(20)
        }
        .background { Rectangle().fill(.black.opacity(0.85)).ignoresSafeArea() }
        .foregroundStyle(.white)
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
