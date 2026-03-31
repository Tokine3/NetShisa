import Foundation

struct ServiceDefinition: Identifiable, Codable {
    var id: String { hostname }
    let name: String
    let hostname: String
    let port: UInt16
    var supportsIPv4: Bool
    var supportsIPv6: Bool

    static let defaults: [ServiceDefinition] = [
        ServiceDefinition(name: "Discord", hostname: "discord.com", port: 443, supportsIPv4: true, supportsIPv6: false),
        ServiceDefinition(name: "X (Twitter)", hostname: "x.com", port: 443, supportsIPv4: true, supportsIPv6: false),
        ServiceDefinition(name: "Valorant", hostname: "playvalorant.com", port: 443, supportsIPv4: true, supportsIPv6: false),
        ServiceDefinition(name: "YouTube", hostname: "youtube.com", port: 443, supportsIPv4: true, supportsIPv6: true),
        ServiceDefinition(name: "Google", hostname: "google.com", port: 443, supportsIPv4: true, supportsIPv6: true),
        ServiceDefinition(name: "Apple", hostname: "apple.com", port: 443, supportsIPv4: true, supportsIPv6: true),
        ServiceDefinition(name: "GitHub", hostname: "github.com", port: 443, supportsIPv4: true, supportsIPv6: true),
    ]
}
