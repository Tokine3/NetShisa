import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case dashboard     = "ダッシュボード"
    case timeline      = "タイムライン"
    case incidents     = "インシデント"
    case wifi          = "Wi-Fi"
    case networkDetail = "NW詳細"
    case dns           = "DNS"
    case icmp          = "ICMP"
    case settings      = "設定"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:     return "gauge.with.dots.needle.33percent"
        case .timeline:      return "chart.xyaxis.line"
        case .incidents:     return "exclamationmark.triangle"
        case .wifi:          return "wifi"
        case .networkDetail: return "network.badge.shield.half.filled"
        case .dns:           return "server.rack"
        case .icmp:          return "point.3.connected.trianglepath.dotted"
        case .settings:      return "gear"
        }
    }
}

struct DetailWindow: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: DetailTab = .dashboard

    var body: some View {
        NavigationSplitView {
            List(DetailTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(appState: appState)
                case .timeline:
                    TimelineView(appState: appState)
                case .incidents:
                    IncidentListView(appState: appState)
                case .wifi:
                    WiFiView(appState: appState)
                case .networkDetail:
                    NetworkDetailView(appState: appState)
                case .dns:
                    DNSDetailView(appState: appState)
                case .icmp:
                    ICMPView(appState: appState)
                case .settings:
                    SettingsView(appState: appState)
                }
            }
        }
        .frame(minWidth: 850, minHeight: 550)
    }
}
