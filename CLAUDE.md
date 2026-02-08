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

# 実行
open build/Build/Products/Debug/Cowork\ Task\ Supervisor.app

# アクセシビリティ権限のTCCリセット（リビルド後に権限が認識されない場合）
tccutil reset Accessibility com.shimizu.CoworkTaskSupervisor
```

> **注意**: アドホック署名のDebugビルドでは、リビルドごとに署名が変わるため、macOSのTCC（Transparency, Consent, and Control）がアクセシビリティ権限を認識しなくなることがある。その場合は `tccutil reset` で権限をリセットし、アプリ再起動後に再付与する。

## プロジェクト構造

```text
CoworkTaskSupervisor/
├── App/
│   ├── CoworkTaskSupervisorApp.swift   # @main、ModelContainer、Settings
│   └── AppSettings.swift               # 設定キー定数（AppSettingsKey）
├── Models/
│   ├── CTask.swift                     # タスクモデル（@Model）
│   ├── AppLog.swift                    # ログモデル（@Model）
│   ├── TaskStatus.swift                # enum: pending/running/completed/failed
│   └── LogLevel.swift                  # enum: info/warning/error
├── Views/
│   ├── ContentView.swift               # メインレイアウト（NavigationSplitView）
│   ├── TaskListView.swift              # タスク一覧（CRUD、並べ替え、カテゴリフィルタ）
│   ├── TaskDetailView.swift            # タスク詳細（実行ボタン含む）
│   ├── TaskFormView.swift              # タスク作成/編集シート
│   ├── LogListView.swift               # ログ一覧（レベルフィルタ）
│   ├── SettingsView.swift              # 設定画面（作業フォルダ選択）
│   └── FilterChip.swift               # 共通フィルターチップUI
├── Services/
│   ├── TaskManager.swift               # タスク実行オーケストレーション
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

- **View層** - SwiftUIによるタスクリスト・詳細画面
- **Task Manager** - タスクCRUD、キュー管理、実行制御
- **SwiftData** - タスクデータの永続化
- **Claude Controller** - Accessibility APIによるClaude for Macの起動・状態監視・プロンプト送信・応答取得

## 主要コンポーネント

### タスク管理

- リストビューでのタスク作成・整理
- タスクはプロンプトテキストを持つ
- 実行結果（ステータスとClaudeの応答）を保存
- ほかのMacとのタスク情報の同期（フェーズ3）
- 繰り返しを含む実行時間設定で、タスクをタスクキューに入れる（フェーズ2）

### Claude for Mac のコントロール

- Claude for Mac未起動時は起動する
- 起動時の処理:
  - バージョンをチェックし、新バージョンの場合はその旨記録
    - 将来的にはUIコンポーネントをチェックし、パス情報変更の必要があれば変更する
  - 実行環境を整える（ローカルフォルダ連携）
- ビジー/アイドル状態の判別
  - アイドル状態なら、タスクキューを順次処理

## 注意事項

- モデル名は `CTask`（Swift Concurrency の `Task` との衝突を避けるため）
- App Sandbox無効（Accessibility APIに必要）
- `*.xcodeproj` は `.gitignore` に含まれる（XcodeGenで生成するため）
- Claude for MacのUI要素パスは `docs/ax-inspection.md` に記録
- アドホック署名のDebugビルドではリビルドごとにTCCのアクセシビリティ権限が無効になる。`tccutil reset Accessibility com.shimizu.CoworkTaskSupervisor` でリセット後、アプリ再起動→権限再付与が必要

## 開発フェーズ

- **フェーズ1（MVP）**: タスク作成 + 即時実行
- **フェーズ2**: スケジュール実行（日時指定・繰り返し）
- **フェーズ3**: iCloud同期、バージョン対応自動化

## 仕様詳細

`SPECIFICATION.md` に完全な仕様（データモデル、フェーズ別機能、未決定事項）を記載。
