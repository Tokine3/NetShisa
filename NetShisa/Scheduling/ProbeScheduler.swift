import Foundation

final class ProbeScheduler: @unchecked Sendable {
    private var timer: Timer?
    private var probeAction: (() async -> Void)?
    private var isIncidentMode = false

    private var normalInterval: TimeInterval = 60
    private var incidentInterval: TimeInterval = 30

    func start(action: @escaping () async -> Void) {
        self.probeAction = action
        // 初回は 1 秒後に実行（UI 描画を優先）
        Task {
            try? await Task.sleep(for: .seconds(1))
            await action()
        }
        scheduleTimer(interval: normalInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func enterIncidentMode() {
        guard !isIncidentMode else { return }
        isIncidentMode = true
        scheduleTimer(interval: incidentInterval)
    }

    func exitIncidentMode() {
        guard isIncidentMode else { return }
        isIncidentMode = false
        scheduleTimer(interval: normalInterval)
    }

    /// 設定画面から呼ばれる即時反映
    func updateIntervals(normal: TimeInterval, incident: TimeInterval) {
        normalInterval = normal
        incidentInterval = incident
        // 現在のモードに応じたインターバルで再スケジュール
        scheduleTimer(interval: isIncidentMode ? incidentInterval : normalInterval)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let action = self?.probeAction else { return }
                Task {
                    await action()
                }
            }
        }
    }
}
