import SwiftUI

struct DNSDetailView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DNS 解決テスト")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("各 DNS サーバーに対する名前解決の成否と応答時間")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        Task { appState.dnsResults = await appState.dnsProbe.probeAll() }
                    }) {
                        Label("再テスト", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                if appState.dnsResults.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("データがありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("最初のプローブ実行後に結果が表示されます。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    let grouped = Dictionary(grouping: appState.dnsResults) { $0.domain }
                    ForEach(Array(grouped.keys.sorted()), id: \.self) { domain in
                        dnsCard(domain: domain, results: grouped[domain]!)
                    }
                }
            }
            .padding(24)
        }
    }

    private func dnsCard(domain: String, results: [DNSCheckResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(domain)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("サーバー")
                        .frame(width: 160, alignment: .leading)
                    Text("種別")
                        .frame(width: 50, alignment: .leading)
                    Text("状態")
                        .frame(width: 50, alignment: .center)
                    Text("応答時間")
                        .frame(width: 70, alignment: .trailing)
                    Text("解決アドレス")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))

                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    HStack {
                        Text(result.server)
                            .frame(width: 160, alignment: .leading)
                        Text(result.queryType)
                            .foregroundColor(result.queryType == "A" ? .blue : .purple)
                            .frame(width: 50, alignment: .leading)
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                            .frame(width: 50, alignment: .center)
                        if let latency = result.latencyMs {
                            Text("\(String(format: "%.1f", latency))ms")
                                .frame(width: 70, alignment: .trailing)
                        } else {
                            Text("—")
                                .foregroundStyle(.quaternary)
                                .frame(width: 70, alignment: .trailing)
                        }
                        Text(result.addresses.joined(separator: ", "))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
