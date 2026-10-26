import Foundation
import SwiftData

extension AppStore {
    var userStance: BoxMaxxingJudge.Stance { stance == "Southpaw" ? .southpaw : .orthodox }

    /// The next planned session that is still to do, if any.
    func upcomingAssignment(after record: SessionRecord) -> PlannedPractice? {
        let today = Calendar.current.startOfDay(for: .now)
        if record.assignmentID != nil { return nextAssignment(after: record) }
        return plan.first { $0.date >= today && !assignmentIsComplete($0) && $0.session?.activities.isEmpty == false }
    }

    /// Facts, the instant debrief and a proposed change to the next session.
    func debriefContext(for record: SessionRecord) -> (facts: SessionFacts, auto: SessionDebrief, next: PlannedPractice?, adjustment: SessionAdjustment?) {
        let facts = SessionFacts.make(record, history: history, stance: userStance)
        let next = upcomingAssignment(after: record)
        let adjustment = next?.session.flatMap { SessionAdjustment.propose(facts: facts, next: $0, stance: userStance, validate: sessionErrors) }
        return (facts, facts.autoDebrief(nextSession: next?.displayTitle), next, adjustment)
    }

    @discardableResult func saveDebrief(_ debrief: SessionDebrief, for recordID: UUID) -> Bool {
        do {
            guard let row = try context.fetch(FetchDescriptor<SavedPractice>()).first(where: { $0.id == recordID }) else { return false }
            var record = try row.record()
            record.debrief = debrief
            row.payload = try JSONEncoder().encode(record)
            try commit(); return true
        } catch { failedSave(); return false }
    }

    /// Replaces an upcoming assignment's session with a validated adjustment.
    @discardableResult func apply(_ adjustment: SessionAdjustment, to assignment: PlannedPractice) -> Bool {
        guard assignment.completionID == nil, sessionErrors(adjustment.session).isEmpty else { return false }
        do {
            assignment.sessionData = try JSONEncoder().encode(adjustment.session)
            let note = String(localized: "Adjusted after your last session: \(adjustment.summary)")
            assignment.note = String((note + (assignment.note.isEmpty ? "" : "\n" + assignment.note)).prefix(1000))
            try commit(); return true
        } catch { failedSave(); return false }
    }
}
