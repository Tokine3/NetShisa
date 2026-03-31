import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("probeInterval") private var probeInterval: Double = 60
    @AppStorage("incidentProbeInterval") private var incidentProbeInterval: Double = 30
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("設定")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                // General
                settingsSection("一般") {
                    Toggle("ログイン時に自動起動", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                }

                // Probe Intervals
                settingsSection("監視間隔") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("通常時:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                            Slider(value: $probeInterval, in: 10...120, step: 5)
                                .onChange(of: probeInterval) { _, _ in applyIntervals() }
                            Text("\(Int(probeInterval))秒")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(width: 50)
                        }
                        HStack {
                            Text("障害時:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .trailing)
                            Slider(value: $incidentProbeInterval, in: 2...30, step: 1)
                                .onChange(of: incidentProbeInterval) { _, _ in applyIntervals() }
                            Text("\(Int(incidentProbeInterval))秒")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(width: 50)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("通常時: ネットワークが正常な間の診断実行間隔")
                            Text("障害時: インシデント検出後、復旧を確認するまでの短縮間隔")
                        }
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                        Text("変更は即時に反映されます")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Monitored Services
                settingsSection("監視サービス一覧") {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.serviceProbe.services.enumerated()), id: \.element.id) { index, service in
                            HStack(spacing: 12) {
                                Text(service.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 100, alignment: .leading)
                                Text(service.hostname)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if service.supportsIPv4 {
                                    Text("v4")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.blue.opacity(0.12)))
                                        .foregroundColor(.blue)
                                }
                                if service.supportsIPv6 {
                                    Text("v6")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.purple.opacity(0.12)))
                                        .foregroundColor(.purple)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Data Management
                settingsSection("データ管理") {
                    HStack(spacing: 12) {
                        Button(action: { exportLogs() }) {
                            Label("ログをエクスポート (JSON)", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button(action: { showDeleteConfirmation = true }) {
                            Label("全データを削除", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.regular)
                        .alert("全データを削除", isPresented: $showDeleteConfirmation) {
                            Button("削除", role: .destructive) { clearData() }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("接続ログ、インシデント履歴、DNS 結果などすべての記録データが削除されます。この操作は取り消せません。")
                        }
                    }
                }

                // About
                settingsSection("このアプリについて") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NetShisa v1.0.0")
                            .font(.system(size: 13, weight: .medium))
                        Text("macOS ネットワーク診断・修復ツール")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("IPv4 / IPv6 のデュアルスタック接続状態をリアルタイムに監視し、障害の原因特定と修復を支援します。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(24)
        }
    }

    /// スライダー変更を即時にスケジューラへ反映
    private func applyIntervals() {
        appState.probeScheduler.updateIntervals(
            normal: probeInterval,
            incident: incidentProbeInterval
        )
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                )
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("ログイン項目の更新に失敗: \(error)")
        }
    }

    private func exportLogs() {
        let fileName = "netshisa-logs-\(Date().ISO8601Format()).json"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let context = ModelContext(appState.modelContainer)
        let descriptor = FetchDescriptor<ConnectivitySnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let snapshots = try? context.fetch(descriptor) else { return }

        let data = snapshots.map { snapshot in
            [
                "timestamp": snapshot.timestamp.ISO8601Format(),
                "ipv4": snapshot.ipv4Status.rawValue,
                "ipv6": snapshot.ipv6Status.rawValue,
                "gateway_reachable": snapshot.gatewayIPv4Reachable,
                "gateway_latency_ms": snapshot.gatewayLatencyMs as Any,
                "interface": snapshot.activeInterface,
            ] as [String: Any]
        }

        if let json = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? json.write(to: url)
        }
    }

    private func clearData() {
        let context = ModelContext(appState.modelContainer)
        do {
            try context.delete(model: ConnectivitySnapshot.self)
            try context.delete(model: Incident.self)
            try context.delete(model: ServiceResult.self)
            try context.delete(model: DNSResult.self)
            try context.delete(model: TracerouteResult.self)
            try context.save()
        } catch {
            print("データ削除に失敗: \(error)")
        }
    }
}
