import SwiftUI
import SwiftData

struct IncidentListView: View {
    @ObservedObject var appState: AppState
    @State private var incidents: [Incident] = []
    @State private var selectedIncident: Incident?

    var body: some View {
        HSplitView {
            // Left: Incident List
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("インシデント履歴")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(incidents.count) 件")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.secondary.opacity(0.1)))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().opacity(0.3)

                // Summary Bar
                if !incidents.isEmpty {
                    let ongoingCount = incidents.filter { $0.isOngoing }.count
                    let resolvedCount = incidents.count - ongoingCount
                    HStack(spacing: 16) {
                        summaryChip(icon: "flame.fill", label: "継続中", count: ongoingCount, color: .orange)
                        summaryChip(icon: "checkmark.circle.fill", label: "解決済", count: resolvedCount, color: .green)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.03))

                    Divider().opacity(0.3)
                }

                // List
                if incidents.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green.opacity(0.3))
                        Text("インシデントなし")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("ネットワーク障害は記録されていません")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else {
                    List(incidents, id: \.id, selection: $selectedIncident) { incident in
                        incidentRow(incident)
                            .tag(incident)
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: 320)

            // Right: Detail
            if let incident = selectedIncident {
                IncidentDetailView(incident: incident)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.25))
                    Text("インシデントを選択")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("左のリストから選択すると詳細と分析を表示します")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadIncidents() }
    }

    // MARK: - List Row

    private func incidentRow(_ incident: Incident) -> some View {
        HStack(spacing: 12) {
            // Status indicator with timeline-like line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(incident.isOngoing ? Color.orange.opacity(0.15) : Color.green.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: incident.isOngoing ? "flame.fill" : "checkmark.circle.fill")
                        .foregroundColor(incident.isOngoing ? .orange : .green)
                        .font(.system(size: 13))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(incident.classification)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if incident.isOngoing {
                        Text("継続中")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 10) {
                    Label(incident.startTime.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    if let duration = incident.duration {
                        Label(formatDuration(duration), systemImage: "timer")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func summaryChip(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func loadIncidents() {
        let context = ModelContext(appState.modelContainer)
        let descriptor = FetchDescriptor<Incident>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        var fetched = (try? context.fetch(descriptor)) ?? []

        #if DEBUG
        if fetched.isEmpty {
            fetched = Self.mockIncidents()
        }
        #endif

        incidents = fetched
    }

    #if DEBUG
    private static func mockIncidents() -> [Incident] {
        let now = Date()
        return [
            Incident(
                classification: "IPv4 Down / IPv6 Up",
                startTime: now.addingTimeInterval(-600) // 10分前〜継続中
            ),
            Incident(
                classification: "Full Outage",
                startTime: now.addingTimeInterval(-86400 - 1800), // 昨日
                endTime: now.addingTimeInterval(-86400 - 300) // 25分で復旧
            ),
            Incident(
                classification: "DNS Failure",
                startTime: now.addingTimeInterval(-172800 - 3600), // 2日前
                endTime: now.addingTimeInterval(-172800 - 2400) // 20分で復旧
            ),
            Incident(
                classification: "Gateway Unreachable",
                startTime: now.addingTimeInterval(-259200 - 7200), // 3日前
                endTime: now.addingTimeInterval(-259200 - 6900) // 5分で復旧
            ),
            Incident(
                classification: "IPv6 Down / IPv4 Up",
                startTime: now.addingTimeInterval(-432000 - 10800), // 5日前
                endTime: now.addingTimeInterval(-432000 - 3600) // 2時間で復旧
            ),
            Incident(
                classification: "Partial Outage: Discord, Valorant",
                startTime: now.addingTimeInterval(-604800), // 1週間前
                endTime: now.addingTimeInterval(-604800 + 5400) // 1.5時間で復旧
            ),
        ]
    }
    #endif

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))秒"
        } else if duration < 3600 {
            return "\(Int(duration / 60))分\(Int(duration.truncatingRemainder(dividingBy: 60)))秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)時間\(minutes)分"
        }
    }
}

// MARK: - Detail View

struct IncidentDetailView: View {
    let incident: Incident

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                header

                // Info Grid
                infoSection

                // Analysis
                analysisSection
            }
            .padding(24)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(incident.isOngoing ? Color.orange.opacity(0.12) : Color.green.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: incident.isOngoing ? "flame.fill" : "checkmark.circle.fill")
                    .foregroundColor(incident.isOngoing ? .orange : .green)
                    .font(.system(size: 22))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(incident.classification)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    Text(incident.isOngoing ? "継続中" : "解決済み")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(incident.isOngoing ? .orange : .green)
                    if let duration = incident.duration {
                        Text("(\(formatDuration(duration)))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(incident.isOngoing ? Color.orange.opacity(0.05) : Color.green.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder((incident.isOngoing ? Color.orange : Color.green).opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("詳細")

            VStack(spacing: 0) {
                infoRow(icon: "tag", label: "分類", value: incident.classification)
                Divider().opacity(0.15).padding(.horizontal, 12)
                infoRow(icon: "clock", label: "発生", value: formatDateTime(incident.startTime))
                if let endTime = incident.endTime {
                    Divider().opacity(0.15).padding(.horizontal, 12)
                    infoRow(icon: "clock.badge.checkmark", label: "解決", value: formatDateTime(endTime))
                }
                if let duration = incident.duration {
                    Divider().opacity(0.15).padding(.horizontal, 12)
                    infoRow(icon: "timer", label: "所要時間", value: formatDuration(duration))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            )
        }
    }

    // MARK: - Analysis Section

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("分析・対処方法")

            let sections = parseAnalysis(classificationExplanation(incident.classification))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if section.isHeading {
                        Text(section.text)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.top, section.text.contains("影響") ? 0 : 4)
                    } else {
                        Text(section.text)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            )
        }
    }

    // MARK: - Components

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Analysis Parser

    private struct AnalysisBlock: Hashable {
        let text: String
        let isHeading: Bool
    }

    private func parseAnalysis(_ raw: String) -> [AnalysisBlock] {
        var blocks: [AnalysisBlock] = []
        var currentText = ""

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !currentText.isEmpty {
                    blocks.append(AnalysisBlock(text: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isHeading: false))
                    currentText = ""
                }
                continue
            }
            // Heading lines with 【】
            if trimmed.hasPrefix("【") && trimmed.hasSuffix("】") {
                if !currentText.isEmpty {
                    blocks.append(AnalysisBlock(text: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isHeading: false))
                    currentText = ""
                }
                blocks.append(AnalysisBlock(text: trimmed, isHeading: true))
                continue
            }
            // Skip separator lines
            if trimmed.hasPrefix("━") { continue }

            currentText += (currentText.isEmpty ? "" : "\n") + trimmed
        }
        if !currentText.isEmpty {
            blocks.append(AnalysisBlock(text: currentText.trimmingCharacters(in: .whitespacesAndNewlines), isHeading: false))
        }
        return blocks
    }

    // MARK: - Helpers

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd(E) HH:mm"
        return f.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))秒"
        } else if duration < 3600 {
            return "\(Int(duration / 60))分\(Int(duration.truncatingRemainder(dividingBy: 60)))秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)時間\(minutes)分"
        }
    }

    // MARK: - Analysis Content

    private func classificationExplanation(_ classification: String) -> String {
        switch classification {
        case "IPv4 Down / IPv6 Up":
            return """
            IPv4 接続が失われ、IPv6 のみが機能しています。

            【影響範囲】
            接続不可:
            ・Discord（音声・テキスト・画面共有すべて）
            ・X (Twitter)（タイムライン・投稿・DM）
            ・Valorant（ゲームサーバー・Riot クライアント）
            ・その他 IPv4 専用サービス全般

            引き続き利用可能（IPv6 経由）:
            ・YouTube（動画視聴・検索・コメント）
            ・Netflix（ストリーミング再生）
            ・Google 検索、Gmail、Google Drive
            ・その他 IPv6 対応（デュアルスタック）サービス

            【原因分析 — v6プラス / IPv6 IPoE (MAP-E) 環境】
            v6プラスでは IPv4 通信を MAP-E 方式で IPv6 上にカプセル化しています。
            IPv4 のみ切断される場合、以下の原因が考えられます:

            1. MAP-E ボーダーリレー (BR) の障害
               → JPNE (日本ネットワークイネイブラー) 側の設備障害。
                 ユーザー側では対処不可。時間経過で復旧を待つか ISP に問い合わせ。

            2. MAP-E ポート割り当ての枯渇・競合
               → v6プラスでは各ユーザーに割り当てられる IPv4 ポートが限定的
                 （通常 240 ポート程度）。同時接続数が多いと枯渇する場合あり。
               → ルーターの再起動でポートテーブルがリセットされ改善する可能性。

            3. ルーターの MAP-E トンネル設定異常
               → ルーターのファームウェア不具合やメモリ不足により
                 MAP-E トンネルが切断されることがある。
               → ルーター再起動で復旧する場合が多い。

            4. VNE 側の設備メンテナンス・障害
               → 回線事業者のメンテナンス情報を確認してください。

            【原因分析 — DS-Lite 環境 (transix 等)】
            1. AFTR (Address Family Transition Router) の障害
               → DS-Lite のトンネル終端装置の障害。VNE 側の対応を待つ。

            2. トンネルセッションの切断
               → ルーター再起動で再確立される場合が多い。

            【原因分析 — PPPoE 環境】
            1. PPPoE セッション切断
               → ルーターの PPPoE 接続が切れている可能性。
               → ルーター管理画面で接続状態を確認。

            2. DHCP リースの期限切れ
               → PC の IPv4 アドレスが失効している。
               → 「修復」ボタンでリース更新を試行。

            3. ISP 側の IPv4 網障害
               → フレッツ網の網終端装置（NTE）の混雑・障害の可能性。

            【推奨対処手順】
            ① このアプリの「修復」ボタンを押す
               → DHCP リース更新・DNS キャッシュフラッシュを自動実行

            ② 改善しない場合 → ルーターを再起動（電源OFF→30秒待機→ON）
               → MAP-E/DS-Lite トンネルの再確立、ポートテーブルのリセット

            ③ それでも改善しない場合
               → ISP / VNE の障害情報ページを確認
               → 一時的にスマートフォンのテザリング等で代替接続
            """

        case "IPv6 Down / IPv4 Up":
            return """
            IPv6 接続が失われていますが、IPv4 は正常に動作しています。

            【影響範囲】
            ほとんどのサービスは IPv4 で引き続き利用可能です。
            ただし v6プラス / IPoE 環境では以下の影響があります:

            ・IPv4 通信が MAP-E/DS-Lite トンネル経由ではなく
              PPPoE フォールバックに切り替わる場合、速度が低下する可能性
            ・IPv6 専用のサービス・機能が利用不可

            【考えられる原因】
            1. ISP / VNE 側の IPv6 網障害
               → NTT フレッツ網の IPv6 (NGN) 側の障害

            2. ルーターの IPv6 設定異常
               → RA (Router Advertisement) の受信失敗
               → DHCPv6 の取得失敗

            3. IPv6 アドレスの再取得失敗
               → ルーター再起動で RA/DHCPv6 を再取得

            4. 上流回線の IPv6 経路障害
               → traceroute6 で経路を確認してください

            【推奨対処手順】
            ① ルーターの IPv6 接続状態を管理画面で確認
            ② ルーターを再起動して IPv6 アドレスを再取得
            ③ 改善しない場合は ISP に問い合わせ
            """

        case "Full Outage":
            return """
            IPv4・IPv6 ともに接続が完全に失われています。
            インターネットに全く接続できない状態です。

            【影響範囲】
            すべてのインターネットサービスが利用不可です。
            ローカルネットワーク（ファイル共有・プリンター等）は
            ゲートウェイの状態により利用可能な場合があります。

            【考えられる原因】
            1. ルーターの障害・フリーズ
               → ルーターのランプ状態を確認。異常点滅していないか。

            2. ONU (光回線終端装置) の障害
               → ONU の「認証」「光回線」ランプが消灯していないか確認。
               → 光ファイバーケーブルの断線・接触不良の可能性。

            3. ISP / NTT 側の回線障害
               → 地域的な大規模障害の可能性。
               → スマートフォン（モバイル回線）で ISP の障害情報を確認。

            4. Wi-Fi 接続の切断（無線の場合）
               → Mac の Wi-Fi が切れている可能性。
               → 他のデバイスで同じ Wi-Fi に接続できるか確認。

            5. LAN ケーブルの断線・接触不良（有線の場合）
               → ケーブルの差し直しを試行。

            【推奨対処手順】
            ① Mac の Wi-Fi / 有線接続を確認（接続されているか）
            ② ルーターのランプ状態を目視確認
            ③ ルーターと ONU の電源を切り、30秒後に ONU → ルーターの順で起動
            ④ 5分待って接続を確認
            ⑤ 改善しない場合 → ISP に電話問い合わせ
               → スマートフォンのテザリングで一時的に代替
            """

        case "Gateway Unreachable":
            return """
            デフォルトゲートウェイ（ルーター）に到達できません。
            ローカルネットワーク自体に問題がある状態です。

            【影響範囲】
            すべてのインターネット通信が不可能です。
            同一ネットワーク上の他のデバイスとの通信も
            ルーター経由の場合は不可能な可能性があります。

            【考えられる原因】
            1. Wi-Fi が切断されている
               → Mac の Wi-Fi アイコンを確認。接続先 SSID が表示されているか。
               → Wi-Fi のパスワードが変更された可能性。

            2. ルーターがフリーズ・停止している
               → ルーターのランプが消灯または異常点滅していないか。
               → ルーターの電源を確認。

            3. DHCP によるアドレス取得失敗
               → Mac が IP アドレスを取得できていない可能性。
               → システム環境設定 > ネットワーク で IP アドレスを確認。
                 「169.254.x.x」の場合は DHCP 取得失敗。

            4. LAN ケーブルの物理的断線（有線の場合）
               → ケーブルの差し直し、別のポートへの接続を試行。

            5. MAC アドレスフィルタリング
               → ルーター側で Mac の MAC アドレスがブロックされている可能性。

            【推奨対処手順】
            ① このアプリの「修復」ボタンを押す（Wi-Fi リセット + DHCP 更新）
            ② Mac の Wi-Fi をオフ → オン
            ③ ルーターの電源を入れ直す
            ④ システム環境設定 > ネットワーク で IP アドレスが正しく取得されているか確認
            """

        case "DNS Failure":
            return """
            DNS（ドメインネームシステム）の名前解決に問題が発生しています。
            IP アドレス直指定の通信は可能ですが、ドメイン名での通信が失敗します。

            【影響範囲】
            ・Web サイトへのアクセス時に「サーバーが見つかりません」エラー
            ・アプリのログインやAPI通信が失敗する場合がある
            ・IP アドレス直指定（8.8.8.8 等）での通信は正常

            【考えられる原因】
            1. ISP の DNS サーバー障害
               → ISP が提供する DNS サーバーが応答しない状態。
               → Google DNS (8.8.8.8) や Cloudflare DNS (1.1.1.1) への
                 切替で改善する場合、ISP DNS 側の問題。

            2. ルーターの DNS プロキシ障害
               → ルーターが DNS クエリを中継する際にフリーズしている。
               → ルーター再起動で改善する場合が多い。

            3. DNS キャッシュの破損
               → ローカルの DNS キャッシュが不整合を起こしている。
               → 「修復」ボタンで DNS フラッシュを実行。

            4. DNS over HTTPS/TLS の設定問題
               → システムまたはブラウザで DoH/DoT が有効な場合、
                 その暗号化 DNS サーバーに問題がある可能性。

            【推奨対処手順】
            ① このアプリの「修復」ボタンを押す（DNS キャッシュフラッシュ）
            ② 改善しない場合 → ルーターを再起動
            ③ それでも改善しない場合
               → システム環境設定 > ネットワーク > DNS で
                 8.8.8.8 と 8.8.4.4 を手動設定
            """

        default:
            if classification.hasPrefix("Partial Outage:") {
                let services = classification.replacingOccurrences(of: "Partial Outage: ", with: "")
                return """
                一部のサービスで接続障害が発生しています。

                【影響サービス】
                \(services)

                【考えられる原因】
                1. サービス側の障害
                   → 対象サービスのステータスページを確認してください。
                   → Discord: discordstatus.com
                   → X: status.x.com
                   → Valorant: status.riotgames.com

                2. 特定サービスへの経路障害
                   → ISP から対象サービスまでの間のネットワーク経路に
                     問題がある可能性。Traceroute タブで経路を確認できます。

                3. DNS による名前解決の一部失敗
                   → 特定ドメインの DNS 応答が遅延・失敗している可能性。
                   → DNS タブで詳細を確認してください。

                【推奨対処手順】
                ① 対象サービスの公式ステータスページを確認
                ② Traceroute タブで対象サービスへの経路を確認
                ③ しばらく待って再診断を実行
                """
            }
            return classification
        }
    }
}
