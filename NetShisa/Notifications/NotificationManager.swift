import Foundation
import UserNotifications

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    private init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendIncidentNotification(classification: String) {
        let content = UNMutableNotificationContent()
        content.title = "NetShisa: ネットワーク障害検出"
        content.body = classificationToMessage(classification)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendRecoveryNotification() {
        let content = UNMutableNotificationContent()
        content.title = "NetShisa: ネットワーク復旧"
        content.body = "ネットワーク接続が復旧しました。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func classificationToMessage(_ classification: String) -> String {
        switch classification {
        case "IPv4 Down / IPv6 Up":
            return "IPv4接続が失われています。IPv6のみのサービスは利用可能ですが、Discord・Xなど IPv4専用サービスに接続できません。"
        case "IPv6 Down / IPv4 Up":
            return "IPv6接続が失われています。ほとんどのサービスはIPv4で引き続き利用可能です。"
        case "Full Outage":
            return "インターネット接続が完全に失われています。"
        case "Gateway Unreachable":
            return "デフォルトゲートウェイに到達できません。ルーターの状態を確認してください。"
        case "DNS Failure":
            return "DNS解決に問題が発生しています。"
        default:
            return classification
        }
    }
}
