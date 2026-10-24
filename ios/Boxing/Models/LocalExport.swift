import Foundation
import SwiftData

extension AppStore {
    func exportRecords() throws -> Data {
        let sessionJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(history))
        let unfinished: Any
        if let pending = pendingSession, let pad = pending.pad {
            unfinished = ["id": pending.id.uuidString, "pad": try JSONSerialization.jsonObject(with: JSONEncoder().encode(pad))] as [String: Any]
        } else if let pending = pendingSession, let checkpoint = pending.checkpoint {
            unfinished = ["id": pending.id.uuidString, "focus": pending.focus.rawValue,
                          "configuration": try JSONSerialization.jsonObject(with: JSONEncoder().encode(pending.configuration)),
                          "checkpoint": try JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint))] as [String: Any]
        } else if let pending = pendingSession, let execution = pending.execution {
            unfinished = ["id": pending.id.uuidString, "execution": try JSONSerialization.jsonObject(with: JSONEncoder().encode(execution))] as [String: Any]
        } else { unfinished = NSNull() }
        let archive: [String: Any] = [
            "format": "BOX.local-records", "version": 2, "exportedAt": Date.now.ISO8601Format(),
            "note": "Record export only. Video files are not embedded. This file can contain private training, food and chat data. Import/restore is not implemented yet.",
            "preferences": ["trainingDays": selectedDays.sorted(), "voiceEnabled": voiceEnabled, "stance": stance],
            "profile": ["name": profile.name, "experience": profile.experience, "goal": profile.goal, "equipment": profile.equipment, "space": profile.space, "sessionMinutes": profile.sessionMinutes],
            "sessions": sessionJSON, "unfinishedSession": unfinished,
            "acceptedTrainingPlans": try context.fetch(FetchDescriptor<AcceptedTrainingPlan>()).map {
                ["id": $0.id.uuidString, "acceptedAt": $0.acceptedAt.ISO8601Format(),
                 "proposal": try JSONSerialization.jsonObject(with: $0.payload), "context": try JSONSerialization.jsonObject(with: $0.contextPayload)] as [String: Any]
            },
            "nutritionProposal": try targets.proposalData.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
            "nutritionPlanningInput": try profile.nutritionInputData.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
            "nutritionTargets": ["calories": targets.calories, "protein": targets.protein, "carbs": targets.carbs, "fat": targets.fat, "waterMl": Double(targets.water)],
            "meals": meals.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "name": $0.name, "serving": $0.serving, "calories": $0.calories, "protein": $0.protein, "carbs": $0.carbs, "fat": $0.fat, "source": $0.source, "assumptions": $0.assumptions] as [String: Any] },
            "water": waterEntries.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "millilitres": $0.millilitres] as [String: Any] },
            "plan": plan.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "focus": $0.focusRaw, "rounds": $0.rounds, "workSeconds": $0.workSeconds, "restSeconds": $0.restSeconds, "source": $0.source, "note": $0.note, "sessionData": $0.sessionData?.base64EncodedString() ?? "", "completionID": $0.completionID?.uuidString ?? "", "planID": $0.planID?.uuidString ?? ""] as [String: Any] },
            "workouts": workouts.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "routineID": $0.routineID, "title": $0.title, "completedExerciseIDs": $0.exerciseIDs, "notes": $0.notes] as [String: Any] },
            "workoutPlans": workoutPlans.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "title": $0.title, "routineIDs": $0.routineIDs, "reason": $0.reason] as [String: Any] },
            "workoutDrafts": workoutDrafts.map { ["routineID": $0.routineID, "completedExerciseIDs": $0.exerciseIDs, "notes": $0.notes] as [String: Any] },
            "coachMessages": messages.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "role": $0.role, "text": $0.text] },
            "videos": videos.map { ["id": $0.id.uuidString, "date": $0.date.ISO8601Format(), "title": $0.title, "filename": $0.filename, "kind": $0.kind, "notes": $0.notes, "subjectCode": $0.subjectCode, "setupCode": $0.setupCode] },
            "aiVideoReports": try reports.map { ["id": $0.id.uuidString, "videoID": $0.videoID.uuidString, "date": $0.date.ISO8601Format(), "startSeconds": $0.startSeconds, "endSeconds": $0.endSeconds, "model": $0.model, "report": try JSONSerialization.jsonObject(with: $0.payload)] as [String: Any] },
            "manualAnnotations": markers.map { ["id": $0.id.uuidString, "videoID": $0.videoID.uuidString, "startSeconds": $0.startSeconds, "endSeconds": $0.endSeconds, "action": $0.action, "note": $0.note] as [String: Any] }
        ]
        return try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys])
    }

    func activeDays(ending date: Date = .now, count: Int = 7, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        let dates = history.filter { $0.workSeconds > 0 }.map(\.date) + workouts.map(\.date)
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.filter { days.contains($0) }.count
    }
    func activityStreak(ending date: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set((history.filter { $0.workSeconds > 0 }.map(\.date) + workouts.map(\.date)).map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: date)
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
