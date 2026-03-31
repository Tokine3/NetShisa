import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var contentOpacity: Double = 1.0
    @State private var spinRotation: Double = 0
    @State private var now = Date()
    @State private var uptimeTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Overall Status Banner
                overallStatusBanner

                // Row 1: 接続 + プロトコル
                HStack(alignment: .top, spacing: 12) {
                    connectionCard
                    protocolCard
                }
                .fixedSize(horizontal: false, vertical: true)

                // Row 2: DNS + サービス
                HStack(alignment: .top, spacing: 12) {
                    dnsCard
                    servicesCard
                }
                .fixedSize(horizontal: false, vertical: true)

                // Incident (conditional)
                if appState.currentIncident != nil {
                    incidentCard
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(contentOpacity)
        }
        .onAppear {
            uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                now = Date()
            }
        }
        .onDisappear {
            uptimeTimer?.invalidate()
            uptimeTimer = nil
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isProbing)
        .onChange(of: appState.isProbing) { _, isProbing in
            if isProbing {
                withAnimation(.easeOut(duration: 0.15)) { contentOpacity = 0.5 }
            } else {
                withAnimation(.easeIn(duration: 0.3)) { contentOpacity = 1.0 }
            }
        }
    }

    // MARK: - 接続カード

    private var connectionCard: some View {
        card("接続") {
            VStack(alignment: .leading, spacing: 10) {
                // Wi-Fi / Ethernet
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: appState.wifiInfo.isWiFiConnected ? "wifi" : (appState.wifiInfo.isEthernet ? "cable.connector" : "wifi.slash"))
                            .font(.system(size: 15))
                            .foregroundColor(.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.wifiInfo.summaryText)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let rssi = appState.wifiInfo.rssi {
                                Text("\(rssi) dBm")
                                    .foregroundColor(signalQualityColor(appState.wifiInfo.signalBars))
                            }
                            if let mode = appState.wifiInfo.phyMode {
                                badge(mode, color: .blue)
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    Spacer()
                }

                Divider().opacity(0.2)

                // 接続方式 + GW
                metricRow(icon: "bolt.horizontal.fill", label: "接続方式",
                          value: appState.connectionType != .unknown ? appState.connectionType.rawValue : "検出中...",
                          dimValue: appState.connectionType == .unknown)

                if let gw = appState.gatewayIPv4 {
                    metricRow(icon: "arrow.triangle.branch", label: "Gateway", value: gw)
                }

                if let localIP = appState.localIPv4 {
                    metricRow(icon: "laptopcomputer", label: "Local IP", value: localIP)
                }

                // 接続時間
                if let start = appState.connectionStartTime {
                    Divider().opacity(0.2)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("接続時間")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(uptimeString(from: start))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - プロトコルカード

    private var protocolCard: some View {
        card("プロトコル") {
            VStack(alignment: .leading, spacing: 10) {
                protocolRow(label: "IPv4", state: appState.ipv4Status, latency: appState.ipv4LatencyMs)
                protocolRow(label: "IPv6", state: appState.ipv6Status, latency: appState.ipv6LatencyMs)

                Divider().opacity(0.2)

                // Gateway
                HStack(spacing: 8) {
                    StatusIndicator(reachable: appState.gatewayReachable)
                    Text("Gateway")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    if let latency = appState.gatewayLatencyMs {
                        latencyBadge(latency)
                    }
                    Text(appState.gatewayReachable ? "到達可" : "不通")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(appState.gatewayReachable ? .green : .red)
                }

                // Global IP
                if let gv4 = appState.globalIPv4 {
                    Divider().opacity(0.2)
                    metricRow(icon: "globe", label: "Global IP", value: gv4)
                    if let gv6 = appState.globalIPv6 {
                        metricRow(icon: "globe", label: "Global v6", value: gv6)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - DNS カード

    private var dnsCard: some View {
        card("DNS") {
            let grouped = Dictionary(grouping: appState.dnsResults) { $0.server }
            let sortedKeys = grouped.keys.sorted()

            VStack(alignment: .leading, spacing: 8) {
                if sortedKeys.isEmpty {
                    HStack {
                        Spacer()
                        Text("データなし")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    let totalPassed = appState.dnsResults.filter { $0.success }.count
                    let total = appState.dnsResults.count

                    // サマリー行
                    HStack(spacing: 6) {
                        Image(systemName: totalPassed == total ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(totalPassed == total ? .green : .orange)
                        Text("\(totalPassed)/\(total) OK")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(totalPassed == total ? .green : .orange)
                        Spacer()
                    }

                    Divider().opacity(0.2)

                    // 各サーバー
                    ForEach(sortedKeys, id: \.self) { server in
                        let results = grouped[server]!
                        let passed = results.filter { $0.success }.count
                        HStack(spacing: 8) {
                            Circle()
                                .fill(passed == results.count ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(server)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(passed)/\(results.count)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - サービスカード

    private var servicesCard: some View {
        card("サービス到達性") {
            VStack(spacing: 2) {
                ForEach(appState.serviceResults) { result in
                    ServiceRow(result: result)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - インシデントカード

    private var incidentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let incident = appState.currentIncident {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.classification)
                            .font(.system(.body, weight: .bold))
                        Text("発生: \(incident.startTime.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { Task { await appState.runRemediation() } }) {
                        Label("修復する", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                    .disabled(appState.isRemediating)
                }
            }

            if let result = appState.lastRemediationResult {
                Divider().opacity(0.3)
                Text("修復結果")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(result.actions) { action in
                    HStack(spacing: 8) {
                        Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(action.success ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(action.actionName)
                                .font(.system(size: 11, weight: .medium))
                            Text(action.message)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Overall Status Banner

    private var overallStatusBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(statusSubtext)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { Task { await appState.runManualProbe() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(spinRotation))
                    Text("再診断")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.isProbing)
            .onChange(of: appState.isProbing) { _, isProbing in
                if isProbing {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        spinRotation = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        spinRotation = 0
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(statusColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(statusColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Shared Components

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func metricRow(icon: String, label: String, value: String, dimValue: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(dimValue ? .secondary : .primary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    private func protocolRow(label: String, state: ConnectivityState, latency: Double?) -> some View {
        HStack(spacing: 8) {
            StatusIndicator(state: state)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Spacer()
            if let latency {
                latencyBadge(latency)
            }
            Text(state.displayText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(state.color)
        }
    }

    private func latencyBadge(_ ms: Double) -> some View {
        Text("\(Int(ms))ms")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.secondary.opacity(0.1)))
            .foregroundColor(.secondary)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.1)))
            .foregroundColor(color)
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch appState.overallStatus {
        case .good: return .green
        case .degraded: return .orange
        case .down: return .red
        }
    }

    private var statusIcon: String {
        switch appState.overallStatus {
        case .good: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .down: return "xmark.circle.fill"
        }
    }

    private var statusText: String {
        switch appState.overallStatus {
        case .good: return "すべて正常"
        case .degraded: return "接続が不安定です"
        case .down: return "接続が切断されています"
        }
    }

    private var statusSubtext: String {
        let v4 = appState.ipv4Status == .reachable ? "IPv4 正常" : "IPv4 異常"
        let v6 = appState.ipv6Status == .reachable ? "IPv6 正常" : "IPv6 異常"
        return "\(v4) / \(v6)"
    }

    private func uptimeString(from start: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(start))
        if elapsed < 60 { return "\(elapsed)秒" }
        let minutes = elapsed / 60
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours < 24 { return "\(hours)時間\(mins)分" }
        let days = hours / 24
        let hrs = hours % 24
        return "\(days)日\(hrs)時間"
    }

    private func signalQualityColor(_ bars: Int) -> Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .orange
        default: return .red
        }
    }
}
