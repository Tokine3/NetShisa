import Foundation
import SwiftData

@Model
final class ConnectivitySnapshot {
    var timestamp: Date
    var ipv4Status: ConnectivityState
    var ipv6Status: ConnectivityState
    var gatewayIPv4Reachable: Bool
    var gatewayIPv6Reachable: Bool
    var gatewayLatencyMs: Double?
    var activeInterface: String

    init(
        timestamp: Date,
        ipv4Status: ConnectivityState,
        ipv6Status: ConnectivityState,
        gatewayIPv4Reachable: Bool,
        gatewayIPv6Reachable: Bool,
        gatewayLatencyMs: Double?,
        activeInterface: String
    ) {
        self.timestamp = timestamp
        self.ipv4Status = ipv4Status
        self.ipv6Status = ipv6Status
        self.gatewayIPv4Reachable = gatewayIPv4Reachable
        self.gatewayIPv6Reachable = gatewayIPv6Reachable
        self.gatewayLatencyMs = gatewayLatencyMs
        self.activeInterface = activeInterface
    }
}
