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
    @Attribute(.unique) var id: UUID
    var videoID: UUID
    var date: Date
    var startSeconds: Double
    var endSeconds: Double
    var model: String
    var payload: Data
    init(videoID: UUID, start: Double, end: Double, model: String, draft: VideoReviewDraft) throws {
        id = UUID(); self.videoID = videoID; date = .now; startSeconds = start; endSeconds = end
        self.model = model; payload = try JSONEncoder().encode(draft)
    }
}
