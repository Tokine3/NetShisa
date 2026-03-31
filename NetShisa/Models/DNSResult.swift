import Foundation
import SwiftData

@Model
final class DNSResult {
    var timestamp: Date
    var queryDomain: String
    var dnsServer: String
    var queryType: String
    var success: Bool
    var latencyMs: Double?
    var resolvedAddresses: [String]
    var errorDescription: String?

    init(
        timestamp: Date,
        queryDomain: String,
        dnsServer: String,
        queryType: String,
        success: Bool,
        latencyMs: Double? = nil,
        resolvedAddresses: [String] = [],
        errorDescription: String? = nil
    ) {
        self.timestamp = timestamp
        self.queryDomain = queryDomain
        self.dnsServer = dnsServer
        self.queryType = queryType
        self.success = success
        self.latencyMs = latencyMs
        self.resolvedAddresses = resolvedAddresses
        self.errorDescription = errorDescription
    }
}
