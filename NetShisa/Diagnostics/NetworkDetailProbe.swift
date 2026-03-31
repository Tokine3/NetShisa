import Foundation

/// 詳細ネットワーク診断情報
struct NetworkDetail {
    // RA (Router Advertisement) 情報
    var raReceived: Bool = false
    var ipv6Routers: [IPv6RouterInfo] = []

    // インターフェース情報
    var interfaces: [InterfaceInfo] = []

    // NDP ネイバーテーブル
    var ndpNeighbors: [NDPNeighborEntry] = []

    // ルーティングテーブル (IPv4/IPv6)
    var ipv4DefaultRoute: String?
    var ipv6DefaultRoute: String?
    var routeEntries: [RouteEntry] = []

    // DNS 設定
    var dnsServers: [String] = []

    // MTU
    var mtu: Int?

    // 接続中の SSID
    var ssid: String?

    // TCP 接続状態サマリー
    var tcpEstablished: Int = 0
    var tcpTimeWait: Int = 0
    var tcpCloseWait: Int = 0
}

struct IPv6RouterInfo {
    let address: String
    let interface: String
    let flags: String
    let preference: String
    let expire: String
}

struct InterfaceInfo {
    let name: String
    let ipv4Addresses: [String]
    let ipv6Addresses: [IPv6AddressInfo]
    let macAddress: String?
    let mtu: Int?
    let status: String  // "active", "inactive"
}

struct IPv6AddressInfo {
    let address: String
    let prefixLength: Int
    let scope: String  // "global", "link-local", "unique-local"
}

struct NDPNeighborEntry {
    let address: String
    let macAddress: String
    let interface: String
    let state: String  // "reachable", "stale", "delay", "probe", "incomplete"
}

struct RouteEntry {
    let destination: String
    let gateway: String
    let interface: String
    let flags: String
}

final class NetworkDetailProbe: Sendable {

    func probe() async -> NetworkDetail {
        var detail = NetworkDetail()

        // 並行で各診断を実行
        await withTaskGroup(of: Void.self) { group in
            group.addTask { detail.ipv6Routers = await self.checkRA() }
            group.addTask { detail.interfaces = await self.getInterfaces() }
            group.addTask { detail.ndpNeighbors = await self.getNDPNeighbors() }
            group.addTask {
                let routes = await self.getRoutes()
                detail.ipv4DefaultRoute = routes.ipv4Default
                detail.ipv6DefaultRoute = routes.ipv6Default
                detail.routeEntries = routes.entries
            }
            group.addTask { detail.dnsServers = await self.getDNSServers() }
            group.addTask { detail.ssid = await self.getSSID() }
            group.addTask {
                let tcp = await self.getTCPStats()
                detail.tcpEstablished = tcp.established
                detail.tcpTimeWait = tcp.timeWait
                detail.tcpCloseWait = tcp.closeWait
            }
        }

        // RA 受信判定: en0 にグローバル IPv6 ルーターがあるか
        detail.raReceived = detail.ipv6Routers.contains { entry in
            let iface = entry.interface
            return iface.contains("en0") || iface.contains("en1")
        }

        // MTU
        detail.mtu = detail.interfaces.first { $0.name == "en0" }?.mtu

        return detail
    }

    // MARK: - RA (Router Advertisement) チェック

    /// ndp -rn で IPv6 ルーター一覧を取得。RA が届いていれば en0 のエントリが存在する
    private func checkRA() async -> [IPv6RouterInfo] {
        let output = await runCommand("/usr/sbin/ndp", arguments: ["-rn"])
        var routers: [IPv6RouterInfo] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Routing") else { continue }

            // 形式: fe80::1%en0 if=en0, flags=, pref=medium, expire=1h58m
            if let ifRange = trimmed.range(of: "if=") {
                let address = String(trimmed[trimmed.startIndex..<ifRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rest = String(trimmed[ifRange.upperBound...])
                let parts = rest.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }

                let iface = parts.first?.replacingOccurrences(of: "if=", with: "") ?? ""
                let flags = parts.first { $0.hasPrefix("flags=") }?.replacingOccurrences(of: "flags=", with: "") ?? ""
                let pref = parts.first { $0.hasPrefix("pref=") }?.replacingOccurrences(of: "pref=", with: "") ?? ""
                let expire = parts.first { $0.hasPrefix("expire=") }?.replacingOccurrences(of: "expire=", with: "") ?? ""

                routers.append(IPv6RouterInfo(
                    address: address,
                    interface: iface,
                    flags: flags,
                    preference: pref,
                    expire: expire
                ))
            }
        }
        return routers
    }

    // MARK: - インターフェース情報

    private func getInterfaces() async -> [InterfaceInfo] {
        let output = await runCommand("/sbin/ifconfig", arguments: ["-a"])
        var interfaces: [InterfaceInfo] = []
        var currentName = ""
        var ipv4s: [String] = []
        var ipv6s: [IPv6AddressInfo] = []
        var mac: String?
        var mtu: Int?
        var status = "inactive"

        func flushInterface() {
            if !currentName.isEmpty && (currentName.hasPrefix("en") || currentName.hasPrefix("bridge")) {
                interfaces.append(InterfaceInfo(
                    name: currentName,
                    ipv4Addresses: ipv4s,
                    ipv6Addresses: ipv6s,
                    macAddress: mac,
                    mtu: mtu,
                    status: status
                ))
            }
        }

        for line in output.components(separatedBy: "\n") {
            if !line.hasPrefix("\t") && !line.hasPrefix(" ") && line.contains(":") {
                flushInterface()
                currentName = String(line.split(separator: ":").first ?? "")
                ipv4s = []; ipv6s = []; mac = nil; mtu = nil; status = "inactive"

                if line.contains("mtu") {
                    if let mtuRange = line.range(of: "mtu ") {
                        let mtuStr = String(line[mtuRange.upperBound...]).split(separator: " ").first ?? ""
                        mtu = Int(mtuStr)
                    }
                }
                if line.contains("status: active") || line.contains("RUNNING") {
                    status = "active"
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    ipv4s.append(String(parts[1]))
                }
            }

            if trimmed.hasPrefix("inet6 ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let addr = String(parts[1]).components(separatedBy: "%").first ?? String(parts[1])
                    let prefixLen = parts.first { $0 == "prefixlen" }.flatMap {
                        let idx = parts.firstIndex(of: $0)!
                        return idx + 1 < parts.count ? Int(parts[idx + 1]) : nil
                    } ?? 0

                    let scope: String
                    if addr.hasPrefix("fe80") { scope = "link-local" }
                    else if addr.hasPrefix("fd") || addr.hasPrefix("fc") { scope = "unique-local" }
                    else if addr.hasPrefix("2") || addr.hasPrefix("3") { scope = "global" }
                    else { scope = "other" }

                    ipv6s.append(IPv6AddressInfo(address: addr, prefixLength: prefixLen, scope: scope))
                }
            }

            if trimmed.hasPrefix("ether ") {
                mac = String(trimmed.split(separator: " ")[1])
            }

            if trimmed.contains("status: active") {
                status = "active"
            }
        }
        flushInterface()

        return interfaces
    }

    // MARK: - NDP ネイバーテーブル

    private func getNDPNeighbors() async -> [NDPNeighborEntry] {
        let output = await runCommand("/usr/sbin/ndp", arguments: ["-an"])
        var entries: [NDPNeighborEntry] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Neighbor") else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4 else { continue }

            let addr = parts[0].components(separatedBy: "%").first ?? parts[0]
            let macAddr = parts[1]
            let iface = parts[2]
            // state は残りの部分から抽出
            let state = parts.count >= 5 ? parts[4] : parts.count >= 4 ? parts[3] : "unknown"

            entries.append(NDPNeighborEntry(
                address: addr,
                macAddress: macAddr,
                interface: iface,
                state: state
            ))
        }
        return entries
    }

    // MARK: - ルーティングテーブル

    private func getRoutes() async -> (ipv4Default: String?, ipv6Default: String?, entries: [RouteEntry]) {
        let ipv4Output = await runCommand("/sbin/route", arguments: ["-n", "get", "default"])
        let ipv6Output = await runCommand("/sbin/route", arguments: ["-n", "get", "-inet6", "default"])

        var ipv4Default: String?
        var ipv6Default: String?

        for line in ipv4Output.components(separatedBy: "\n") {
            if line.contains("gateway:") {
                ipv4Default = line.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        for line in ipv6Output.components(separatedBy: "\n") {
            if line.contains("gateway:") {
                ipv6Default = line.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // netstat -rn で主要ルートを取得
        let routeOutput = await runCommand("/usr/sbin/netstat", arguments: ["-rn"])
        var entries: [RouteEntry] = []

        for line in routeOutput.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4 else { continue }
            let dest = parts[0]
            // default や主要ルートのみ
            if dest == "default" || dest.hasPrefix("10.") || dest.hasPrefix("192.168.") || dest.hasPrefix("172.") || dest.contains(":") {
                entries.append(RouteEntry(
                    destination: dest,
                    gateway: parts[1],
                    interface: parts.count >= 6 ? parts[5] : (parts.count >= 4 ? parts[3] : ""),
                    flags: parts.count >= 3 ? parts[2] : ""
                ))
            }
        }

        return (ipv4Default, ipv6Default, entries)
    }

    // MARK: - DNS サーバー

    private func getDNSServers() async -> [String] {
        let output = await runCommand("/usr/sbin/scutil", arguments: ["--dns"])
        var servers: [String] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("nameserver[") {
                if let colonRange = trimmed.range(of: ": ") {
                    let server = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !servers.contains(server) {
                        servers.append(server)
                    }
                }
            }
        }
        return servers
    }

    // MARK: - SSID

    private func getSSID() async -> String? {
        let output = await runCommand("/usr/sbin/networksetup", arguments: ["-getairportnetwork", "en0"])
        // "Current Wi-Fi Network: SSID_NAME"
        if let range = output.range(of: ": ") {
            return String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - TCP 接続状態

    private func getTCPStats() async -> (established: Int, timeWait: Int, closeWait: Int) {
        let output = await runCommand("/usr/sbin/netstat", arguments: ["-n", "-p", "tcp"])
        var established = 0, timeWait = 0, closeWait = 0

        for line in output.components(separatedBy: "\n") {
            if line.contains("ESTABLISHED") { established += 1 }
            else if line.contains("TIME_WAIT") { timeWait += 1 }
            else if line.contains("CLOSE_WAIT") { closeWait += 1 }
        }
        return (established, timeWait, closeWait)
    }

    // MARK: - ヘルパー

    private func runCommand(_ path: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
