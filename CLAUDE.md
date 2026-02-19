# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

Cowork Task Supervisor は、Claude Coworkに様々なタスクを自動実行させるMac用デスクトップアプリケーション。Mac上で人が行える作業をAIに委任し、業務効率と確実性を向上させることが目的。

## 技術スタック

- **UI**: Swift / SwiftUI
- **データ永続化**: SwiftData
- **Mac間同期**: iCloud (CloudKit)
- **Claude for Mac制御**: Accessibility API
- **プロジェクト生成**: XcodeGen（`project.yml`）

## ビルド・実行コマンド

```bash
# XcodeGen でプロジェクト生成
xcodegen generate

# ビルド
xcodebuild build -project CoworkTaskSupervisor.xcodeproj -scheme CoworkTaskSupervisor -configuration Debug -derivedDataPath build

# 実行
open build/Build/Products/Debug/Cowork\ Task\ Supervisor.app
```

> **署名とTCC権限**: Developer ID署名（`project.yml` の `CODE_SIGN_IDENTITY: "Developer ID Application"`）を使用しているため、リビルドしてもTCC権限は維持される。`tccutil reset` は不要（むしろ既存プロセスへのAXアクセスが無効化されて問題が起きる）。アドホック署名に変更した場合のみ、リビルドごとに `tccutil reset Accessibility com.shimizu.CoworkTaskSupervisor` が必要。

## プロジェクト構造

```text
CoworkTaskSupervisor/
├── App/
│   ├── CoworkTaskSupervisorApp.swift   # @main、ModelContainer（CloudStore/LocalStore分離）、レガシー移行
│   ├── AppSettings.swift               # 設定キー定数（AppSettingsKey）
│   └── DeviceIdentifier.swift          # デバイスID管理（UserDefaults保存）
├── Models/
│   ├── CTask.swift                     # タスクモデル（@Model、CloudKit同期対象）
│   ├── AppLog.swift                    # ログモデル（@Model、ローカルのみ）
│   ├── UIElementConfig.swift           # UI要素設定構造体（ElementMarker + UIElementConfig）
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
│   ├── UIElementConfigManager.swift    # UI要素設定の管理・バージョン検証・自動検出
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
- **SwiftData** - タスク・ログデータの永続化。CTask は CloudKit 同期（CloudStore）、AppLog はローカルのみ（LocalStore）
- **Claude Controller** - Accessibility APIによるClaude for Macの起動・状態監視・プロンプト送信・応答取得
- **UIElementConfigManager** - UI要素ラベルの設定管理。新バージョン検出時にAXツリーを検証し、不一致要素を自動検出

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

### Claude for Mac のコントロール（ClaudeController）

- タスク実行時のみ `sendPrompt()` → `prepareEnvironment()` で環境を自動準備（タスクがなければ Claude を制御しない）:
  1. Claude for Macの起動確認・起動 + バージョンチェック + UI要素検証（`verifyAndUpdate()`）
  2. 3タブ判定（Chat/Cowork/Code）→ Chat/Code なら Cmd+2 で Cowork に切替
  3. Cowork ビジー待機（キューボタンが消えるまでポーリング）
  4. 作業フォルダの設定（CGEventクリックでポップアップ操作）
- タブ判定: `UIElementConfig` のマーカー配列で判定（`detectCurrentTab()`）
  - 各タブのマーカー（chatMarkers / coworkMarkers / codeMarkers）のいずれかが見つかればそのタブ
  - UI要素のラベルが変更された場合は `UIElementConfigManager` で自動検出・更新
- プロンプト送信: クリップボード経由（Cmd+V）で入力、Returnキーで送信
- ビジー/アイドル状態の判別:
  - 応答待機: AXButton label「応答を停止」の有無で判定
  - Coworkビジー: AXButton label「メッセージをキューに追加」の有無で判定
- Electron固有の制約:
  - AXPressアクションが効かない → CGEventクリック or キーボードショートカットを使用
  - AXRadioButton.selectedが信頼できない → 固有要素の存在で判定
  - AX属性の格納先が要素ごとに異なる → Inspectorで必ず確認（title/label）
  - コールドスタート時にAXツリーの構築が遅延 → activateClaude() + appElement再取得でリトライ（最大3回）

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
- Developer ID署名ではリビルドしてもTCC権限は維持される（`tccutil reset` 不要）
- iCloud 同期には Developer ID プロビジョニングプロファイル（`PROVISIONING_PROFILE_SPECIFIER`）が必要

## 開発フェーズ

- **フェーズ1（MVP）**: タスク作成 + 即時実行 ✓
- **フェーズ2**: スケジュール実行（日時指定・繰り返し・自動実行フラグ） ✓
- **フェーズ3**: iCloud同期 ✓、バージョン対応自動化 ✓

## 仕様詳細

`SPECIFICATION.md` に完全な仕様（データモデル、フェーズ別機能、未決定事項）を記載。
