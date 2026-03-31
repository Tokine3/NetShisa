import Foundation

struct DNSCheckResult: Identifiable {
    var id: String { "\(server)-\(queryType)" }
    let server: String
    let queryType: String  // "A" or "AAAA"
    let domain: String
    let success: Bool
    let latencyMs: Double?
    let addresses: [String]
    let error: String?
}

final class DNSProbe: Sendable {
    struct DNSServer {
        let name: String
        let address: String?  // nil = system default
    }

    static let servers: [DNSServer] = [
        DNSServer(name: "System", address: nil),
        DNSServer(name: "Google (8.8.8.8)", address: "8.8.8.8"),
        DNSServer(name: "Cloudflare (1.1.1.1)", address: "1.1.1.1"),
    ]

    static let testDomains = ["google.com", "discord.com"]

    func probeAll() async -> [DNSCheckResult] {
        await withTaskGroup(of: [DNSCheckResult].self) { group in
            for server in Self.servers {
                group.addTask {
                    await self.probeServer(server)
                }
            }
            var results: [DNSCheckResult] = []
            for await batch in group {
                results.append(contentsOf: batch)
            }
            return results
        }
    }

    private func probeServer(_ server: DNSServer) async -> [DNSCheckResult] {
        var results: [DNSCheckResult] = []

        for domain in Self.testDomains {
            // Test A records (IPv4)
            let ipv4Result = await resolveDNS(
                hostname: domain,
                family: AF_INET,
                server: server
            )
            results.append(ipv4Result)

            // Test AAAA records (IPv6)
            let ipv6Result = await resolveDNS(
                hostname: domain,
                family: AF_INET6,
                server: server
            )
            results.append(ipv6Result)
        }

        return results
    }

    private func resolveDNS(hostname: String, family: Int32, server: DNSServer) async -> DNSCheckResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let queryType = family == AF_INET ? "A" : "AAAA"
                var hints = addrinfo()
                hints.ai_family = family
                hints.ai_socktype = SOCK_STREAM

                var result: UnsafeMutablePointer<addrinfo>?
                let start = DispatchTime.now()
                let status = getaddrinfo(hostname, "443", &hints, &result)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

                if status != 0 {
                    let errorMsg = String(cString: gai_strerror(status))
                    continuation.resume(returning: DNSCheckResult(
                        server: server.name,
                        queryType: queryType,
                        domain: hostname,
                        success: false,
                        latencyMs: elapsed,
                        addresses: [],
                        error: errorMsg
                    ))
                    return
                }

                defer { freeaddrinfo(result) }

                var addresses: [String] = []
                var current = result
                while let info = current {
                    let addr = info.pointee
                    if family == AF_INET {
                        var sa = sockaddr_in()
                        memcpy(&sa, addr.ai_addr, Int(addr.ai_addrlen))
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var addrCopy = sa.sin_addr
                        inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(INET_ADDRSTRLEN))
                        addresses.append(String(cString: buf))
                    } else {
                        var sa = sockaddr_in6()
                        memcpy(&sa, addr.ai_addr, Int(addr.ai_addrlen))
                        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        var addrCopy = sa.sin6_addr
                        inet_ntop(AF_INET6, &addrCopy, &buf, socklen_t(INET6_ADDRSTRLEN))
                        addresses.append(String(cString: buf))
                    }
                    current = addr.ai_next
                }

                continuation.resume(returning: DNSCheckResult(
                    server: server.name,
                    queryType: queryType,
                    domain: hostname,
                    success: !addresses.isEmpty,
                    latencyMs: elapsed,
                    addresses: Array(Set(addresses)),
                    error: nil
                ))
            }
        }
    }
}
