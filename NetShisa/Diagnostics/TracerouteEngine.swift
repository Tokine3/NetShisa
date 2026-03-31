import Foundation

final class TracerouteEngine: Sendable {

    func run(target: String, ipv6: Bool = false) async -> [TracerouteHop] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                if ipv6 {
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute6")
                    process.arguments = ["-m", "30", "-w", "3", target]
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
                    process.arguments = ["-m", "30", "-w", "3", target]
                }

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let hops = self.parseTraceroute(output)
                    continuation.resume(returning: hops)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// 外部から traceroute 出力をパースする用
    func parseOutput(_ output: String) -> [TracerouteHop] {
        parseTraceroute(output)
    }

    private func parseTraceroute(_ output: String) -> [TracerouteHop] {
        var hops: [TracerouteHop] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("traceroute") else { continue }

            // Parse hop number
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let hopNum = Int(parts.first ?? "") else { continue }

            if parts.contains("*") && parts.filter({ $0 == "*" }).count == 3 {
                hops.append(TracerouteHop(
                    hopNumber: hopNum,
                    address: nil,
                    hostname: nil,
                    latencyMs: [],
                    timedOut: true
                ))
                continue
            }

            // Parse address and latencies
            var hostname: String?
            var address: String?
            var latencies: [Double] = []

            var i = 1
            while i < parts.count {
                let part = parts[i]
                if part == "*" {
                    i += 1
                    continue
                }
                if part.hasPrefix("(") && part.hasSuffix(")") {
                    address = String(part.dropFirst().dropLast())
                    i += 1
                } else if part.hasSuffix("ms") || (i + 1 < parts.count && parts[i + 1] == "ms") {
                    if part.hasSuffix("ms") {
                        if let val = Double(String(part.dropLast(2))) {
                            latencies.append(val)
                        }
                        i += 1
                    } else if let val = Double(part) {
                        latencies.append(val)
                        i += 2  // skip "ms"
                    } else {
                        i += 1
                    }
                } else if address == nil && !part.isEmpty {
                    if hostname == nil {
                        hostname = part
                    }
                    i += 1
                } else {
                    i += 1
                }
            }

            hops.append(TracerouteHop(
                hopNumber: hopNum,
                address: address,
                hostname: hostname,
                latencyMs: latencies,
                timedOut: false
            ))
        }

        return hops
    }
}
