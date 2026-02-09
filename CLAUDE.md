# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

Cowork Task Supervisor は、Claude Coworkに様々なタスクを自動実行させるMac用デスクトップアプリケーション。Mac上で人が行える作業をAIに委任し、業務効率と確実性を向上させることが目的。

## 技術スタック

- **UI**: Swift / SwiftUI
- **データ永続化**: SwiftData
- **Mac間同期**: iCloud (CloudKit)（フェーズ3）
- **Claude for Mac制御**: Accessibility API
- **プロジェクト生成**: XcodeGen（`project.yml`）

## ビルド・実行コマンド

```bash
# XcodeGen でプロジェクト生成
xcodegen generate

# ビルド
xcodebuild build -project CoworkTaskSupervisor.xcodeproj -scheme CoworkTaskSupervisor -configuration Debug -derivedDataPath build

# アクセシビリティ権限のTCCリセット（リビルド後に毎回必要）
tccutil reset Accessibility com.shimizu.CoworkTaskSupervisor

# 実行
open build/Build/Products/Debug/Cowork\ Task\ Supervisor.app
```

> **注意**: アドホック署名のDebugビルドでは、リビルドごとに署名が変わるため、macOSのTCC（Transparency, Consent, and Control）がアクセシビリティ権限を認識しなくなる。**ビルド→起動のたびに `tccutil reset` を実行すること**。アプリ再起動後に権限を再付与する。

## プロジェクト構造

```text
CoworkTaskSupervisor/
├── App/
│   ├── CoworkTaskSupervisorApp.swift   # @main、ModelContainer、Settings
│   ├── AppSettings.swift               # 設定キー定数（AppSettingsKey）
│   └── DeviceIdentifier.swift          # デバイスID管理（UserDefaults保存）
├── Models/
│   ├── CTask.swift                     # タスクモデル（@Model）
│   ├── AppLog.swift                    # ログモデル（@Model）
│   ├── TaskStatus.swift                # enum: pending/queued/running/completed/failed/cancelled
│   ├── RepeatRule.swift                # 繰り返しルール enum（daily/weekly/monthly/yearly/custom）+ RepeatUnit
│   ├── AutoExecutionMode.swift         # 自動実行モード enum（off/on/thisDeviceOnly）
│   └── LogLevel.swift                  # enum: info/warning/error
├── Views/
│   ├── ContentView.swift               # メインレイアウト（NavigationSplitView 3カラム）、ツールバー、自動実行ボタン
│   ├── TaskListView.swift              # タスク一覧（CRUD、並べ替え、カテゴリフィルタ）
│   ├── TaskDetailView.swift            # タスク詳細（インライン編集、スケジュール設定）
│   ├── LogListView.swift               # ログ一覧（レベルフィルタ）
│   ├── SettingsView.swift              # 設定画面（作業フォルダ選択）
│   └── FilterChip.swift               # 共通フィルターチップUI
├── Services/
│   ├── TaskManager.swift               # タスク実行オーケストレーション（キュー管理、キャンセル対応）
│   ├── SchedulerService.swift          # スケジュール実行（30秒間隔チェック、次回日時計算）
│   ├── ClaudeController.swift          # Claude for Mac制御（NSWorkspace + AX API）
│   ├── LogManager.swift                # SwiftData経由のログ記録
│   └── AccessibilityService.swift      # AX権限管理・ポーリング
├── Utilities/
│   └── AXExtensions.swift              # AXUIElement Swift拡張
└── Resources/
    ├── Info.plist
    ├── CoworkTaskSupervisor.entitlements
    └── Assets.xcassets/
```

## アーキテクチャ

- **View層** - SwiftUIによるタスクリスト・詳細画面・ログ画面
- **Task Manager** - タスク実行制御、キュー管理（`pendingQueue`）、キャンセル処理
- **Scheduler Service** - 30秒間隔でスケジュールチェック、到来タスクをTaskManagerへ投入、次回日時計算
- **SwiftData** - タスク・ログデータの永続化
- **Claude Controller** - Accessibility APIによるClaude for Macの起動・状態監視・プロンプト送信・応答取得

## 主要コンポーネント

### タスク管理

- リストビューでのタスク作成・整理（並べ替え、複製、削除）
- タスクはタイトル（任意）、プロンプトテキスト、メモ・備考（任意）、カテゴリ（任意）を持つ
- 実行結果（ステータスとClaudeの応答）を保存
- タスクキュー: 実行中に新タスクが追加された場合は `.queued` 状態でキューに入り、順次実行
- キャンセル: 応答完了後にキャンセル処理（`.cancelled` 状態へ遷移）

### スケジュール実行

- 日時指定でスケジュール設定（トグルON時の初期値: 次の09:00）
- 繰り返し: 毎日 / 毎週 / 毎月 / 毎年 / カスタム（任意間隔 × 時間/日/週/月/年）
- 自動実行モード: オフ / オン / このMacだけオン（ツールバーで切替）
- SchedulerServiceが30秒間隔でチェック→TaskManagerへ投入
- 月末日クランプ（31日指定→28日等）、閏年対応（2/29→2/28）

### Claude for Mac のコントロール

- Claude for Mac未起動時は起動する
- 起動時の処理:
  - バージョンをチェックし、新バージョンの場合はその旨記録
  - 実行環境を整える（ローカルフォルダ連携）
- ビジー/アイドル状態の判別（AXButton label「応答を停止」の有無）
  - アイドル状態なら、タスクキューを順次処理

## UI構成

### リストビュー (TaskListView)

- カテゴリフィルタ（チップ形式）
- タスク行: カテゴリ → タイトル → ステータス+アイコン行（bolt→clock→repeat→日時）
- アイコン配色: bolt blue(オン)/purple(このMac)、clock orange、repeat teal

### 詳細ビュー (TaskDetailView)

- ヘッダー（完了/失敗/キャンセル バッジ + 実行日時）
- 実行インジケータ（待機中.../実行中...）
- スケジュール（トグル + 日付 + 時刻 + 繰り返しピッカー、すべてインライン配置）
- 編集エリア（タイトル + カテゴリ + プロンプト + メモ）
- 結果表示（応答テキスト / エラー）

### ツールバー (ContentView.detailToolbar)

- 追加(+) / 複製 / 削除 + 自動実行モードボタン（オフ/オン/このMac）

## 注意事項

- モデル名は `CTask`（Swift Concurrency の `Task` との衝突を避けるため）
- App Sandbox無効（Accessibility APIに必要）
- `*.xcodeproj` は `.gitignore` に含まれる（XcodeGenで生成するため）
- Claude for MacのUI要素パスは `docs/ax-inspection.md` に記録
- アドホック署名のDebugビルドではリビルドごとにTCCのアクセシビリティ権限が無効になる。`tccutil reset Accessibility com.shimizu.CoworkTaskSupervisor` でリセット後、アプリ再起動→権限再付与が必要

## 開発フェーズ

- **フェーズ1（MVP）**: タスク作成 + 即時実行 ✓
- **フェーズ2**: スケジュール実行（日時指定・繰り返し・自動実行フラグ） ✓
- **フェーズ3**: iCloud同期、バージョン対応自動化

## 仕様詳細

`SPECIFICATION.md` に完全な仕様（データモデル、フェーズ別機能、未決定事項）を記載。
