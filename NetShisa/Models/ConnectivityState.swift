import Foundation

enum ConnectivityState: String, Codable {
    case reachable
    case unreachable
    case degraded
    case unknown
}
