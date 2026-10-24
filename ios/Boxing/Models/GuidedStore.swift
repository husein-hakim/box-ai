import Foundation
import SwiftData

extension AppStore {
    var activityEquipment: [String] {
        // Old profile values stay intact; map only explicit selections, never assume gloves/wraps.
        let selected = profile.equipment.map { $0 == "Heavy bag" ? "Punch bag" : $0 }
        return Array(Set(selected + (profile.space == "Outdoor space" ? ["Outdoor space"] : [])))
    }
    var hasOpenSpace: Bool { profile.space != "Small indoor space" }
    var activityDifficulty: ActivityDifficulty { profile.experience == "Beginner" ? .beginner : .intermediate }
    func sessionErrors(_ session: GuidedSession) -> [String] {
        session.validationErrors(equipment: activityEquipment, openSpace: hasOpenSpace, difficulty: activityDifficulty, budget: profile.sessionMinutes * 60)
    }
    func start(_ session: GuidedSession, assignmentID: UUID? = nil) {
        guard !session.activities.isEmpty else { storageNotice = "This is a rest day. No guided activities are prescribed."; return }
        let errors = sessionErrors(session)
        guard errors.isEmpty else { storageNotice = errors.joined(separator: "\n"); return }
        let launch = SessionLaunch(configuration: .init(), focus: .mixed, execution: .init(session: session, assignmentID: assignmentID), assignmentID: assignmentID)
        present(launch)
    }
    func assignmentRecord(_ assignment: PlannedPractice) -> SessionRecord? {
        history.first { $0.id == assignment.completionID }
    }
    func assignmentIsComplete(_ assignment: PlannedPractice) -> Bool {
        guard let record = assignmentRecord(assignment) else { return false }
        return record.finished && (record.guided != nil || record.skippedBlocks == 0)
    }
    func startAssignment(_ assignment: PlannedPractice) {
        guard !assignmentIsComplete(assignment) else { return }
        if let pendingSession, pendingSession.assignmentID == assignment.id { activeSession = pendingSession; return }
        if let session = assignment.session { start(session, assignmentID: assignment.id) }
        else if assignment.sessionData != nil { storageNotice = "This saved session could not be opened. Its data has been kept; your other training is still available." }
        else { present(SessionLaunch(configuration: assignment.configuration, focus: assignment.focus, assignmentID: assignment.id)) }
    }
    func assignmentProgress(_ assignment: PlannedPractice) -> String? {
        let execution = pendingSession?.assignmentID == assignment.id ? pendingSession?.execution : assignmentRecord(assignment)?.guided?.execution
        guard let execution else { return nil }
        let completed = execution.results.indices.filter { execution.outcome(at: $0) == .completed }.count
        return "\(completed) of \(execution.session.activities.count) activities complete · \(execution.session.activities.count - completed) remaining"
    }
    func nextAssignment(after record: SessionRecord) -> PlannedPractice? {
        let origin = plan.first { $0.id == record.assignmentID }?.date ?? Calendar.current.startOfDay(for: .now)
        return plan.first { $0.id != record.assignmentID && $0.date >= origin && !assignmentIsComplete($0) && !($0.session?.activities.isEmpty ?? false) }
    }
    func present(_ launch: SessionLaunch) {
        if pendingSession != nil { replacementSession = launch } else { activeSession = launch }
    }
    func saveExecution(launch: SessionLaunch, execution: GuidedExecution) {
        guard execution.phase != .briefing, execution.isValidCheckpoint else { return }
        do {
            let draft = try context.fetch(FetchDescriptor<SavedSessionDraft>()).first ?? SavedSessionDraft()
            draft.padData = nil
            draft.sessionID = launch.id; draft.assignmentID = execution.assignmentID
            draft.executionData = try JSONEncoder().encode(execution)
            if draft.modelContext == nil { context.insert(draft) }
            try context.save()
            try reload()
        } catch { failedSave() }
    }

    func startPad(_ configuration: PadConfiguration, assignmentID: UUID? = nil) {
        guard configuration.isValid else { storageNotice = "This camera practice configuration is unavailable."; return }
        var launch = SessionLaunch(configuration: .init(), focus: configuration.activityID == "jab-reset-v1" ? .jab : .straightCombination, assignmentID: assignmentID)
        launch.pad = PadTrainingState(configuration: configuration)
        present(launch)
    }

    func savePad(launch: SessionLaunch, state: PadTrainingState) {
        guard state.phase != .briefing, state.isValidCheckpoint else { return }
        do {
            let draft = try context.fetch(FetchDescriptor<SavedSessionDraft>()).first ?? SavedSessionDraft()
            draft.sessionID = launch.id; draft.assignmentID = launch.assignmentID; draft.executionData = nil
            draft.padData = try JSONEncoder().encode(state)
            if draft.modelContext == nil { context.insert(draft) }
            try context.save(); try reload()
        } catch { failedSave() }
    }
}
