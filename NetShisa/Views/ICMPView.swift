import SwiftUI

enum ICMPTool: String, CaseIterable, Identifiable {
    case ping = "Ping"
    case ping6 = "Ping6"
    case traceroute = "Traceroute"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .ping: return "IPv4 ICMP Echo — 対象ホストへの到達性と RTT を測定"
        case .ping6: return "IPv6 ICMPv6 Echo — IPv6 経路での到達性と RTT を測定"
        case .traceroute: return "TTL インクリメントによるホップごとの経路追跡"
        }
    }
}

struct ICMPView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTool: ICMPTool = .ping
    @State private var target: String = "google.com"
    @State private var pingCount: Int = 10
    @State private var isRunning: Bool = false
    @State private var outputLines: [OutputLine] = []

    // Traceroute 用
    @State private var hops: [TracerouteHop] = []

    private let engine = TracerouteEngine()

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType

        enum LineType {
            case info, success, timeout, error, summary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 2) {
                Text("ICMP 診断ツール")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Ping / Ping6 / Traceroute によるネットワーク到達性・経路診断")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // ツール選択
            HStack(spacing: 0) {
                ForEach(ICMPTool.allCases) { tool in
                    VStack(spacing: 4) {
                        Text(tool.rawValue)
                            .font(.system(size: 12, weight: selectedTool == tool ? .bold : .medium))
                        Text(tool == .ping ? "IPv4" : tool == .ping6 ? "IPv6" : "経路追跡")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(
                        selectedTool == tool
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                    )
                    .overlay(alignment: .bottom) {
                        if selectedTool == tool {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                    .onTapGesture {
                        if !isRunning { selectedTool = tool }
                    }
                }
            }
            .background(Color.secondary.opacity(0.05))

            Divider().opacity(0.3)

            // 入力欄
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("ホスト名または IP アドレス", text: $target)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .onSubmit { if !isRunning && !target.isEmpty { run() } }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                        )
                )
                .frame(width: 280)

                if selectedTool == .ping || selectedTool == .ping6 {
                    HStack(spacing: 4) {
                        Text("回数:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("", value: $pingCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }

                Button(action: { run() }) {
                    HStack(spacing: 4) {
                        if isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isRunning ? "実行中..." : "実行")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isRunning || target.isEmpty)

                if isRunning {
                    Button(action: { stopRunning() }) {
                        Label("停止", systemImage: "stop.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.regular)
                }

                Button(action: { outputLines = []; hops = [] }) {
                    Label("クリア", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isRunning)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // 結果表示
            if selectedTool == .traceroute && !hops.isEmpty {
                tracerouteResultView
            } else {
                terminalOutputView
            }
        }
    }

    // MARK: - ターミナル風出力 (Ping / Ping6)

    private var terminalOutputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(outputLines) { line in
                        HStack(spacing: 6) {
                            Image(systemName: lineIcon(line.type))
                                .font(.system(size: 9))
                                .foregroundColor(lineColor(line.type))
                                .frame(width: 12)
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(lineColor(line.type))
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.03))
            .onChange(of: outputLines.count) { _, _ in
                if let last = outputLines.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Traceroute 結果テーブル

    private var tracerouteResultView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // サマリーバナー
                if !hops.isEmpty {
                    let reachedCount = hops.filter { !$0.timedOut }.count
                    let allReached = reachedCount == hops.count
                    HStack(spacing: 8) {
                        Image(systemName: allReached ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(allReached ? .green : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(allReached ? "Traceroute 成功" : "一部ホップでタイムアウト")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(target) — \(hops.count) ホップ中 \(reachedCount) ホップ応答")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(allReached ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder((allReached ? Color.green : Color.orange).opacity(0.2), lineWidth: 1)
                            )
                    )
                }

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("")
                            .frame(width: 10)
                        Text("#")
                            .frame(width: 26, alignment: .trailing)
                        Text("ホスト名")
                            .frame(width: 200, alignment: .leading)
                        Text("IP アドレス")
                            .frame(width: 160, alignment: .leading)
                        Text("応答時間")
                            .frame(width: 160, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.05))

                    ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                        HStack(spacing: 6) {
                            Image(systemName: hop.timedOut ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(hop.timedOut ? .secondary.opacity(0.4) : .green)

                            Text("\(hop.hopNumber)")
                                .frame(width: 26, alignment: .trailing)
                                .foregroundColor(.secondary)

                            if hop.timedOut {
                                Text("* * *")
                                    .foregroundStyle(.quaternary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(hop.hostname ?? hop.address ?? "—")
                                    .frame(width: 200, alignment: .leading)
                                    .lineLimit(1)

                                Text(hop.address ?? "")
                                    .foregroundColor(.secondary)
                                    .frame(width: 160, alignment: .leading)

                                HStack(spacing: 4) {
                                    ForEach(hop.latencyMs.indices, id: \.self) { i in
                                        Text("\(String(format: "%.1f", hop.latencyMs[i]))ms")
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                Capsule().fill(latencyColor(hop.latencyMs[i]).opacity(0.12))
                                            )
                                            .foregroundColor(latencyColor(hop.latencyMs[i]))
                                    }
                                }
                                .frame(width: 160, alignment: .leading)
                            }
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
                .textSelection(.enabled)

                // Traceroute 生ログも表示
                if !outputLines.isEmpty {
                    Text("生ログ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(outputLines) { line in
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.03))
                    )
                }
            }
            .padding(24)
        }
    }

    // MARK: - 実行

    @State private var runningProcess: Process?

    private func run() {
        outputLines = []
        hops = []
        isRunning = true

        switch selectedTool {
        case .ping:
            runPing(ipv6: false)
        case .ping6:
            runPing(ipv6: true)
        case .traceroute:
            runTraceroute()
        }
    }

    private func runPing(ipv6: Bool) {
        let cmd = ipv6 ? "/sbin/ping6" : "/sbin/ping"
        let args = ["-c", "\(pingCount)", target]

        addOutput("$ \(ipv6 ? "ping6" : "ping") -c \(pingCount) \(target)", type: .info)

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmd)
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            await MainActor.run { self.runningProcess = process }

            do {
                try process.run()

                let handle = pipe.fileHandleForReading
                // 行ごとに読み取り
                while process.isRunning || handle.availableData.count > 0 {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    if let str = String(data: data, encoding: .utf8) {
                        let lines = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                        for line in lines {
                            let type: OutputLine.LineType
                            if line.contains("bytes from") { type = .success }
                            else if line.contains("timeout") || line.contains("unreachable") { type = .timeout }
                            else if line.contains("statistics") || line.contains("round-trip") || line.contains("packet") { type = .summary }
                            else { type = .info }

                            await MainActor.run {
                                self.addOutput(line, type: type)
                            }
                        }
                    }
                }

                process.waitUntilExit()
                await MainActor.run {
                    let code = process.terminationStatus
                    if code == 0 {
                        self.addOutput("--- 完了: すべてのパケットが正常に到達しました ---", type: .success)
                    } else if code == 2 {
                        self.addOutput("--- 中断されました ---", type: .error)
                    } else {
                        self.addOutput("--- 完了: 一部のパケットが損失しました (終了コード: \(code)) ---", type: .timeout)
                    }
                    self.isRunning = false
                    self.runningProcess = nil
                }
            } catch {
                await MainActor.run {
                    self.addOutput("エラー: \(error.localizedDescription)", type: .error)
                    self.isRunning = false
                    self.runningProcess = nil
                }
            }
        }
    }

    private func runTraceroute() {
        addOutput("$ traceroute \(target)", type: .info)

        Task.detached { [target, engine] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
            process.arguments = ["-m", "30", "-w", "3", target]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            await MainActor.run { self.runningProcess = process }

            do {
                try process.run()

                var fullOutput = ""
                let handle = pipe.fileHandleForReading
                while process.isRunning || handle.availableData.count > 0 {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    if let str = String(data: data, encoding: .utf8) {
                        fullOutput += str
                        let lines = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                        for line in lines {
                            let type: OutputLine.LineType
                            if line.contains("* * *") { type = .timeout }
                            else if line.trimmingCharacters(in: .whitespaces).first?.isNumber == true { type = .success }
                            else { type = .info }
                            await MainActor.run {
                                self.addOutput(line, type: type)
                            }
                        }
                    }
                }

                process.waitUntilExit()
                let parsedHops = engine.parseOutput(fullOutput)

                await MainActor.run {
                    self.hops = parsedHops
                    let reachedCount = parsedHops.filter { !$0.timedOut }.count
                    let totalCount = parsedHops.count
                    if totalCount > 0 {
                        self.addOutput("--- traceroute 完了: \(totalCount) ホップ中 \(reachedCount) ホップ応答 ---", type: .summary)
                    }
                    self.isRunning = false
                    self.runningProcess = nil
                }
            } catch {
                await MainActor.run {
                    self.addOutput("エラー: \(error.localizedDescription)", type: .error)
                    self.isRunning = false
                    self.runningProcess = nil
                }
            }
        }
    }

    private func stopRunning() {
        runningProcess?.terminate()
        runningProcess = nil
        isRunning = false
        addOutput("--- 中断されました ---", type: .error)
    }

    private func addOutput(_ text: String, type: OutputLine.LineType) {
        outputLines.append(OutputLine(text: text, type: type))
    }

    // MARK: - ヘルパー

    private func lineIcon(_ type: OutputLine.LineType) -> String {
        switch type {
        case .info: return "chevron.right"
        case .success: return "checkmark.circle.fill"
        case .timeout: return "xmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .summary: return "chart.bar.fill"
        }
    }

    private func lineColor(_ type: OutputLine.LineType) -> Color {
        switch type {
        case .info: return .primary
        case .success: return .green
        case .timeout: return .red
        case .error: return .red
        case .summary: return .cyan
        }
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 20 { return .green }
        if ms < 80 { return .orange }
        return .red
    }
}
