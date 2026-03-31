import Foundation

struct RemediationResult {
    let actions: [RemediationActionResult]
    let overallSuccess: Bool
}

struct RemediationActionResult: Identifiable {
    let id = UUID()
    let actionName: String
    let success: Bool
    let message: String
}

final class RemediationEngine: Sendable {

    func runRemediation(
        ipv4Status: ConnectivityState,
        ipv6Status: ConnectivityState,
        gatewayReachable: Bool
    ) async -> RemediationResult {
        var actions: [RemediationActionResult] = []

        // Step 1: Flush DNS cache
        let dnsFlush = await flushDNSCache()
        actions.append(dnsFlush)

        // Step 2: Renew DHCP lease (most effective for IPv4 drops)
        if ipv4Status == .unreachable {
            let dhcpRenew = await renewDHCPLease()
            actions.append(dhcpRenew)
        }

        // Step 3: IPv6 再取得 (IPv6 unreachable の場合)
        if ipv6Status == .unreachable {
            let ipv6Reset = await resetIPv6()
            actions.append(ipv6Reset)
        }

        // Step 4: If gateway unreachable, try Wi-Fi reset
        if !gatewayReachable {
            let wifiReset = await resetWiFi()
            actions.append(wifiReset)
        }

        let success = actions.contains(where: { $0.success })
        return RemediationResult(actions: actions, overallSuccess: success)
    }

    private func flushDNSCache() async -> RemediationActionResult {
        let result1 = await runPrivilegedCommand(
            path: "/usr/bin/dscacheutil",
            arguments: ["-flushcache"]
        )
        let result2 = await runPrivilegedCommand(
            path: "/usr/bin/killall",
            arguments: ["-HUP", "mDNSResponder"]
        )

        let success = result1 && result2
        return RemediationActionResult(
            actionName: "DNS Cache Flush",
            success: success,
            message: success ? "DNSキャッシュをクリアしました" : "DNSキャッシュのクリアに失敗しました"
        )
    }

    private func renewDHCPLease() async -> RemediationActionResult {
        // Get the primary network interface
        let interface = await getPrimaryInterface() ?? "en0"

        let success = await runPrivilegedCommand(
            path: "/usr/sbin/ipconfig",
            arguments: ["set", interface, "DHCP"]
        )

        return RemediationActionResult(
            actionName: "DHCP Lease Renewal",
            success: success,
            message: success ? "DHCPリースを更新しました (\(interface))" : "DHCPリース更新に失敗しました"
        )
    }

    /// 外部から直接呼べる IPv6 再取得
    func resetIPv6Public() async -> RemediationActionResult {
        await resetIPv6()
    }

    private func resetIPv6() async -> RemediationActionResult {
        let interface = await getWiFiInterface() ?? "en0"

        // IPv6 を一度無効化
        let off = await runCommand(
            path: "/usr/sbin/networksetup",
            arguments: ["-setv6off", interface]
        )

        try? await Task.sleep(for: .seconds(2))

        // IPv6 を自動に戻す (RA を再受信)
        let on = await runCommand(
            path: "/usr/sbin/networksetup",
            arguments: ["-setv6automatic", interface]
        )

        // RA 受信待ち
        try? await Task.sleep(for: .seconds(3))

        let success = off && on
        return RemediationActionResult(
            actionName: "IPv6 再取得",
            success: success,
            message: success
                ? "IPv6 を再取得しました (setv6off → setv6automatic on \(interface))。RA 再受信を待機中..."
                : "IPv6 再取得に失敗しました"
        )
    }

    private func resetWiFi() async -> RemediationActionResult {
        // Get Wi-Fi interface name
        let interface = await getWiFiInterface() ?? "en0"

        // Turn off
        let off = await runCommand(
            path: "/usr/sbin/networksetup",
            arguments: ["-setairportpower", interface, "off"]
        )

        // Wait a moment
        try? await Task.sleep(for: .seconds(2))

        // Turn on
        let on = await runCommand(
            path: "/usr/sbin/networksetup",
            arguments: ["-setairportpower", interface, "on"]
        )

        let success = off && on
        return RemediationActionResult(
            actionName: "Wi-Fi Reset",
            success: success,
            message: success ? "Wi-Fiをリセットしました" : "Wi-Fiリセットに失敗しました"
        )
    }

    private func getPrimaryInterface() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/route")
                process.arguments = ["-n", "get", "default"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    for line in output.components(separatedBy: "\n") {
                        if line.contains("interface:") {
                            let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                            if parts.count >= 2 {
                                continuation.resume(returning: parts[1])
                                return
                            }
                        }
                    }
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func getWiFiInterface() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                process.arguments = ["-listallhardwareports"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let lines = output.components(separatedBy: "\n")
                    for (i, line) in lines.enumerated() {
                        if line.contains("Wi-Fi") || line.contains("AirPort") {
                            if i + 1 < lines.count, lines[i + 1].contains("Device:") {
                                let device = lines[i + 1]
                                    .replacingOccurrences(of: "Device:", with: "")
                                    .trimmingCharacters(in: .whitespaces)
                                continuation.resume(returning: device)
                                return
                            }
                        }
                    }
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func runPrivilegedCommand(path: String, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // Use osascript to run with admin privileges
                let command = ([path] + arguments).map { "quoted form of \"\($0)\"" }.joined(separator: " & \" \" & ")
                let script = "do shell script \(command) with administrator privileges"

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func runCommand(path: String, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
