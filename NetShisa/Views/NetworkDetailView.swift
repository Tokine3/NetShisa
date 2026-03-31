import SwiftUI

struct NetworkDetailView: View {
    @ObservedObject var appState: AppState
    @State private var isLoading = false

    /// データが一度でも取得されたか
    private var hasData: Bool {
        !appState.networkDetail.interfaces.isEmpty || !appState.networkDetail.dnsServers.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ネットワーク詳細診断")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("インターフェース、RA、NDP、ルーティング、DNS の詳細情報")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: {
                    isLoading = true
                    Task {
                        appState.networkDetail = await appState.networkDetailProbe.probe()
                        isLoading = false
                    }
                }) {
                    HStack(spacing: 4) {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("再取得")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isLoading)

                // IPv6 再取得ボタン
                Button(action: {
                    Task {
                        isLoading = true
                        // RemediationEngine の IPv6 リセットを直接呼ぶ
                        let result = await appState.remediationEngine.resetIPv6Public()
                        appState.lastRemediationResult = RemediationResult(actions: [result], overallSuccess: result.success)
                        appState.networkDetail = await appState.networkDetailProbe.probe()
                        await appState.executeProbes()
                        isLoading = false
                    }
                }) {
                    Label("IPv6 再取得", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
                .disabled(isLoading)
            }
            .padding(20)

            Divider().opacity(0.3)

            if isLoading && !hasData {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("ネットワーク情報を取得中...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else if !hasData {
                // ここには通常到達しない（onAppear で自動取得するため）
                EmptyView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let detail = appState.displayNetworkDetail

                        // SSID / 接続情報
                        if let ssid = detail.ssid {
                            infoCard("接続中の Wi-Fi") {
                                monoText("SSID: \(ssid)")
                            }
                        }

                        // グローバル IP
                        globalIPSection

                        // RA (Router Advertisement) 状態
                        raSection(detail)

                        // インターフェース情報
                        interfaceSection(detail)

                        // NDP ネイバーテーブル
                        ndpSection(detail)

                        // ルーティングテーブル
                        routingSection(detail)

                        // DNS サーバー
                        dnsSection(detail)

                        // TCP 接続状態
                        tcpSection(detail)
                    }
                    .padding(20)
                }
            }
        }
        .onAppear {
            if !hasData {
                isLoading = true
                Task {
                    appState.networkDetail = await appState.networkDetailProbe.probe()
                    isLoading = false
                }
            }
        }
    }

    // MARK: - グローバル IP セクション

    private var globalIPSection: some View {
        infoCard("グローバル IP アドレス") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("IPv4")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                        .frame(width: 35, alignment: .trailing)
                    monoText(appState.displayGlobalIPv4 ?? "取得中...")
                        .foregroundColor(appState.displayGlobalIPv4 != nil ? .primary : .secondary)
                }
                HStack(spacing: 8) {
                    Text("IPv6")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.purple)
                        .frame(width: 35, alignment: .trailing)
                    monoText(appState.displayGlobalIPv6 ?? "なし")
                        .foregroundColor(appState.displayGlobalIPv6 != nil ? .primary : .secondary)
                }
            }
        }
    }

    // MARK: - RA セクション

    private func raSection(_ detail: NetworkDetail) -> some View {
        infoCard("IPv6 Router Advertisement (RA)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: detail.raReceived ? "checkmark.circle.fill" : "minus.circle.fill")
                        .foregroundColor(detail.raReceived ? .green : (appState.ipv6Status == .unreachable ? .red : .secondary))
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.raReceived ? "RA 受信中" : "RA 未検出")
                            .font(.system(size: 13, weight: .bold))
                        Text(detail.raReceived
                            ? "Wi-Fi インターフェースで IPv6 ルーター広告を受信しています。"
                            : appState.ipv6Status == .unreachable
                                ? "Wi-Fi インターフェースに RA が届いていません。ルーターの NDプロキシ / IPv6パススルー設定を確認してください。"
                                : "Wi-Fi インターフェース上で RA は検出されていません。v6プラス等では RA なしでも IPv4 over IPv6 は正常に動作します。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if !detail.ipv6Routers.isEmpty {
                    Divider().opacity(0.3)
                    Text("検出された IPv6 ルーター")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    tableView(
                        headers: ["アドレス", "IF", "Pref", "Expire", "Flags"],
                        widths: [220, 60, 60, 80, 60],
                        rows: detail.ipv6Routers.map { router in
                            [router.address, router.interface, router.preference, router.expire, router.flags]
                        }
                    )
                }

                if !detail.raReceived && appState.ipv6Status == .unreachable {
                    Divider().opacity(0.3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("切り分け手順")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                        monoText("""
                        1. ルーター管理画面で NDプロキシ or IPv6パススルーが有効か確認
                        2. ndp -rn でルーター側に RA ソースが存在するか確認
                        3. ルーターの WAN 側 IPv6 アドレスが取得できているか確認
                           → 取得できていない場合、ONU-ルーター間の IPv6 IPoE に問題
                        4. tcpdump -i en0 icmp6 で RA パケット (type=134) をキャプチャ
                        5. rtsol en0 で手動 RS (Router Solicitation) 送信を試行
                        """)
                    }
                }
            }
        }
    }

    // MARK: - インターフェースセクション

    private func interfaceSection(_ detail: NetworkDetail) -> some View {
        infoCard("インターフェース") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(detail.interfaces.filter { !$0.ipv4Addresses.isEmpty || !$0.ipv6Addresses.isEmpty }, id: \.name) { iface in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(iface.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text(iface.status)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(iface.status == "active" ? Color.green.opacity(0.15) : Color.red.opacity(0.15)))
                                .foregroundColor(iface.status == "active" ? .green : .red)
                            if let mtu = iface.mtu {
                                Text("MTU \(mtu)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if let mac = iface.macAddress {
                                Text(mac)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        ForEach(iface.ipv4Addresses, id: \.self) { addr in
                            HStack(spacing: 4) {
                                Text("IPv4")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.blue)
                                monoText(addr)
                            }
                            .padding(.leading, 16)
                        }

                        ForEach(iface.ipv6Addresses, id: \.address) { addr in
                            HStack(spacing: 4) {
                                Text("IPv6")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.purple)
                                monoText(addr.address)
                                Text("/\(addr.prefixLength)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(addr.scope)
                                    .font(.system(size: 8, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(scopeColor(addr.scope).opacity(0.12)))
                                    .foregroundColor(scopeColor(addr.scope))
                            }
                            .padding(.leading, 16)
                        }
                    }

                    if iface.name != detail.interfaces.last?.name {
                        Divider().opacity(0.2)
                    }
                }

                // グローバル IPv6 アドレスの有無チェック（IPv6 unreachable の場合のみ警告）
                let hasGlobal = detail.interfaces.flatMap(\.ipv6Addresses).contains { $0.scope == "global" }
                if !hasGlobal && appState.ipv6Status == .unreachable {
                    Divider().opacity(0.3)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("グローバル IPv6 アドレスが割り当てられていません。RA が受信できていないか、DHCPv6/SLAAC が機能していない可能性があります。")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    // MARK: - NDP セクション

    private func ndpSection(_ detail: NetworkDetail) -> some View {
        infoCard("NDP ネイバーテーブル (ndp -an)") {
            VStack(alignment: .leading, spacing: 6) {
                if detail.ndpNeighbors.isEmpty {
                    monoText("エントリなし")
                        .foregroundColor(.secondary)
                } else {
                    tableView(
                        headers: ["IPv6 アドレス", "MAC", "IF", "State"],
                        widths: [240, 130, 50, 80],
                        rows: detail.ndpNeighbors.prefix(20).map { entry in
                            [entry.address, entry.macAddress, entry.interface, entry.state]
                        }
                    )
                    if detail.ndpNeighbors.count > 20 {
                        Text("... 他 \(detail.ndpNeighbors.count - 20) エントリ")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - ルーティングセクション

    private func routingSection(_ detail: NetworkDetail) -> some View {
        infoCard("ルーティングテーブル") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IPv4 Default GW")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        monoText(detail.ipv4DefaultRoute ?? "なし")
                            .foregroundColor(detail.ipv4DefaultRoute != nil ? .primary : .red)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IPv6 Default GW")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        monoText(detail.ipv6DefaultRoute ?? "なし")
                            .foregroundColor(detail.ipv6DefaultRoute != nil ? .primary : .orange)
                    }
                }

                if detail.ipv6DefaultRoute == nil && appState.ipv6Status == .unreachable {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("IPv6 デフォルトルートが存在しません。RA によるルート広告が受信できていない可能性があります。")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                if !detail.routeEntries.isEmpty {
                    Divider().opacity(0.3)
                    Text("主要ルートエントリ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    tableView(
                        headers: ["Destination", "Gateway", "Flags", "IF"],
                        widths: [180, 180, 60, 60],
                        rows: detail.routeEntries.prefix(15).map { entry in
                            [entry.destination, entry.gateway, entry.flags, entry.interface]
                        }
                    )
                }
            }
        }
    }

    // MARK: - DNS セクション

    private func dnsSection(_ detail: NetworkDetail) -> some View {
        infoCard("DNS サーバー (scutil --dns)") {
            VStack(alignment: .leading, spacing: 4) {
                if detail.dnsServers.isEmpty {
                    monoText("DNS サーバーが設定されていません")
                        .foregroundColor(.red)
                } else {
                    ForEach(Array(detail.dnsServers.enumerated()), id: \.offset) { index, server in
                        HStack(spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            monoText(server)
                            // IPv4 or IPv6 表示
                            Text(server.contains(":") ? "v6" : "v4")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(server.contains(":") ? Color.purple.opacity(0.12) : Color.blue.opacity(0.12)))
                                .foregroundColor(server.contains(":") ? .purple : .blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - TCP セクション

    private func tcpSection(_ detail: NetworkDetail) -> some View {
        infoCard("TCP 接続状態 (netstat)") {
            HStack(spacing: 20) {
                tcpStatBadge("ESTABLISHED", count: detail.tcpEstablished, color: .green)
                tcpStatBadge("TIME_WAIT", count: detail.tcpTimeWait, color: .orange)
                tcpStatBadge("CLOSE_WAIT", count: detail.tcpCloseWait, color: .red)
            }
        }
    }

    private func tcpStatBadge(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.06))
        )
    }

    // MARK: - ヘルパー

    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func monoText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
    }

    private func tableView(headers: [String], widths: [CGFloat], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text(header)
                        .frame(width: widths[i], alignment: .leading)
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.05))

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                        Text(cell)
                            .frame(width: colIdx < widths.count ? widths[colIdx] : 100, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(rowIdx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
            }
        }
        .textSelection(.enabled)
    }

    private func scopeColor(_ scope: String) -> Color {
        switch scope {
        case "global": return .green
        case "link-local": return .blue
        case "unique-local": return .purple
        default: return .gray
        }
    }
}
