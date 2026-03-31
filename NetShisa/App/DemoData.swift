#if DEBUG
import Foundation

/// スクリーンショット撮影用のダミーデータ
enum DemoData {
    static let ssid = "MyHome-WiFi-5G"
    static let bssid = "a1:b2:c3:d4:e5:f6"
    static let localIPv4 = "192.168.1.128"
    static let gatewayIPv4 = "192.168.1.1"
    static let gatewayIPv6 = "fe80::1"
    static let globalIPv4 = "203.0.113.75"
    static let globalIPv6 = "2001:db8:1a2b::c3d4"

    static let macAddress = "a1:b2:c3:d4:e5:f6"
    static let dnsServers = ["192.168.1.1", "2001:db8::1"]

    /// WiFiInfo のセンシティブフィールドをダミーに置換
    static func mask(_ info: WiFiInfo) -> WiFiInfo {
        var masked = info
        if info.isWiFiConnected {
            masked.ssid = ssid
            masked.bssid = bssid
        }
        return masked
    }

    /// NetworkDetail のセンシティブフィールドをダミーに置換
    static func mask(_ detail: NetworkDetail) -> NetworkDetail {
        var masked = detail

        if detail.ssid != nil {
            masked.ssid = ssid
        }

        // インターフェース
        masked.interfaces = detail.interfaces.map { iface in
            InterfaceInfo(
                name: iface.name,
                ipv4Addresses: iface.ipv4Addresses.enumerated().map { i, _ in
                    "192.168.1.\(128 + i)"
                },
                ipv6Addresses: iface.ipv6Addresses.map { addr in
                    let demoAddr: String
                    switch addr.scope {
                    case "global":     demoAddr = "2001:db8:1a2b::\(addr.address.suffix(4))"
                    case "link-local": demoAddr = "fe80::\(addr.address.suffix(4))"
                    default:           demoAddr = "fd00::\(addr.address.suffix(4))"
                    }
                    return IPv6AddressInfo(address: demoAddr, prefixLength: addr.prefixLength, scope: addr.scope)
                },
                macAddress: iface.macAddress != nil ? macAddress : nil,
                mtu: iface.mtu,
                status: iface.status
            )
        }

        // NDP
        masked.ndpNeighbors = detail.ndpNeighbors.enumerated().map { i, entry in
            NDPNeighborEntry(
                address: "fe80::\(String(format: "%x", 100 + i))",
                macAddress: String(format: "aa:bb:cc:dd:%02x:%02x", i / 256, i % 256),
                interface: entry.interface,
                state: entry.state
            )
        }

        // ルーティング
        if detail.ipv4DefaultRoute != nil { masked.ipv4DefaultRoute = gatewayIPv4 }
        if detail.ipv6DefaultRoute != nil { masked.ipv6DefaultRoute = gatewayIPv6 }
        masked.routeEntries = detail.routeEntries.map { entry in
            RouteEntry(
                destination: maskRouteAddress(entry.destination),
                gateway: maskRouteAddress(entry.gateway),
                interface: entry.interface,
                flags: entry.flags
            )
        }

        // DNS
        if !detail.dnsServers.isEmpty {
            masked.dnsServers = dnsServers
        }

        // IPv6 ルーター
        masked.ipv6Routers = detail.ipv6Routers.enumerated().map { i, router in
            IPv6RouterInfo(
                address: "fe80::\(String(format: "%x", 1 + i))",
                interface: router.interface,
                flags: router.flags,
                preference: router.preference,
                expire: router.expire
            )
        }

        return masked
    }

    private static func maskRouteAddress(_ addr: String) -> String {
        if addr == "default" || addr == "link" || addr.isEmpty { return addr }
        if addr.contains(":") { return "2001:db8::\(addr.suffix(4))" }
        return "192.168.1.\(addr.suffix(1))"
    }
}
#endif
