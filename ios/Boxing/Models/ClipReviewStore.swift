import Foundation

extension AppStore {
    /// Saved coaching reviews of the user's own clips, newest first.
    var clipReviews: [(report: AIClipReport, review: ClipReview)] { reports.compactMap { r in r.review.map { (r, $0) } } }
    /// Saved fighter style studies, newest first.
    var styleStudies: [(report: AIClipReport, style: FighterStyle)] { reports.compactMap { r in r.style.map { (r, $0) } } }

    /// The style the program leans toward, if the user picked one.
    var styleFocus: StyleFocus? {
        get { profile.styleFocusData.flatMap { try? JSONDecoder().decode(StyleFocus.self, from: $0) } }
        set { profile.styleFocusData = newValue.flatMap { try? JSONEncoder().encode($0) }; persist() }
    }

    /// Main corrections from the last three usable reviews, for plans and the coach.
    var reviewFocus: [String] {
        clipReviews.filter { !$0.review.isRejected }.prefix(3).flatMap { item in
            item.review.fixes.prefix(1).map { "\($0.title) (cue: \($0.cue))" }
        }
    }

    /// Short history for the review prompt, so the coach can comment on progress.
    var reviewHistoryText: String {
        clipReviews.filter { !$0.review.isRejected }.prefix(4).map { item in
            let score = item.review.scores.map { " overall \($0.overall)" } ?? ""
            return "\(item.report.date.formatted(.dateTime.month(.abbreviated).day())): \(item.review.headline);\(score); main fix: \(item.review.fixes.first?.title ?? "none")"
        }.joined(separator: "\n")
    }

    var profileSummary: String {
        let stanceText = stance.isEmpty ? "Orthodox" : stance
        return "\(profile.experience) boxer, \(stanceText.lowercased()) stance, goal: \(profile.goal). Equipment: \(profile.equipment.isEmpty ? "none" : profile.equipment.joined(separator: ", ")). Sessions of \(profile.sessionMinutes) minutes."
    }

    @discardableResult func saveClipReview(video: LocalVideo, review: ClipReview, model: String) -> AIClipReport? {
        save(video: video, start: review.segmentStart ?? 0, end: review.segmentEnd ?? 0, model: model, kind: "review-2", value: review)
    }
    @discardableResult func saveStyleStudy(video: LocalVideo, style: FighterStyle, model: String) -> AIClipReport? {
        save(video: video, start: style.segmentStart ?? 0, end: style.segmentEnd ?? 0, model: model, kind: "style-1", value: style)
    }
    func deleteReport(_ report: AIClipReport) { context.delete(report); persist() }

    private func save<T: Encodable>(video: LocalVideo, start: Double, end: Double, model: String, kind: String, value: T) -> AIClipReport? {
        do {
            let report = AIClipReport(videoID: video.id, start: start, end: end, model: model, kind: kind, payload: try JSONEncoder().encode(value))
            context.insert(report); try commit(); return report
        } catch { failedSave(); return nil }
    }
}
