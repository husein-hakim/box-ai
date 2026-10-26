import Foundation
import SwiftData

struct VideoReviewDraft: Codable, Sendable {
    struct Observation: Codable, Identifiable, Sendable {
        let id = UUID()
        let seconds: Double
        let observation: String
        let suggestion: String
        let uncertainty: String
        let drillID: String?
        enum CodingKeys: String, CodingKey { case seconds, observation, suggestion, uncertainty, drillID }
    }
    let summary: String
    let observations: [Observation]
    func isValid(start: Double, end: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start && end - start <= 30.01 && !summary.isEmpty && summary.count <= 4000 && observations.count <= 12 && observations.allSatisfy {
            $0.seconds.isFinite && $0.seconds >= start && $0.seconds <= end &&
            !$0.observation.isEmpty && $0.observation.count <= 2000 && !$0.uncertainty.isEmpty &&
            $0.suggestion.count <= 2000 && ($0.drillID == nil || ["jab-reset-v1", "jab-cross-reset-v1"].contains($0.drillID!))
        }
    }
}

@Model final class AIClipReport {
    var id: UUID = UUID()
    var videoID: UUID = UUID()
    var date: Date = Date.now
    var startSeconds: Double = 0
    var endSeconds: Double = 0
    var model: String = ""
    var payload: Data = Data()
    /// "frames-v1" (legacy observations), "review-2" (ClipReview) or "style-1" (FighterStyle).
    var kind: String = "frames-v1"
    init(videoID: UUID, start: Double, end: Double, model: String, draft: VideoReviewDraft) throws {
        id = UUID(); self.videoID = videoID; date = .now; startSeconds = start; endSeconds = end
        self.model = model; payload = try JSONEncoder().encode(draft)
    }
    init(videoID: UUID, start: Double, end: Double, model: String, kind: String, payload: Data) {
        id = UUID(); self.videoID = videoID; date = .now; startSeconds = start; endSeconds = end
        self.model = model; self.kind = kind; self.payload = payload
    }
    var review: ClipReview? { kind == "review-2" ? try? JSONDecoder().decode(ClipReview.self, from: payload) : nil }
    var style: FighterStyle? { kind == "style-1" ? try? JSONDecoder().decode(FighterStyle.self, from: payload) : nil }
}
