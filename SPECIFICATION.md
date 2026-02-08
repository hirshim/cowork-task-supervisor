# Cowork Task Supervisor 仕様書

Hirokazu Shimizu

## 概要

### What

Claude Coworkに様々なタスクを自動実行させるMac用デスクトップアプリケーション。

### Why

- Mac上で人が行える作業は、AIでも行えるはずだ。
- Claude Coworkに、人の代わりにMacで作業してもらい、業務の効率改善、確実性を向上させる。

## 技術スタック

| 項目 | 選定 |
| --- | --- |
| UI フレームワーク | Swift / SwiftUI |
| データ永続化 | SwiftData |
| Mac間同期 | iCloud (CloudKit) |
| Claude for Mac 制御 | Accessibility API |
| 最小対応OS | macOS 15 Sequoia |

## 機能仕様

### フェーズ1（MVP）

#### タスク管理

- リストビューでタスクを作成・整理する
  - 並べ替え（ドラッグ）
  - 削除
  - カテゴリ分け
- タスクはプロンプトテキストとメモ・備考（任意）を持つ
- タスクの実行結果を保存する
  - ステータス（pending / running / completed / failed）
  - Claude の応答テキスト
  - 失敗時のエラー内容

#### Claude for Mac のコントロール

- Claude for Mac未起動時は起動する
- 起動時の処理:
  - バージョンをチェックし、新バージョンの場合はその旨をアプリ内ログに記録
  - 実行環境を整える
    - Claude for Macのプロジェクト機能で作業フォルダを設定する（アプリ全体で一つの設定）
- ビジー/アイドル状態の判別（方法は調査・検証して決定する）
  - アイドル状態なら、タスクを即時実行する
- タスクのプロンプトテキストをClaude for Macに送信し、応答を取得する

#### Accessibility API 権限

- 初回起動時にAccessibility APIの権限をリクエストする
- 権限が未付与の場合、システム設定への誘導メッセージを表示する
- 権限が拒否されている間はタスク実行機能を無効化する

#### アプリ内ログ

- バージョンチェック結果やタスク実行の経過をアプリ内ログとして記録する
- ログ閲覧画面を設ける

### フェーズ2

#### スケジュール実行

- 日時指定でタスクをタスクキューに入れる
- 繰り返し設定（毎日○時、毎週○曜日など）に対応する
- タスクキューの管理と順次処理

### フェーズ3

#### Mac間同期

- iCloud（CloudKit）を利用して複数Macデバイス間でタスク情報を同期する

#### バージョン対応の自動化

- Claude for Macの新バージョン検出時、UIコンポーネントをチェックする
- UIコンポーネントパス情報に変更があれば自動的に更新する

## データモデル

### Task

| プロパティ | 型 | 説明 |
| --- | --- | --- |
| id | UUID | 一意識別子 |
| prompt | String | Claude に送信するプロンプトテキスト |
| comment | String? | メモ・備考 |
| status | TaskStatus | 実行状態 |
| category | String? | カテゴリ名（自由入力テキスト） |
| order | Int | リスト内の表示順 |
| response | String? | Claude の応答テキスト |
| errorMessage | String? | 失敗時のエラー内容 |
| createdAt | Date | 作成日時 |
| updatedAt | Date | 更新日時 |
| executedAt | Date? | 最終実行日時 |

> **フェーズ2で追加予定**: scheduledAt（実行予定日時）、repeatRule（繰り返しルール）

### AppLog

| プロパティ | 型 | 説明 |
| --- | --- | --- |
| id | UUID | 一意識別子 |
| taskId | UUID? | 関連するタスクのID（タスクに紐付かないログはnil） |
| message | String | ログメッセージ |
| level | LogLevel | ログレベル（info / warning / error） |
| createdAt | Date | 記録日時 |

### LogLevel

| 値 | 説明 |
| --- | --- |
| info | 通常の情報（バージョンチェック結果、タスク実行開始/完了など） |
| warning | 注意が必要な状態（権限未付与、Claude for Mac未応答など） |
| error | エラー（タスク実行失敗、起動失敗など） |

### TaskStatus

| 値 | 説明 |
| --- | --- |
| pending | 未実行 |
| running | 実行中 |
| completed | 正常完了 |
| failed | 実行失敗 |

> **フェーズ2で追加予定**: cancelled（ユーザーによるキャンセル）

## アーキテクチャ

```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
│  (タスクリスト、詳細/編集、ログ閲覧)       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│            Task Manager                 │
│       (タスクCRUD、実行制御)              │
└───────┬────────────────────┬────────────┘
        │                    │
┌───────▼──────┐  ┌──────────▼────────────┐
│  SwiftData   │  │  Claude Controller    │
│  (永続化)    │  │  (Accessibility API)  │
└──────────────┘  └───────────────────────┘
```

### レイヤー構成

- **View層** - SwiftUIによるUI。タスクリストビュー、タスク詳細/編集画面、ログ閲覧画面
- **Task Manager** - タスクのCRUD操作、実行の制御を担当。フェーズ2でキュー管理を追加
- **SwiftData** - タスクデータの永続化。フェーズ3でiCloud同期を有効化
- **Claude Controller** - Accessibility APIを通じたClaude for Macの起動・状態監視・プロンプト送信・応答取得

## 未決定事項

- [ ] Claude for Macのビジー/アイドル判定方法（Accessibility APIで何を監視するか調査が必要）
- [ ] Accessibility APIによるClaude の応答テキストの読み取り方法
- [ ] タスク実行失敗時のリトライポリシー
- [ ] アプリのメニューバー常駐の有無
