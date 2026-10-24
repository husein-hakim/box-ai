import Foundation
import SwiftData

struct SessionCheckpoint: Codable {
    let timeline: RoundTimeline
    let issuedCues: Int
    let cueIndex: Int
    let cueRaw: String
    func isValid(configuration: RoundConfiguration) -> Bool {
        timeline.isValidCheckpoint(configuration: configuration) && (0...100_000).contains(issuedCues) &&
        (0...100_000).contains(cueIndex) && ["jab", "cross", "oneTwo", "reset"].contains(cueRaw)
    }
}

@Model final class SavedSessionDraft {
    @Attribute(.unique) var key: String
    var sessionID: UUID
    var focusRaw: String
    var configuration: Data
    var checkpoint: Data
    var executionData: Data?
    var padData: Data?
    var assignmentID: UUID?
    init() { key = "active"; sessionID = UUID(); focusRaw = "mixed"; configuration = Data(); checkpoint = Data() }
}
