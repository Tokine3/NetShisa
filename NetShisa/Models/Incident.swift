import Foundation
import SwiftData

@Model
final class Incident {
    var id: UUID
    var classification: String
    var startTime: Date
    var endTime: Date?
    var notes: String?

    init(
        classification: String,
        startTime: Date,
        endTime: Date? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.classification = classification
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
    }

    var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    var isOngoing: Bool {
        endTime == nil
    }
}
