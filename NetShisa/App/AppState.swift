import Foundation
import SwiftData
import Combine

@MainActor
final class AppState: ObservableObject {
    let modelContainer: ModelContainer

    // Diagnostic modules
    let dualStackMonitor: DualStackMonitor
    let serviceProbe: ServiceProbe
    let dnsProbe: DNSProbe
    let gatewayProbe: GatewayProbe
    let incidentDetector: IncidentDetector
    let remediationEngine: RemediationEngine
    let probeScheduler: ProbeScheduler
    let networkDetailProbe: NetworkDetailProbe
    let wifiProbe: WiFiProbe

    // Published state
    @Published var ipv4Status: ConnectivityState = .unknown
    @Published var ipv6Status: ConnectivityState = .unknown
    @Published var ipv4LatencyMs: Double?
    @Published var ipv6LatencyMs: Double?
    @Published var localIPv4: String?
    @Published var gatewayIPv4: String?
    @Published var gatewayIPv6: String?
    @Published var gatewayReachable: Bool = false
    @Published var gatewayLatencyMs: Double?
    @Published var globalIPv4: String?
    @Published var globalIPv6: String?
    @Published var serviceResults: [ServiceCheckResult] = []
    @Published var dnsResults: [DNSCheckResult] = []
    @Published var overallStatus: OverallStatus = .good
    @Published var currentIncident: Incident?
    /// 手動の再診断ボタン押下時のみ true（定期プローブでは false のまま）
    @Published var isProbing: Bool = false
    @Published var isRemediating: Bool = false
    @Published var lastRemediationResult: RemediationResult?
    @Published var connectionType: ConnectionType = .unknown
    @Published var lastProbeTime: Date?
    @Published var networkDetail: NetworkDetail = NetworkDetail()
    @Published var wifiInfo: WiFiInfo = WiFiInfo()
    @Published var connectionStartTime: Date?
    @Published var rssiHistory: [(date: Date, rssi: Int)] = []

    #if DEBUG
    @Published var isDemoMode: Bool = false
    #endif

    private let maxRSSIHistory = 60

    /// グローバルIP取得タスクの参照（重複実行防止）
    private var globalIPTask: Task<Void, Never>?

    /// スナップショット保存用の共有コンテキスト（毎回生成を避ける）
    private lazy var persistenceContext: ModelContext = ModelContext(modelContainer)

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.dualStackMonitor = DualStackMonitor()
        self.serviceProbe = ServiceProbe()
        self.dnsProbe = DNSProbe()
        self.gatewayProbe = GatewayProbe()
        self.incidentDetector = IncidentDetector()
        self.remediationEngine = RemediationEngine()
        self.probeScheduler = ProbeScheduler()
        self.networkDetailProbe = NetworkDetailProbe()
        self.wifiProbe = WiFiProbe()
    }

    func startMonitoring() {
        // Wi-Fi 情報は軽量プローブで即時取得（スキャンなし → 高速）
        wifiInfo = wifiProbe.probe()
        // 初回起動時も DHCP リース時刻から接続時刻を取得
        if wifiInfo.isWiFiConnected || wifiInfo.isEthernet {
            connectionStartTime = wifiInfo.connectedSince ?? Date()
        }

        // 位置情報の許可が得られたら WiFi 情報を再取得（SSID 表示に必要）
        wifiProbe.onAuthorizationChanged = { [weak self] in
            Task { @MainActor in
                self?.wifiInfo = self?.wifiProbe.probe() ?? WiFiInfo()
            }
        }

        // 定期プローブを開始（初回は少し遅延して UI 描画を優先）
        probeScheduler.start { [weak self] in
            await self?.executeProbes()
        }

        // パス変更トリガー（Wi-Fi 切替等）
        dualStackMonitor.startPathMonitor { [weak self] in
            Task { @MainActor in
                await self?.executeProbes()
            }
        }

        // 接続方式検出はバックグラウンドで遅延実行（重い処理）
        Task {
            try? await Task.sleep(for: .seconds(3))
            connectionType = await dualStackMonitor.detectConnectionType()
        }
    }

    func stopMonitoring() {
        probeScheduler.stop()
        dualStackMonitor.stopPathMonitor()
        globalIPTask?.cancel()
        globalIPTask = nil
    }

    /// 手動の再診断（UIからボタン押下時に呼ぶ。アニメーション付き + 詳細診断）
    func runManualProbe() async {
        isProbing = true
        defer { isProbing = false }
        await executeProbes()
        // 手動時のみ詳細診断も実行
        networkDetail = await networkDetailProbe.probe()
    }

    /// 実際のプローブ処理（アニメーション状態には触れない）
    func executeProbes() async {
        // Wi-Fi 情報更新（重い処理をバックグラウンドで実行）
        let probe = wifiProbe
        let fullInfo = await Task.detached { probe.probeFull() }.value
        wifiInfo = fullInfo

        // 接続開始時刻: DHCP LeaseStartTime を優先
        if wifiInfo.isWiFiConnected || wifiInfo.isEthernet {
            connectionStartTime = wifiInfo.connectedSince ?? connectionStartTime ?? Date()
        } else {
            connectionStartTime = nil
        }

        // RSSI 履歴を記録
        if let rssi = wifiInfo.rssi {
            rssiHistory.append((date: Date(), rssi: rssi))
            if rssiHistory.count > maxRSSIHistory {
                rssiHistory.removeFirst(rssiHistory.count - maxRSSIHistory)
            }
        }

        // ローカル IP 取得
        localIPv4 = getLocalIPv4()

        // Run IPv4/IPv6 probes
        let ipv4Result = await dualStackMonitor.probeIPv4()
        let ipv6Result = await dualStackMonitor.probeIPv6()

        ipv4Status = ipv4Result.reachable ? .reachable : .unreachable
        ipv6Status = ipv6Result.reachable ? .reachable : .unreachable
        ipv4LatencyMs = ipv4Result.latencyMs
        ipv6LatencyMs = ipv6Result.latencyMs

        // グローバル IP をバックグラウンドで取得（前回タスクが実行中ならスキップ）
        if globalIPTask == nil {
            globalIPTask = Task.detached { [weak self] in
                let gv4 = await Self.fetchGlobalIP(url: "https://api.ipify.org")
                let gv6 = await Self.fetchGlobalIP(url: "https://api64.ipify.org")
                await MainActor.run {
                    self?.globalIPv4 = gv4
                    self?.globalIPv6 = (gv6 != nil && gv6 != gv4) ? gv6 : nil
                    self?.globalIPTask = nil
                }
            }
        }

        // Run gateway probe
        let gwResult = await gatewayProbe.probe()
        gatewayIPv4 = gwResult.ipv4Gateway
        gatewayIPv6 = gwResult.ipv6Gateway
        gatewayReachable = gwResult.reachable
        gatewayLatencyMs = gwResult.latencyMs

        // Run service probes
        serviceResults = await serviceProbe.probeAll()

        // Run DNS probes
        dnsResults = await dnsProbe.probeAll()

        // Evaluate overall status
        let evaluation = incidentDetector.evaluate(
            ipv4Status: ipv4Status,
            ipv6Status: ipv6Status,
            gatewayReachable: gatewayReachable,
            serviceResults: serviceResults,
            dnsResults: dnsResults
        )

        overallStatus = evaluation.overallStatus
        lastProbeTime = Date()

        // Handle incident detection
        if let classification = evaluation.incidentClassification {
            if currentIncident == nil {
                let incident = Incident(
                    classification: classification,
                    startTime: Date()
                )
                currentIncident = incident
                probeScheduler.enterIncidentMode()
                persistenceContext.insert(incident)
                try? persistenceContext.save()

                NotificationManager.shared.sendIncidentNotification(classification: classification)
            }
        } else if let incident = currentIncident {
            incident.endTime = Date()
            currentIncident = nil
            probeScheduler.exitIncidentMode()

            try? persistenceContext.save()
        }

        // Save snapshot
        saveSnapshot()
    }

    func runRemediation() async {
        isRemediating = true
        defer { isRemediating = false }

        let result = await remediationEngine.runRemediation(
            ipv4Status: ipv4Status,
            ipv6Status: ipv6Status,
            gatewayReachable: gatewayReachable
        )
        lastRemediationResult = result

        // Re-probe after remediation
        try? await Task.sleep(for: .seconds(2))
        await executeProbes()
    }

    /// 最後にクリーンアップを実行した日時
    private var lastCleanupDate: Date?

    private func saveSnapshot() {
        let context = persistenceContext

        let snapshot = ConnectivitySnapshot(
            timestamp: Date(),
            ipv4Status: ipv4Status,
            ipv6Status: ipv6Status,
            gatewayIPv4Reachable: gatewayReachable,
            gatewayIPv6Reachable: gatewayReachable,
            gatewayLatencyMs: gatewayLatencyMs,
            activeInterface: dualStackMonitor.activeInterface ?? "unknown"
        )
        context.insert(snapshot)

        // 1日1回だけ古いデータをクリーンアップ
        let now = Date()
        if lastCleanupDate == nil || now.timeIntervalSince(lastCleanupDate!) > 86400 {
            lastCleanupDate = now
            pruneOldData()
        }

        try? context.save()
    }

    /// 古いスナップショット（7日超）とインシデント（90日超）を削除
    private func pruneOldData() {
        let context = persistenceContext
        let snapshotCutoff = Date().addingTimeInterval(-7 * 86400)
        let incidentCutoff = Date().addingTimeInterval(-90 * 86400)

        let snapshotDescriptor = FetchDescriptor<ConnectivitySnapshot>(
            predicate: #Predicate { $0.timestamp < snapshotCutoff }
        )
        if let old = try? context.fetch(snapshotDescriptor) {
            for item in old { context.delete(item) }
        }

        let incidentDescriptor = FetchDescriptor<Incident>(
            predicate: #Predicate { $0.startTime < incidentCutoff }
        )
        if let old = try? context.fetch(incidentDescriptor) {
            for item in old { context.delete(item) }
        }
    }

    /// ローカル IPv4 アドレスを取得
    private func getLocalIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            let family = iface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: iface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var addr = iface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }

    /// グローバル IP を外部 API から取得
    private static func fetchGlobalIP(url: String) async -> String? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (ip?.isEmpty == false) ? ip : nil
        } catch {
            return nil
        }
    }
}

// MARK: - デモモード表示用プロパティ

extension AppState {
    #if DEBUG
    var displayLocalIPv4: String? { isDemoMode ? DemoData.localIPv4 : localIPv4 }
    var displayGatewayIPv4: String? { isDemoMode ? DemoData.gatewayIPv4 : gatewayIPv4 }
    var displayGatewayIPv6: String? { isDemoMode ? (gatewayIPv6 != nil ? DemoData.gatewayIPv6 : nil) : gatewayIPv6 }
    var displayGlobalIPv4: String? { isDemoMode ? DemoData.globalIPv4 : globalIPv4 }
    var displayGlobalIPv6: String? { isDemoMode ? (globalIPv6 != nil ? DemoData.globalIPv6 : nil) : globalIPv6 }
    var displayWifiInfo: WiFiInfo { isDemoMode ? DemoData.mask(wifiInfo) : wifiInfo }
    var displayNetworkDetail: NetworkDetail { isDemoMode ? DemoData.mask(networkDetail) : networkDetail }
    #else
    var displayLocalIPv4: String? { localIPv4 }
    var displayGatewayIPv4: String? { gatewayIPv4 }
    var displayGatewayIPv6: String? { gatewayIPv6 }
    var displayGlobalIPv4: String? { globalIPv4 }
    var displayGlobalIPv6: String? { globalIPv6 }
    var displayWifiInfo: WiFiInfo { wifiInfo }
    var displayNetworkDetail: NetworkDetail { networkDetail }
    #endif
}

enum OverallStatus: String {
    case good
    case degraded
    case down

    var color: String {
        switch self {
        case .good: return "green"
        case .degraded: return "yellow"
        case .down: return "red"
        }
    }
}
