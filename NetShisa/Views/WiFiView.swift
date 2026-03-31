import SwiftUI

struct WiFiView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi 詳細情報")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("接続中の Wi-Fi アクセスポイントの詳細情報")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        let probe = appState.wifiProbe
                        Task.detached {
                            let info = probe.probeFull()
                            await MainActor.run { appState.wifiInfo = info }
                        }
                    }) {
                        Label("更新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                let info = appState.displayWifiInfo

                if !info.isWiFiConnected && !info.isEthernet {
                    notConnectedView
                } else if info.isEthernet && !info.isWiFiConnected {
                    ethernetView
                } else {
                    connectionSummaryCard(info)

                    if appState.rssiHistory.count >= 2 {
                        rssiChartCard
                    }

                    HStack(alignment: .top, spacing: 16) {
                        signalCard(info)
                        radioCard(info)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - 接続サマリー

    private func connectionSummaryCard(_ info: WiFiInfo) -> some View {
        styledCard("接続情報") {
            HStack(spacing: 20) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(wifiDisplayColor(info).opacity(0.1))
                            .frame(width: 56, height: 56)
                        Image(systemName: wifiIcon(info))
                            .font(.system(size: 24))
                            .foregroundColor(wifiDisplayColor(info))
                    }
                    Text(wifiDisplayQuality(info))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(wifiDisplayColor(info))
                }

                VStack(alignment: .leading, spacing: 6) {
                    infoRow("SSID", value: info.ssid ?? "(取得不可)")
                    infoRow("BSSID", value: info.bssid ?? "—")
                    infoRow("チャンネル", value: info.channel.map { "\($0)" } ?? "—")
                    infoRow("周波数帯", value: info.frequencyBand ?? "—")
                    infoRow("セキュリティ", value: info.security ?? "—")
                    if let iface = info.interfaceName {
                        infoRow("IF", value: iface)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - 信号カード

    private func signalCard(_ info: WiFiInfo) -> some View {
        styledCard("信号品質") {
            VStack(alignment: .leading, spacing: 8) {
                signalRow("RSSI", value: info.rssi.map { "\($0) dBm" } ?? "—",
                           detail: rssiExplanation(info.rssi),
                           color: signalColor(info.signalBars))
                Divider().opacity(0.2)
                signalRow("Noise", value: info.noise.map { "\($0) dBm" } ?? "—",
                           detail: "環境ノイズレベル", color: .secondary)
                Divider().opacity(0.2)
                signalRow("SNR", value: info.snr.map { "\($0) dB" } ?? "—",
                           detail: snrExplanation(info.snr),
                           color: snrColor(info.snr))
                Divider().opacity(0.2)
                signalRow("TX Rate", value: info.txRate.map { "\(Int($0)) Mbps" } ?? "—",
                           detail: "現在のリンク速度", color: .secondary)
            }
        }
    }

    // MARK: - 無線規格カード

    private func radioCard(_ info: WiFiInfo) -> some View {
        styledCard("無線規格") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("PHY モード", value: info.phyMode ?? "—")
                Divider().opacity(0.2)
                infoRow("周波数帯", value: info.frequencyBand ?? "—")
                Divider().opacity(0.2)
                infoRow("チャンネル", value: info.channel.map { "ch \($0)" } ?? "—")
                Divider().opacity(0.2)
                infoRow("国コード", value: info.countryCode ?? "—")
            }
        }
    }

    // MARK: - RSSI 推移グラフ

    private var rssiChartCard: some View {
        styledCard("信号強度の推移") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let latest = appState.rssiHistory.last {
                        Text("\(latest.rssi) dBm")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(rssiChartColor(latest.rssi))
                    }
                    Spacer()
                    Text("直近 \(appState.rssiHistory.count) 回の測定")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    let data = appState.rssiHistory.map { $0.rssi }
                    let minVal = max((data.min() ?? -90) - 5, -100)
                    let maxVal = min((data.max() ?? -30) + 5, -20)
                    let range = Double(maxVal - minVal)
                    let w = geo.size.width
                    let h = geo.size.height

                    // 背景の品質ゾーン
                    ZStack(alignment: .topLeading) {
                        // 良好ゾーン (>= -50)
                        rssiZone(label: "良好", threshold: -50, minVal: minVal, maxVal: maxVal, height: h, color: .green)
                        // 普通ゾーン (-70 ~ -50)
                        rssiZone(label: "普通", threshold: -70, minVal: minVal, maxVal: maxVal, height: h, color: .orange)

                        // 折れ線グラフ
                        Path { path in
                            for (i, val) in data.enumerated() {
                                let x = data.count > 1
                                    ? w * CGFloat(i) / CGFloat(data.count - 1)
                                    : w / 2
                                let y = range > 0
                                    ? h * (1.0 - CGFloat(val - minVal) / CGFloat(range))
                                    : h / 2
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        // グラデーション塗りつぶし
                        Path { path in
                            for (i, val) in data.enumerated() {
                                let x = data.count > 1
                                    ? w * CGFloat(i) / CGFloat(data.count - 1)
                                    : w / 2
                                let y = range > 0
                                    ? h * (1.0 - CGFloat(val - minVal) / CGFloat(range))
                                    : h / 2
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: h))
                                    path.addLine(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            if !data.isEmpty {
                                let lastX = data.count > 1 ? w : w / 2
                                path.addLine(to: CGPoint(x: lastX, y: h))
                            }
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )

                        // 最新値のドット
                        if let lastVal = data.last {
                            let x = data.count > 1 ? w : w / 2
                            let y = range > 0
                                ? h * (1.0 - CGFloat(lastVal - minVal) / CGFloat(range))
                                : h / 2
                            Circle()
                                .fill(rssiChartColor(lastVal))
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }

                    // Y軸ラベル
                    VStack {
                        Text("\(maxVal)")
                        Spacer()
                        Text("\(minVal)")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 80)
            }
        }
    }

    private func rssiZone(label: String, threshold: Int, minVal: Int, maxVal: Int, height: CGFloat, color: Color) -> some View {
        let range = Double(maxVal - minVal)
        let clampedTop = min(max(threshold, minVal), maxVal)
        let yTop = range > 0 ? height * (1.0 - CGFloat(clampedTop - minVal) / CGFloat(range)) : 0

        return Rectangle()
            .fill(color.opacity(0.04))
            .frame(height: max(0, height - yTop))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func rssiChartColor(_ rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -60 { return .green }
        if rssi >= -70 { return .orange }
        return .red
    }

    // MARK: - 未接続 / 有線

    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Wi-Fi 未接続")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Wi-Fi に接続すると詳細情報が表示されます。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var ethernetView: some View {
        styledCard("接続情報") {
            HStack(spacing: 12) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("有線接続 (Ethernet)")
                        .font(.system(size: 13, weight: .bold))
                    Text("Wi-Fi は未使用です。有線 LAN で接続されています。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - ヘルパー

    private func styledCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                )
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func signalRow(_ label: String, value: String, detail: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .trailing)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 80)
            Text(detail)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func signalColor(_ bars: Int) -> Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .orange
        case 1: return .red
        default: return .secondary
        }
    }

    private func wifiIcon(_ info: WiFiInfo) -> String {
        if info.isWiFiConnected && info.rssi == nil {
            return "wifi"
        }
        switch info.signalBars {
        case 1: return "wifi.exclamationmark"
        default: return "wifi"
        }
    }

    private func wifiDisplayColor(_ info: WiFiInfo) -> Color {
        if info.isWiFiConnected && info.rssi == nil {
            return .blue
        }
        return signalColor(info.signalBars)
    }

    private func wifiDisplayQuality(_ info: WiFiInfo) -> String {
        if info.isWiFiConnected && info.rssi == nil {
            return "接続中"
        }
        return info.signalQuality
    }

    private func rssiExplanation(_ rssi: Int?) -> String {
        guard let rssi else { return "" }
        if rssi >= -50 { return "非常に良好 (>= -50)" }
        if rssi >= -60 { return "良好 (-60 ~ -50)" }
        if rssi >= -70 { return "普通 (-70 ~ -60)" }
        if rssi >= -80 { return "弱い (-80 ~ -70)" }
        return "非常に弱い (< -80)"
    }

    private func snrExplanation(_ snr: Int?) -> String {
        guard let snr else { return "" }
        if snr >= 40 { return "非常に良好 (>= 40)" }
        if snr >= 25 { return "良好 (25-40)" }
        if snr >= 15 { return "普通 (15-25)" }
        return "不良 (< 15)"
    }

    private func snrColor(_ snr: Int?) -> Color {
        guard let snr else { return .gray }
        if snr >= 25 { return .green }
        if snr >= 15 { return .orange }
        return .red
    }
}
