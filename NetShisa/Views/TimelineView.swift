import SwiftUI
import Charts
import SwiftData

struct TimelineView: View {
    @ObservedObject var appState: AppState
    @State private var snapshots: [ConnectivitySnapshot] = []
    @State private var timeRange: TimeRange = .hour1

    enum TimeRange: String, CaseIterable {
        case hour1 = "1時間"
        case hour6 = "6時間"
        case hour24 = "24時間"
        case week = "1週間"

        var interval: TimeInterval {
            switch self {
            case .hour1: return 3600
            case .hour6: return 3600 * 6
            case .hour24: return 3600 * 24
            case .week: return 3600 * 24 * 7
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("接続タイムライン")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("時系列での接続状態の変化を表示します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("期間", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            if snapshots.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("データがありません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("監視を開始するとタイムラインデータが記録されます。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Protocol Status Chart
                        chartCard("プロトコル状態") {
                            Chart {
                                ForEach(snapshots, id: \.timestamp) { snapshot in
                                    PointMark(
                                        x: .value("時刻", snapshot.timestamp),
                                        y: .value("プロトコル", "IPv4")
                                    )
                                    .foregroundStyle(snapshot.ipv4Status == .reachable ? .green : .red)
                                    .symbolSize(30)

                                    PointMark(
                                        x: .value("時刻", snapshot.timestamp),
                                        y: .value("プロトコル", "IPv6")
                                    )
                                    .foregroundStyle(snapshot.ipv6Status == .reachable ? .green : .red)
                                    .symbolSize(30)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(values: ["IPv4", "IPv6"])
                            }
                            .frame(height: 100)
                        }

                        // Gateway Latency Chart
                        chartCard("ゲートウェイ遅延") {
                            Chart {
                                ForEach(snapshots.filter { $0.gatewayLatencyMs != nil }, id: \.timestamp) { snapshot in
                                    LineMark(
                                        x: .value("時刻", snapshot.timestamp),
                                        y: .value("遅延 (ms)", snapshot.gatewayLatencyMs ?? 0)
                                    )
                                    .foregroundStyle(
                                        .linearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .lineStyle(StrokeStyle(lineWidth: 2))

                                    AreaMark(
                                        x: .value("時刻", snapshot.timestamp),
                                        y: .value("遅延 (ms)", snapshot.gatewayLatencyMs ?? 0)
                                    )
                                    .foregroundStyle(
                                        .linearGradient(
                                            colors: [.blue.opacity(0.15), .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                }
                            }
                            .chartYAxisLabel("ms")
                            .frame(height: 160)
                        }
                    }
                }
            }
        }
        .padding(24)
        .onAppear { loadSnapshots() }
        .onChange(of: timeRange) { _, _ in loadSnapshots() }
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    /// 表示する最大データポイント数
    private static let maxDataPoints = 500

    private func loadSnapshots() {
        let context = ModelContext(appState.modelContainer)
        let cutoff = Date().addingTimeInterval(-timeRange.interval)
        let descriptor = FetchDescriptor<ConnectivitySnapshot>(
            predicate: #Predicate { $0.timestamp > cutoff },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let all = (try? context.fetch(descriptor)) ?? []

        // データポイントが多すぎる場合は等間隔にサンプリング
        if all.count > Self.maxDataPoints {
            let step = Double(all.count) / Double(Self.maxDataPoints)
            var sampled: [ConnectivitySnapshot] = []
            var index: Double = 0
            while Int(index) < all.count {
                sampled.append(all[Int(index)])
                index += step
            }
            // 最新のデータは必ず含める
            if let last = all.last, sampled.last !== last {
                sampled.append(last)
            }
            snapshots = sampled
        } else {
            snapshots = all
        }
    }
}
