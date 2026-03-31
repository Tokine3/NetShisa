import Foundation
import Network

struct ServiceCheckResult: Identifiable {
    var id: String { definition.hostname }
    let definition: ServiceDefinition
    var ipv4Reachable: Bool?
    var ipv6Reachable: Bool?
    var ipv4LatencyMs: Double?
    var ipv6LatencyMs: Double?
    var error: String?
}

final class ServiceProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.netshisa.serviceprobe")

    var services: [ServiceDefinition] = ServiceDefinition.defaults

    func probeAll() async -> [ServiceCheckResult] {
        await withTaskGroup(of: ServiceCheckResult.self) { group in
            for service in services {
                group.addTask {
                    await self.probeService(service)
                }
            }
            var results: [ServiceCheckResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.definition.name < $1.definition.name }
        }
    }

    private func probeService(_ service: ServiceDefinition) async -> ServiceCheckResult {
        var result = ServiceCheckResult(definition: service)

        // Resolve hostname first to get actual addresses
        let addresses = await resolveHostname(service.hostname)

        let ipv4Addresses = addresses.filter { !$0.contains(":") }
        let ipv6Addresses = addresses.filter { $0.contains(":") }

        // Update support flags based on actual DNS
        var def = service
        def.supportsIPv4 = !ipv4Addresses.isEmpty
        def.supportsIPv6 = !ipv6Addresses.isEmpty
        result = ServiceCheckResult(definition: def)

        // Probe IPv4 if available
        if let addr = ipv4Addresses.first {
            let probeResult = await probeAddress(addr, port: service.port)
            result.ipv4Reachable = probeResult.reachable
            result.ipv4LatencyMs = probeResult.latencyMs
        }

        // Probe IPv6 if available
        if let addr = ipv6Addresses.first {
            let probeResult = await probeAddress(addr, port: service.port)
            result.ipv6Reachable = probeResult.reachable
            result.ipv6LatencyMs = probeResult.latencyMs
        }

        return result
    }

    private func resolveHostname(_ hostname: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM

                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(hostname, "443", &hints, &result)

                guard status == 0, let info = result else {
                    continuation.resume(returning: [])
                    return
                }

                defer { freeaddrinfo(info) }

                var addresses: [String] = []
                var current = info
                while true {
                    let addr = current.pointee
                    if addr.ai_family == AF_INET {
                        var sa = sockaddr_in()
                        memcpy(&sa, addr.ai_addr, Int(addr.ai_addrlen))
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var addrCopy = sa.sin_addr
                        inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(INET_ADDRSTRLEN))
                        addresses.append(String(cString: buf))
                    } else if addr.ai_family == AF_INET6 {
                        var sa = sockaddr_in6()
                        memcpy(&sa, addr.ai_addr, Int(addr.ai_addrlen))
                        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        var addrCopy = sa.sin6_addr
                        inet_ntop(AF_INET6, &addrCopy, &buf, socklen_t(INET6_ADDRSTRLEN))
                        addresses.append(String(cString: buf))
                    }
                    guard let next = addr.ai_next else { break }
                    current = next
                }
                continuation.resume(returning: Array(Set(addresses)))
            }
        }
    }

    private func probeAddress(_ address: String, port: UInt16) async -> ProbeResult {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(address)
            let endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
            let parameters = NWParameters.tcp
            let connection = NWConnection(to: endpoint, using: parameters)
            let start = DispatchTime.now()
            var resumed = false

            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    connection.cancel()
                    continuation.resume(returning: ProbeResult(reachable: true, latencyMs: elapsed))
                case .failed, .cancelled:
                    resumed = true
                    connection.cancel()
                    continuation.resume(returning: ProbeResult(reachable: false, latencyMs: nil))
                default:
                    break
                }
            }
            connection.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 5) {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: ProbeResult(reachable: false, latencyMs: nil))
            }
        }
    }
}
