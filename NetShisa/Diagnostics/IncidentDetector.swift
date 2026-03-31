import Foundation

struct IncidentEvaluation {
    let overallStatus: OverallStatus
    let incidentClassification: String?
}

final class IncidentDetector: Sendable {

    func evaluate(
        ipv4Status: ConnectivityState,
        ipv6Status: ConnectivityState,
        gatewayReachable: Bool,
        serviceResults: [ServiceCheckResult],
        dnsResults: [DNSCheckResult]
    ) -> IncidentEvaluation {

        // Check for full outage
        if ipv4Status == .unreachable && ipv6Status == .unreachable {
            if !gatewayReachable {
                return IncidentEvaluation(
                    overallStatus: .down,
                    incidentClassification: "Gateway Unreachable"
                )
            }
            return IncidentEvaluation(
                overallStatus: .down,
                incidentClassification: "Full Outage"
            )
        }

        // Check for IPv4 down / IPv6 up (user's likely scenario)
        if ipv4Status == .unreachable && ipv6Status == .reachable {
            return IncidentEvaluation(
                overallStatus: .degraded,
                incidentClassification: "IPv4 Down / IPv6 Up"
            )
        }

        // Check for IPv6 down / IPv4 up
        if ipv4Status == .reachable && ipv6Status == .unreachable {
            return IncidentEvaluation(
                overallStatus: .degraded,
                incidentClassification: "IPv6 Down / IPv4 Up"
            )
        }

        // Check DNS failures
        let dnsFailures = dnsResults.filter { !$0.success }
        let dnsTotal = dnsResults.count
        if dnsTotal > 0 && dnsFailures.count > dnsTotal / 2 {
            return IncidentEvaluation(
                overallStatus: .degraded,
                incidentClassification: "DNS Failure"
            )
        }

        // Check partial service outage
        let failedServices = serviceResults.filter { result in
            let ipv4Failed = result.definition.supportsIPv4 && result.ipv4Reachable == false
            let ipv6Failed = result.definition.supportsIPv6 && result.ipv6Reachable == false
            return ipv4Failed || ipv6Failed
        }

        if !failedServices.isEmpty {
            let names = failedServices.map { $0.definition.name }.joined(separator: ", ")
            return IncidentEvaluation(
                overallStatus: .degraded,
                incidentClassification: "Partial Outage: \(names)"
            )
        }

        // All good
        return IncidentEvaluation(
            overallStatus: .good,
            incidentClassification: nil
        )
    }
}
