# Cowork Task Supervisor

Claude Cowork に様々なタスクを自動実行させる macOS デスクトップアプリケーション。

Mac 上で人が行える作業を AI に委任し、業務効率と確実性を向上させます。

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue)
![SwiftData](https://img.shields.io/badge/SwiftData-green)

## 特徴

- **タスク管理** — プロンプトベースのタスクを作成・整理・カテゴリ分け
- **Claude for Mac 自動制御** — Accessibility API で Claude for Mac の起動・タブ切替・フォルダ設定・プロンプト送信・応答取得を自動化
- **スケジュール実行** — 日時指定・繰り返し（毎日/毎週/毎月/毎年/カスタム）でタスクを自動実行
- **タスクキュー** — 複数タスクを順次処理、実行中のキャンセルに対応
- **自動実行モード** — オフ / オン / このMacだけオン の3段階制御
- **Liquid Glass アイコン** — ライトモード・ダークモード両対応

## スクリーンショット

<!-- TODO: スクリーンショットを追加 -->

## 必要環境

- macOS 15 Sequoia 以降
- Claude for Mac（インストール済み）
- アクセシビリティ権限（初回起動時に付与）

## インストール・ビルド

[XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要です。

```bash
# XcodeGen をインストール（未導入の場合）
brew install xcodegen

# プロジェクト生成
xcodegen generate

# ビルド
xcodebuild build \
  -project CoworkTaskSupervisor.xcodeproj \
  -scheme CoworkTaskSupervisor \
  -configuration Debug \
  -derivedDataPath build

# 実行
open build/Build/Products/Debug/Cowork\ Task\ Supervisor.app
```

> **Note:** Developer ID 署名を使用しているため、リビルドしても TCC のアクセシビリティ権限は維持されます。初回起動時のみシステム設定で権限を付与してください。

## 技術スタック

| 項目 | 選定 |
|---|---|
| UI | Swift / SwiftUI |
| データ永続化 | SwiftData |
| Claude for Mac 制御 | Accessibility API |
| プロジェクト生成 | XcodeGen |
| 最小対応 OS | macOS 15 Sequoia |

## アーキテクチャ

```
SwiftUI Views（タスクリスト・詳細・ログ）
        │
    Task Manager（実行制御・キュー管理）
     ┌──┼──────────┐
SwiftData  Claude     Scheduler
(永続化)   Controller  Service
           (AX API)   (30秒間隔)
```

## 開発ロードマップ

- [x] **フェーズ 1（MVP）** — タスク作成 + 即時実行
- [x] **フェーズ 2** — スケジュール実行（日時指定・繰り返し・自動実行）
- [ ] **フェーズ 3** — iCloud 同期、バージョン対応自動化

## ライセンス

MIT License

## Author

Hirokazu Shimizu
