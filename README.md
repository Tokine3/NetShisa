# NetShisa

macOS ネットワーク診断・監視ツール。IPv4 / IPv6 のデュアルスタック接続状態をリアルタイムに監視し、障害の原因特定と修復を支援します。

## 特徴

- **メニューバー常駐** — Dock に表示されず、メニューバーからワンクリックでネットワーク状態を確認
- **デュアルスタック監視** — IPv4 / IPv6 の疎通・レイテンシーを定期的に自動診断
- **インシデント自動検出** — 接続断・DNS障害・ゲートウェイ不通などを自動分類し、詳細な原因分析と対処手順を提示
- **自動修復** — DHCP リース更新、DNS キャッシュフラッシュなどをワンクリックで実行
- **Wi-Fi 詳細情報** — SSID、RSSI、SNR、チャンネル、PHYモード、セキュリティなどを表示。信号強度の推移グラフも
- **ICMP 診断ツール** — Ping / Ping6 / Traceroute を GUI から実行
- **DNS 診断** — 複数 DNS サーバーへのクエリ結果を一覧表示
- **タイムライン** — 接続状態とゲートウェイレイテンシーの時系列グラフ
- **通知** — インシデント発生時に macOS 通知を送信

## スクリーンショット
<img width="856" height="683" alt="image" src="https://github.com/user-attachments/assets/7fa3459c-25c3-4e8c-9f6e-3fd62ce013dc" />

<table>
  <tr>
    <td align="center">
      <img src="https://github.com/user-attachments/assets/6664aa9d-9c12-4f6d-9a6a-0609db231bf0" width="280" />
      <br /><b>ポップオーバー</b>
      <br />メニューバーから即座に状態確認
    </td>
    <td align="center">
      <img src="https://github.com/user-attachments/assets/7fa3459c-25c3-4e8c-9f6e-3fd62ce013dc" width="420" />
      <br /><b>ダッシュボード</b>
      <br />接続・プロトコル・DNS・サービスを一覧
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="https://github.com/user-attachments/assets/c1fe51be-0349-4af8-961e-671fae15d422" width="420" />
      <br /><b>Wi-Fi 詳細</b>
      <br />信号強度グラフ付きの詳細情報
    </td>
    <td align="center">
      <img src="https://github.com/user-attachments/assets/aa5c01dd-4e22-475f-8426-240f7e7622bc" width="420" />
      <br /><b>インシデント</b>
      <br />原因分析と対処手順を表示
    </td>
  </tr>
</table>

## 動作環境

- **macOS 14.0 (Sonoma)** 以上
- Apple Silicon / Intel Mac

## ビルド

### 必要なツール

- Xcode 16.0 以上
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（プロジェクトファイル生成時のみ）

### 手順

```bash
# リポジトリをクローン
git clone https://github.com/Tokine3/NetShisa.git
cd NetShisa

# Xcode プロジェクトを再生成する場合
xcodegen generate

# ビルド
xcodebuild -scheme NetShisa -configuration Release build

# アプリケーションフォルダにコピー
cp -R ~/Library/Developer/Xcode/DerivedData/NetShisa-*/Build/Products/Release/NetShisa.app /Applications/
```

または Xcode でプロジェクトを開いて `Cmd + R` で実行。

## アーキテクチャ

```
NetShisa/
├── App/                  # アプリケーションエントリーポイント・状態管理
│   ├── NetShisaApp.swift
│   ├── AppDelegate.swift        # SwiftData コンテナ初期化、監視開始
│   └── AppState.swift           # 全診断モジュールのオーケストレーション
├── Diagnostics/          # ネットワーク診断エンジン
│   ├── DualStackMonitor.swift   # IPv4/IPv6 疎通確認・接続方式検出
│   ├── WiFiProbe.swift          # Wi-Fi 情報取得 (CoreWLAN)
│   ├── ServiceProbe.swift       # 外部サービス到達性確認
│   ├── DNSProbe.swift           # DNS クエリ診断
│   ├── GatewayProbe.swift       # ゲートウェイ到達性・レイテンシー
│   ├── NetworkDetailProbe.swift # 詳細ネットワーク情報
│   ├── TracerouteEngine.swift   # Traceroute 実行・解析
│   └── IncidentDetector.swift   # インシデント分類・検出
├── Models/               # データモデル (SwiftData)
│   ├── ConnectivitySnapshot.swift
│   ├── ConnectivityState.swift
│   ├── Incident.swift
│   ├── DNSResult.swift
│   ├── ServiceDefinition.swift
│   ├── ServiceResult.swift
│   └── TracerouteResult.swift
├── MenuBar/              # メニューバー UI
│   ├── StatusBarController.swift
│   └── PopoverView.swift
├── Views/                # 詳細ウィンドウ UI
│   ├── DashboardView.swift
│   ├── WiFiView.swift
│   ├── ICMPView.swift
│   ├── DNSDetailView.swift
│   ├── NetworkDetailView.swift
│   ├── IncidentListView.swift
│   ├── TimelineView.swift
│   ├── SettingsView.swift
│   ├── DetailWindow.swift
│   └── Components/
├── Scheduling/           # 定期実行スケジューラー
│   └── ProbeScheduler.swift
├── Remediation/          # 自動修復エンジン
│   └── RemediationEngine.swift
└── Notifications/        # OS 通知
    └── NotificationManager.swift
```

## 使用フレームワーク

| フレームワーク | 用途 |
|---|---|
| SwiftUI | UI |
| SwiftData | データ永続化 |
| CoreWLAN | Wi-Fi 接続情報取得 |
| CoreLocation | Wi-Fi SSID 取得のための位置情報許可 |
| Network | ネットワーク接続監視 |
| SystemConfiguration | ゲートウェイ・ネットワーク設定取得 |
| Charts | タイムライングラフ |
| UserNotifications | インシデント通知 |
| ServiceManagement | ログイン時自動起動 |

## インシデント分類

NetShisa は以下のインシデントを自動検出・分類します：

| 分類 | 条件 |
|---|---|
| **Full Outage** | IPv4 / IPv6 ともに不通 |
| **Gateway Unreachable** | ゲートウェイに到達不可 |
| **IPv4 Down / IPv6 Up** | IPv4 のみ不通（MAP-E/DS-Lite 環境での典型的障害） |
| **IPv6 Down / IPv4 Up** | IPv6 のみ不通 |
| **DNS Failure** | DNS 解決の 50% 以上が失敗 |
| **Partial Outage** | 特定サービスのみ不通 |

各インシデントには、接続環境（v6プラス / DS-Lite / PPPoE）に応じた原因分析と対処手順が表示されます。

## 監視設定

| 項目 | デフォルト | 範囲 |
|---|---|---|
| 通常時の監視間隔 | 60 秒 | 10〜120 秒 |
| 障害時の監視間隔 | 30 秒 | 2〜30 秒 |

設定は詳細ウィンドウの「設定」タブから変更でき、即時に反映されます。

## 権限

- **位置情報** — macOS 14+ で Wi-Fi SSID を取得するために必要。初回起動時に許可ダイアログが表示されます。
- **ネットワーク** — 外部サービスへの疎通確認に使用。
- **サンドボックス無効** — `ipconfig`、`networksetup` 等のシステムコマンドを使用するため、App Sandbox は無効にしています。

## ライセンス

MIT
