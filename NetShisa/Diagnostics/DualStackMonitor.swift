import Foundation
import Network

struct ProbeResult {
    let reachable: Bool
    let latencyMs: Double?
}

/// 接続方式の検出結果
enum ConnectionType: String {
    case ipoe = "IPv6 IPoE (DS-Lite/MAP-E)"
    case pppoe = "PPPoE"
    case unknown = "不明"
}

final class DualStackMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.netshisa.dualstack")
    private var pathMonitor: NWPathMonitor?
    private var debounceWorkItem: DispatchWorkItem?
    var activeInterface: String?
    var detectedConnectionType: ConnectionType = .unknown

    // Google Public DNS IPv4 アドレスに接続して IPv4 疎通確認
    func probeIPv4() async -> ProbeResult {
        await probeEndpoint(host: "8.8.8.8", port: 443)
    }

    // Google Public DNS IPv6 アドレスに接続して IPv6 疎通確認
    func probeIPv6() async -> ProbeResult {
        await probeEndpoint(host: "2001:4860:4860::8888", port: 443)
    }

    /// IPv6 IPoE 接続かどうかを推定する
    /// - IPv6 がネイティブで到達可能
    /// - IPv4 も到達可能（トンネル経由）
    /// - IPv4 の遅延が IPv6 より大きい傾向（トンネルオーバーヘッド）
    func detectConnectionType() async -> ConnectionType {
        let ipv6Result = await probeIPv6()
        let ipv4Result = await probeIPv4()

        guard ipv6Result.reachable else {
            detectedConnectionType = ipv4Result.reachable ? .pppoe : .unknown
            return detectedConnectionType
        }

        // IPv6 到達可能な場合、IPoE の可能性を検出
        // ルーターの WAN 側 IPv6 アドレスの有無やトンネルインターフェースで判定
        let hasIPv6WAN = await checkIPv6WAN()

        if hasIPv6WAN && ipv4Result.reachable {
            // IPv6 ネイティブ + IPv4 到達可能 = IPoE（DS-Lite/MAP-E）の可能性が高い
            detectedConnectionType = .ipoe
        } else if !hasIPv6WAN && ipv4Result.reachable {
            detectedConnectionType = .pppoe
        } else {
            detectedConnectionType = .unknown
        }

        return detectedConnectionType
    }

    /// IPv6 の WAN アドレスが存在するか確認（IPoE 判定用）
    private func checkIPv6WAN() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
                process.arguments = ["en0"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    // グローバル IPv6 アドレス（2xxx: or 3xxx:）が存在するか
                    let hasGlobalIPv6 = output.contains("inet6") &&
                        (output.range(of: "inet6 2[0-9a-f]", options: .regularExpression) != nil ||
                         output.range(of: "inet6 3[0-9a-f]", options: .regularExpression) != nil)
                    continuation.resume(returning: hasGlobalIPv6)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func probeEndpoint(host: String, port: UInt16) async -> ProbeResult {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )
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

            // 5秒でタイムアウト
            self.queue.asyncAfter(deadline: .now() + 5) {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: ProbeResult(reachable: false, latencyMs: nil))
            }
        }
    }

    func startPathMonitor(onChange: @escaping () -> Void) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if let interface = path.availableInterfaces.first {
                self.activeInterface = interface.name
            }
            // デバウンス: 2秒以内の連続変更をまとめる
            self.debounceWorkItem?.cancel()
            let work = DispatchWorkItem { onChange() }
            self.debounceWorkItem = work
            self.queue.asyncAfter(deadline: .now() + 2, execute: work)
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    func stopPathMonitor() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}
