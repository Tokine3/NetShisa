# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

NetShisa — macOS メニューバー常駐型のネットワーク診断・監視ユーティリティ。IPv4/IPv6デュアルスタック監視、障害検知、自動修復を提供する。UIは全て日本語。

## ビルド・実行

```bash
# プロジェクトファイル生成（project.ymlを変更した場合）
xcodegen generate

# デバッグビルド
xcodebuild -project NetShisa.xcodeproj -scheme NetShisa -configuration Debug build

# リリースビルド
xcodebuild -project NetShisa.xcodeproj -scheme NetShisa -configuration Release build

# ビルド成果物の場所
# ~/Library/Developer/Xcode/DerivedData/NetShisa-*/Build/Products/{Debug,Release}/NetShisa.app
```

テストターゲットは未構成。外部SPM依存なし（Apple純正フレームワークのみ）。

## 環境要件

- macOS 14.0 (Sonoma) 以降
- Xcode 16.0+, Swift 5.10
- XcodeGen 2.38+（project.yml変更時のみ）
- App Sandbox無効（`/sbin/ping`等のシステムコマンド実行に必要）
- `LSUIElement: true`（Dockに表示されないメニューバーアプリ）

## アーキテクチャ

**状態管理の中心は`AppState`（@MainActor）。** 全診断モジュールを所有し、@Publishedプロパティで全Viewに状態を配信する。

### 起動フロー

`NetShisaApp` → `AppDelegate`（SwiftData ModelContainer生成）→ `AppState`生成 → `StatusBarController`生成 → `appState.startMonitoring()`

### モジュール構成

- **App/** — エントリポイント、AppDelegate（SwiftData設定）、AppState（全体のオーケストレーション）
- **Diagnostics/** — 各種診断エンジン（DualStackMonitor, WiFiProbe, ServiceProbe, DNSProbe, GatewayProbe, NetworkDetailProbe, TracerouteEngine, IncidentDetector）。全て`async/await`で動作
- **Models/** — SwiftData永続化モデル（ConnectivitySnapshot, Incident, ServiceResult, DNSResult, TracerouteResult）+ 非永続構造体（ServiceDefinition等）
- **MenuBar/** — StatusBarController（NSStatusBar管理、アイコン色変更）+ PopoverView（360x480のクイックビュー）
- **Views/** — DetailWindow（8タブのNavigationSplitView）+ 各タブView + Components/
- **Scheduling/** — ProbeScheduler（通常60秒/障害時30秒のタイマー制御）
- **Remediation/** — RemediationEngine（DNSキャッシュフラッシュ、DHCP更新、IPv6リセット、Wi-Fiリセット）
- **Notifications/** — UNUserNotificationCenter統合

### データフロー

`ProbeScheduler`（タイマー）→ `AppState.executeProbes()`（各Diagnosticsを並列実行）→ `IncidentDetector.evaluate()`（障害分類）→ SwiftDataに保存 + @Published更新 → View自動更新 + StatusBarアイコン色変更

### 障害分類（IncidentDetector）

Full Outage / Gateway Unreachable / IPv4 Down・IPv6 Up / IPv6 Down・IPv4 Up / DNS Failure / Partial Outage の6種。分類結果に応じてRemediationEngineが修復手順を実行。

### SwiftDataの保持期間

- ConnectivitySnapshot: 7日
- Incident: 90日
- クリーンアップは1日1回自動実行

## 重要な設計判断

- **サンドボックス無効**: `/sbin/ping`, `/usr/sbin/ipconfig`, `/usr/bin/dscacheutil`, `/usr/bin/networksetup`等のシステムコマンドを`Process`で直接実行するため
- **接続方式検出**: IPv6到達可能+WAN IPv6アドレスあり+IPv4到達可能 → IPoE(DS-Lite/MAP-E)、IPv4のみ → PPPoE
- **グローバルIP取得**: `api.ipify.org`/`api64.ipify.org`を使用、同時リクエストの重複排除あり
- **CoreLocation権限**: macOS 14+でWi-Fi SSID取得に必要
- **@unchecked Sendable**: 診断モジュールは内部でDispatchQueueを使うため手動でSendable準拠
