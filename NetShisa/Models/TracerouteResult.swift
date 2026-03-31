import Foundation
import SwiftData

@Model
final class TracerouteResult {
    var timestamp: Date
    var target: String
    var ipv6: Bool
    var hopsRaw: String  // JSON-encoded array of TracerouteHop
    var completed: Bool

    init(
        timestamp: Date,
        target: String,
        ipv6: Bool = false,
        hopsRaw: String = "[]",
        completed: Bool = false
    ) {
        self.timestamp = timestamp
        self.target = target
        self.ipv6 = ipv6
        self.hopsRaw = hopsRaw
        self.completed = completed
    }

    var hops: [TracerouteHop] {
        guard let data = hopsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TracerouteHop].self, from: data)
        else { return [] }
        return decoded
    }
}

struct TracerouteHop: Codable, Identifiable {
    var id: Int { hopNumber }
    let hopNumber: Int
    let address: String?
    let hostname: String?
    let latencyMs: [Double]
    let timedOut: Bool
}
