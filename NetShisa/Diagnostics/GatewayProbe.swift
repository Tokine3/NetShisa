import Foundation
import SystemConfiguration

struct GatewayResult {
    let ipv4Gateway: String?
    let ipv6Gateway: String?
    let reachable: Bool
    let latencyMs: Double?
}

final class GatewayProbe: Sendable {

    func probe() async -> GatewayResult {
        let gateways = getDefaultGateways()

        guard let ipv4 = gateways.ipv4 else {
            return GatewayResult(
                ipv4Gateway: nil,
                ipv6Gateway: gateways.ipv6,
                reachable: false,
                latencyMs: nil
            )
        }

        // Ping gateway via TCP connection to port 80 or simple process-based ping
        let pingResult = await pingGateway(ipv4)

        return GatewayResult(
            ipv4Gateway: ipv4,
            ipv6Gateway: gateways.ipv6,
            reachable: pingResult.success,
            latencyMs: pingResult.latencyMs
        )
    }

    private func getDefaultGateways() -> (ipv4: String?, ipv6: String?) {
        guard let store = SCDynamicStoreCreate(nil, "NetShisa" as CFString, nil, nil) else {
            return (nil, nil)
        }

        var ipv4Router: String?
        var ipv6Router: String?

        if let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            ipv4Router = dict["Router"] as? String
        }

        if let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any] {
            ipv6Router = dict["Router"] as? String
        }

        return (ipv4Router, ipv6Router)
    }

    private func pingGateway(_ address: String) async -> (success: Bool, latencyMs: Double?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-c", "1", "-W", "3000", address]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                let start = DispatchTime.now()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

                    if process.terminationStatus == 0 {
                        // Parse actual RTT from ping output
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        let latency = self.parsePingLatency(output) ?? elapsed

                        continuation.resume(returning: (true, latency))
                    } else {
                        continuation.resume(returning: (false, nil))
                    }
                } catch {
                    continuation.resume(returning: (false, nil))
                }
            }
        }
    }

    private func parsePingLatency(_ output: String) -> Double? {
        // Parse "round-trip min/avg/max/stddev = 1.234/2.345/3.456/0.567 ms"
        guard let range = output.range(of: "round-trip") else { return nil }
        let line = String(output[range.lowerBound...])
        guard let eqRange = line.range(of: "= ") else { return nil }
        let values = String(line[eqRange.upperBound...])
        let parts = values.split(separator: "/")
        guard parts.count >= 2, let avg = Double(parts[1]) else { return nil }
        return avg
    }
}
