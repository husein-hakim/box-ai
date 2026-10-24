import SwiftUI
import UIKit

@main
struct BoxingApp: App {
    init() { BoxNavigationAppearance.apply() }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let screen = DesignQARouter.requested { DesignQARouter(name: screen) } else { AppBootstrap() }
                #else
                AppBootstrap()
                #endif
            }
            .preferredColorScheme(.dark).tint(BoxStyle.accent)
        }
    }
}

struct AppBootstrap: View {
    @State private var store: AppStore?
    @State private var error: String?
    var body: some View {
        Group {
            if let store {
                AppShell(store: store)
            } else if let error {
                ContentUnavailableView {
                    Label("Local data unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: { Button("Try again") { open() } }
            } else { ProgressView("Opening your training…") }
        }
        .background(BoxStyle.background)
        .task { if store == nil { open() } }
    }
    private func open() {
        do { store = try AppStore(container: LocalDatabase.open()); error = nil }
        catch { self.error = "Your saved data could not be opened. It has not been erased. \(error.localizedDescription)" }
    }
}

enum AppTab: Hashable { case today, train, review, fuel, progress }
enum AppSheet: String, Identifiable {
    case schedule, builder, settings, coach, camera, profile
    var id: Self { self }
}

struct AppShell: View {
    @Bindable var store: AppStore
    @State private var selectedTab: AppTab = .today
    @State private var sheet: AppSheet?

    var body: some View {
        let replacement = store.replacementSession
        TabView(selection: $selectedTab) {
            Tab("Train", systemImage: "figure.boxing", value: .train) {
                NavigationStack { TrainView(store: store, sheet: $sheet, selectedTab: $selectedTab) }
            }
            Tab("Review", systemImage: "play.rectangle.on.rectangle.fill", value: .review) {
                NavigationStack {
                    ReviewLibraryView(store: store, sheet: $sheet)
                }
            }
            Tab("Today", systemImage: "square.grid.2x2.fill", value: .today) {
                NavigationStack {
                    TodayView(store: store, sheet: $sheet, selectedTab: $selectedTab)
                }
            }
            Tab("Fuel", systemImage: "fork.knife", value: .fuel) {
                NavigationStack {
                    FuelView(store: store)
                }
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: .progress) {
                NavigationStack { ProgressViewScreen(store: store, sheet: $sheet) }
            }
        }
        .onChange(of: selectedTab) { _, _ in BoxHaptics.selection() }
        .sheet(item: $sheet, onDismiss: {
            if let launch = store.queuedSession {
                store.queuedSession = nil
                store.present(launch)
            }
        }) { destination in
            NavigationStack {
                switch destination {
                case .schedule: ScheduleSheet(store: store)
                case .builder: SessionBuilderSheet(store: store)
                case .settings: SettingsSheet(store: store)
                case .profile: TrainingProfileEditor(store: store)
                case .camera: CameraCaptureView(store: store)
                case .coach:
                    CoachChatView(store: store)
                }
            }
            .preferredColorScheme(.dark)
            .tint(BoxStyle.accent)
        }
        .confirmationDialog("You have an unfinished practice", isPresented: Binding(get: { store.replacementSession != nil }, set: { if !$0 { store.replacementSession = nil } }), titleVisibility: .visible) {
            Button("Resume saved practice") { store.activeSession = store.pendingSession; store.replacementSession = nil }
            Button("Discard it & start new", role: .destructive) {
                if store.discardCheckpoint() { store.activeSession = replacement; store.replacementSession = nil }
            }
            Button("Cancel", role: .cancel) { store.replacementSession = nil }
        }
        .alert("Could not save", isPresented: Binding(get: { store.storageNotice != nil }, set: { if !$0 { store.storageNotice = nil } })) {
            Button("OK") { store.storageNotice = nil }
        } message: { Text(store.storageNotice ?? "") }
        .fullScreenCover(item: $store.activeSession, onDismiss: {
            let followUp = store.sessionFollowUp; store.sessionFollowUp = nil
            switch followUp {
            case .today: selectedTab = .today
            case .progress: selectedTab = .progress
            case .assignment(let id):
                if let assignment = store.plan.first(where: { $0.id == id }) { store.startAssignment(assignment) }
            case nil: break
            }
        }) { launch in
            SessionPlayer(launch: launch, voiceEnabled: store.voiceEnabled, store: store)
                .preferredColorScheme(.dark).tint(BoxStyle.accent)
        }
    }
}

/// Condensed italic navigation titles on every pushed screen and sheet. Backgrounds stay native (Liquid Glass).
@MainActor enum BoxNavigationAppearance {
    static func apply() {
        func font(_ size: CGFloat, _ weight: UIFont.Weight, _ width: UIFont.Width) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: weight, width: width)
        }
        let ink = UIColor(BoxStyle.ink)
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: font(19, .heavy, .condensed)), .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font(40, .black, .compressed)), .foregroundColor: ink]
    }
}

struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Done") { dismiss() } }
}

#Preview { AppBootstrap().preferredColorScheme(.dark) }
