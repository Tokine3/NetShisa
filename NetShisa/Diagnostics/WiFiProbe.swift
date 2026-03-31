import Foundation
import CoreWLAN
import CoreLocation

/// Wi-Fi 接続情報
struct WiFiInfo {
    var isWiFiConnected: Bool = false
    var isEthernet: Bool = false
    var ssid: String?
    var bssid: String?
    var channel: Int?
    var frequencyBand: String?   // "2.4GHz" / "5GHz" / "6GHz"
    var rssi: Int?               // dBm
    var noise: Int?              // dBm
    var snr: Int?                // Signal-to-Noise Ratio
    var txRate: Double?          // Mbps
    var phyMode: String?         // "802.11ax" etc.
    var security: String?        // "WPA3 Personal" etc.
    var countryCode: String?
    var interfaceName: String?
    var connectedSince: Date?    // DHCP LeaseStartTime

    var signalQuality: String {
        guard let rssi else { return "不明" }
        if rssi >= -50 { return "非常に良好" }
        if rssi >= -60 { return "良好" }
        if rssi >= -70 { return "普通" }
        if rssi >= -80 { return "弱い" }
        return "非常に弱い"
    }

    var signalBars: Int {
        guard let rssi else { return 0 }
        if rssi >= -50 { return 4 }
        if rssi >= -60 { return 3 }
        if rssi >= -70 { return 2 }
        if rssi >= -80 { return 1 }
        return 0
    }

    /// ポップオーバー用の簡易表示文字列
    var summaryText: String {
        if isWiFiConnected {
            if let ssid, let band = frequencyBand {
                return "\(ssid) (\(band))"
            } else if let ssid {
                return ssid
            } else if let band = frequencyBand {
                return "Wi-Fi 接続中 (\(band))"
            } else {
                return "Wi-Fi 接続中"
            }
        } else if isEthernet {
            return "有線接続"
        } else {
            return "未接続"
        }
    }
}

/// Wi-Fi 周辺ネットワーク情報
struct NearbyNetwork: Identifiable {
    var id: String { "\(ssid)-\(bssid)" }
    let ssid: String
    let bssid: String
    let rssi: Int
    let channel: Int
    let band: String
}

final class WiFiProbe: NSObject, @unchecked Sendable, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationAuthorized = false

    /// 位置情報の許可状態が変わったときに呼ばれるコールバック
    var onAuthorizationChanged: (() -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        requestLocationIfNeeded()
    }

    private func requestLocationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            locationAuthorized = true
        default:
            locationAuthorized = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let wasAuthorized = locationAuthorized
        locationAuthorized = (manager.authorizationStatus == .authorizedAlways)
        // 未許可→許可に変わったら WiFi 情報を再取得させる
        if !wasAuthorized && locationAuthorized {
            onAuthorizationChanged?()
        }
    }

    /// 前回スキャンで取得した RSSI キャッシュ
    private var cachedScanRSSI: Int?
    private var lastScanTime: Date?

    /// system_profiler の Noise キャッシュ（重いので5分間保持）
    private var cachedNoise: Int?
    private var lastNoiseTime: Date?

    /// 軽量プローブ（初回・定期実行用）
    func probe() -> WiFiInfo {
        return probeInternal(allowScan: false)
    }

    /// フルプローブ（スキャンによる RSSI 取得を含む）
    func probeFull() -> WiFiInfo {
        return probeInternal(allowScan: true)
    }

    private func probeInternal(allowScan: Bool) -> WiFiInfo {
        var info = WiFiInfo()

        let client = CWWiFiClient.shared()
        guard let iface = client.interface() else {
            info.isEthernet = checkEthernetActive()
            return info
        }

        info.interfaceName = iface.interfaceName

        guard iface.powerOn() else {
            info.isEthernet = checkEthernetActive()
            return info
        }

        let isConnected = iface.serviceActive() && iface.wlanChannel() != nil

        if isConnected {
            info.isWiFiConnected = true

            info.ssid = iface.ssid() ?? getSSIDFallback()
            info.bssid = iface.bssid()

            // RSSI: CoreWLAN → キャッシュ → スキャン(許可時のみ)
            let rssi = iface.rssiValue()
            if rssi != 0 {
                info.rssi = rssi
            } else if let cached = cachedScanRSSI,
                      let lastScan = lastScanTime,
                      Date().timeIntervalSince(lastScan) < 120 {
                info.rssi = cached
            } else if allowScan, let bssid = info.bssid {
                let scanned = getRSSIFromScan(iface: iface, bssid: bssid)
                info.rssi = scanned
                cachedScanRSSI = scanned
                lastScanTime = Date()
            }

            // Noise: CoreWLAN → キャッシュ → system_profiler(重いので5分間キャッシュ)
            let noise = iface.noiseMeasurement()
            if noise != 0 {
                info.noise = noise
            } else if let cn = cachedNoise,
                      let lastNoise = lastNoiseTime,
                      Date().timeIntervalSince(lastNoise) < 300 {
                info.noise = cn
            } else if allowScan {
                let sp = getNoiseFromSystemProfiler()
                info.noise = sp
                cachedNoise = sp
                lastNoiseTime = Date()
            }

            info.txRate = iface.transmitRate()
            info.countryCode = iface.countryCode()

            if let rssiVal = info.rssi, let noiseVal = info.noise {
                info.snr = rssiVal - noiseVal
            }

            // チャンネル・周波数帯
            if let channel = iface.wlanChannel() {
                info.channel = channel.channelNumber
                switch channel.channelBand {
                case .band2GHz: info.frequencyBand = "2.4GHz"
                case .band5GHz: info.frequencyBand = "5GHz"
                case .band6GHz: info.frequencyBand = "6GHz"
                @unknown default: info.frequencyBand = "\(channel.channelNumber)ch"
                }
            }

            // PHY モード
            let mode = iface.activePHYMode()
            if mode != .modeNone {
                info.phyMode = phyModeString(mode)
            }

            // セキュリティ
            let security = iface.security()
            if security != .unknown {
                info.security = securityString(security)
            }

            // 接続時刻 (DHCP LeaseStartTime)
            if let ifName = iface.interfaceName {
                info.connectedSince = getLeaseStartTime(interfaceName: ifName)
            }
        } else {
            info.isEthernet = checkEthernetActive()
        }

        return info
    }

    /// 周辺ネットワークのスキャン
    func scanNearbyNetworks() -> [NearbyNetwork] {
        let client = CWWiFiClient.shared()
        guard let iface = client.interface() else { return [] }

        do {
            let networks = try iface.scanForNetworks(withSSID: nil)
            return networks.compactMap { network in
                guard let ssid = network.ssid, let bssid = network.bssid else { return nil }
                let ch = network.wlanChannel?.channelNumber ?? 0
                let band: String
                switch network.wlanChannel?.channelBand {
                case .band2GHz: band = "2.4GHz"
                case .band5GHz: band = "5GHz"
                case .band6GHz: band = "6GHz"
                default: band = ""
                }
                return NearbyNetwork(
                    ssid: ssid,
                    bssid: bssid,
                    rssi: network.rssiValue,
                    channel: ch,
                    band: band
                )
            }.sorted { $0.rssi > $1.rssi }
        } catch {
            return []
        }
    }

    /// スキャン結果から接続中 BSSID の RSSI を取得（CoreWLAN が 0 を返す場合のフォールバック）
    private func getRSSIFromScan(iface: CWInterface, bssid: String) -> Int? {
        guard let networks = try? iface.scanForNetworks(withSSID: nil) else { return nil }
        let normalized = bssid.lowercased()
        for network in networks {
            if let nb = network.bssid?.lowercased(), nb == normalized {
                let val = network.rssiValue
                return val != 0 ? val : nil
            }
        }
        return nil
    }

    /// DHCP LeaseStartTime から接続開始時刻を取得
    private func getLeaseStartTime(interfaceName: String) -> Date? {
        let output = runSync("/usr/sbin/ipconfig", arguments: ["getsummary", interfaceName])
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "LeaseStartTime : 03/31/2026 11:43:34"
            if trimmed.hasPrefix("LeaseStartTime") {
                if let colonRange = trimmed.range(of: ": ") {
                    let dateStr = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    return formatter.date(from: dateStr)
                }
            }
        }
        return nil
    }

    /// system_profiler から Noise を取得
    private func getNoiseFromSystemProfiler() -> Int? {
        let output = runSync("/usr/sbin/system_profiler", arguments: ["SPAirPortDataType"])
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "Signal / Noise: -55 dBm / -76 dBm"
            if trimmed.hasPrefix("Signal / Noise:") {
                let parts = trimmed.components(separatedBy: "/")
                if parts.count >= 3 {
                    let noisePart = parts[2].trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: " dBm", with: "")
                    return Int(noisePart)
                }
            }
        }
        return nil
    }

    /// SSID 取得のフォールバック (networksetup)
    /// macOS 14+ ではプライバシー制限により SSID が取得できない場合がある
    private func getSSIDFallback() -> String? {
        let nsOutput = runSync("/usr/sbin/networksetup", arguments: ["-getairportnetwork", "en0"])
        // "Current Wi-Fi Network: SSID_NAME"
        if let range = nsOutput.range(of: "Network: ") {
            let ssid = String(nsOutput[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !ssid.isEmpty && !ssid.contains("not associated") && !ssid.contains("Error") {
                return ssid
            }
        }
        // 取得できない場合は nil（summaryText で "Wi-Fi 接続中 (5GHz)" のように表示される）
        return nil
    }

    /// 有線 Ethernet が active かチェック（en0 以外の en* も確認）
    private func checkEthernetActive() -> Bool {
        // networksetup で Ethernet 系サービスの状態を確認
        let output = runSync("/usr/sbin/networksetup", arguments: ["-listallhardwareports"])
        let lines = output.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            // "Ethernet" を含むが "Wi-Fi" を含まないハードウェアポートを探す
            if line.contains("Ethernet") && !line.contains("Wi-Fi") && !line.contains("Thunderbolt") {
                if i + 1 < lines.count, lines[i + 1].contains("Device:") {
                    let device = lines[i + 1]
                        .replacingOccurrences(of: "Device:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let ifOutput = runSync("/sbin/ifconfig", arguments: [device])
                    if ifOutput.contains("status: active") {
                        return true
                    }
                }
            }
        }

        // Thunderbolt Bridge 等も確認
        let tbOutput = runSync("/sbin/ifconfig", arguments: ["bridge0"])
        if tbOutput.contains("status: active") {
            return true
        }

        return false
    }

    private func phyModeString(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a:  return "802.11a"
        case .mode11b:  return "802.11b"
        case .mode11g:  return "802.11g"
        case .mode11n:  return "802.11n (Wi-Fi 4)"
        case .mode11ac: return "802.11ac (Wi-Fi 5)"
        case .mode11ax: return "802.11ax (Wi-Fi 6/6E)"
        case .modeNone: return "不明"
        @unknown default: return "不明"
        }
    }

    private func securityString(_ security: CWSecurity) -> String {
        switch security {
        case .none:                return "Open"
        case .WEP:                 return "WEP"
        case .wpaPersonal:         return "WPA Personal"
        case .wpaPersonalMixed:    return "WPA/WPA2 Personal"
        case .wpa2Personal:        return "WPA2 Personal"
        case .personal:            return "WPA3 Personal"
        case .wpaEnterprise:       return "WPA Enterprise"
        case .wpaEnterpriseMixed:  return "WPA/WPA2 Enterprise"
        case .wpa2Enterprise:      return "WPA2 Enterprise"
        case .enterprise:          return "WPA3 Enterprise"
        case .dynamicWEP:          return "Dynamic WEP"
        case .unknown:             return "不明"
        @unknown default:          return "不明"
        }
    }

    private func runSync(_ path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
