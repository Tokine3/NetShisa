import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    @State private var probeOpacity: Double = 1.0
    @State private var spinRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.5)

            // プローブ中インジケーター
            if appState.isProbing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("診断中...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.06))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                VStack(spacing: 12) {
                    // Protocol Status Card
                    cardSection {
                        VStack(spacing: 8) {
                            protocolRow(label: "IPv4", state: appState.ipv4Status, latency: appState.ipv4LatencyMs)
                            protocolRow(label: "IPv6", state: appState.ipv6Status, latency: appState.ipv6LatencyMs)

                            Divider().opacity(0.3)

                            // Local IP
                            if let localIP = appState.localIPv4 {
                                HStack(spacing: 8) {
                                    Image(systemName: "laptopcomputer")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .frame(width: 14)
                                    Text("Local IP")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    Text(localIP)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }

                            // Gateway
                            HStack(spacing: 8) {
                                StatusIndicator(reachable: appState.gatewayReachable)
                                Text("Gateway")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                if let gw = appState.gatewayIPv4 {
                                    Text(gw)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let latency = appState.gatewayLatencyMs {
                                    Text("\(String(format: "%.1f", latency))ms")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // 接続方式
                            if appState.connectionType != .unknown {
                                Divider().opacity(0.3)
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.horizontal.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                    Text("接続方式:")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(appState.connectionType.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.blue)
                                    Spacer()
                                }
                            }
                        }
                    }

                    // Services Card
                    cardSection {
                        VStack(alignment: .leading, spacing: 2) {
                            sectionLabel("サービス")
                                .padding(.bottom, 4)

                            ForEach(appState.serviceResults) { result in
                                ServiceRow(result: result)
                            }
                        }
                    }

                    // DNS Summary Card
                    cardSection {
                        HStack {
                            sectionLabel("DNS")
                            Spacer()

                            let passed = appState.dnsResults.filter { $0.success }.count
                            let total = appState.dnsResults.count
                            if total > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: passed == total ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(passed == total ? .green : .yellow)
                                    Text("\(passed)/\(total) OK")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(passed == total ? .green : .yellow)
                                }
                            } else {
                                Text("—")
                                    .font(.caption)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                    }

                    // Incident Card
                    if appState.currentIncident != nil {
                        incidentCard
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .opacity(probeOpacity)
            }

            Divider().opacity(0.5)

            // 最終診断時刻 + Footer Actions
            VStack(spacing: 6) {
                if let lastTime = appState.lastProbeTime {
                    Text("最終診断: \(lastTime.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                footerActions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360, height: 530)
        .animation(.easeInOut(duration: 0.3), value: appState.isProbing)
        .onChange(of: appState.isProbing) { _, isProbing in
            if isProbing {
                withAnimation(.easeOut(duration: 0.15)) {
                    probeOpacity = 0.4
                }
            } else {
                withAnimation(.easeIn(duration: 0.3)) {
                    probeOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            Text("NetShisa")
                .font(.system(.headline, design: .rounded))

            // Wi-Fi / 接続情報をタイトル横に
            Image(systemName: appState.wifiInfo.isWiFiConnected ? "wifi" : (appState.wifiInfo.isEthernet ? "cable.connector" : "wifi.slash"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(appState.wifiInfo.summaryText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let rssi = appState.wifiInfo.rssi {
                signalBars(appState.wifiInfo.signalBars)
                Text("\(rssi)dBm")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            overallStatusBadge
        }
    }

    private func signalBars(_ bars: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
    }

    private var overallStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(overallStatusColor)
                .frame(width: 7, height: 7)
                .shadow(color: overallStatusColor.opacity(0.5), radius: 3)
            Text(overallStatusLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(overallStatusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(overallStatusColor.opacity(0.12))
        )
    }

    private var overallStatusColor: Color {
        switch appState.overallStatus {
        case .good: return .green
        case .degraded: return .orange
        case .down: return .red
        }
    }

    private var overallStatusLabel: String {
        switch appState.overallStatus {
        case .good: return "正常"
        case .degraded: return "不安定"
        case .down: return "障害発生"
        }
    }

    // MARK: - Protocol Row

    private func protocolRow(label: String, state: ConnectivityState, latency: Double?) -> some View {
        HStack(spacing: 8) {
            StatusIndicator(state: state)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Spacer()
            if let latency {
                Text("\(Int(latency))ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(state.displayText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(state.color)
        }
    }

    // MARK: - Incident Card

    private var incidentCard: some View {
        cardSection {
            VStack(alignment: .leading, spacing: 8) {
                if let incident = appState.currentIncident {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                        Text(incident.classification)
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                    }
                }

                if let result = appState.lastRemediationResult {
                    ForEach(result.actions) { action in
                        HStack(spacing: 6) {
                            Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(action.success ? .green : .red)
                                .font(.system(size: 10))
                            Text(action.message)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await appState.runManualProbe() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(spinRotation))
                    Text("再診断")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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

            Button(action: { openDetailWindow() }) {
                Label("詳細", systemImage: "rectangle.expand.vertical")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if appState.currentIncident != nil {
                Button(action: { Task { await appState.runRemediation() } }) {
                    Label("修復", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .disabled(appState.isRemediating)
            }

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("NetShisa を終了")
        }
    }

    // MARK: - Helpers

    private func cardSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private static weak var detailWindow: NSWindow?

    private func openDetailWindow() {
        // ポップオーバーを閉じる
        NSApp.keyWindow?.performClose(nil)

        if let existing = Self.detailWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NetShisa — 詳細"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DetailWindow(appState: appState))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.detailWindow = window
    }
}

// MARK: - ConnectivityState UI Extensions

extension ConnectivityState {
    var displayText: String {
        switch self {
        case .reachable: return "接続中"
        case .unreachable: return "切断"
        case .degraded: return "不安定"
        case .unknown: return "確認中..."
        }
    }

    var color: Color {
        switch self {
        case .reachable: return .green
        case .unreachable: return .red
        case .degraded: return .yellow
        case .unknown: return .gray
        }
    }
}
