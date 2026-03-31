import Foundation
import SwiftData

@Model
final class ServiceResult {
    var timestamp: Date
    var serviceName: String
    var hostname: String
    var port: Int
    var ipv4Reachable: Bool?
    var ipv6Reachable: Bool?
    var ipv4LatencyMs: Double?
    var ipv6LatencyMs: Double?
    var errorDescription: String?

    init(
        timestamp: Date,
        serviceName: String,
        hostname: String,
        port: Int,
        ipv4Reachable: Bool? = nil,
        ipv6Reachable: Bool? = nil,
        ipv4LatencyMs: Double? = nil,
        ipv6LatencyMs: Double? = nil,
        errorDescription: String? = nil
    ) {
        self.timestamp = timestamp
        self.serviceName = serviceName
        self.hostname = hostname
        self.port = port
        self.ipv4Reachable = ipv4Reachable
        self.ipv6Reachable = ipv6Reachable
        self.ipv4LatencyMs = ipv4LatencyMs
        self.ipv6LatencyMs = ipv6LatencyMs
        self.errorDescription = errorDescription
    }
}
