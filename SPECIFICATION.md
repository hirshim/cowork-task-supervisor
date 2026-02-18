# Cowork Task Supervisor 仕様書

Hirokazu Shimizu

## 概要

### What

Claude Coworkにさまざまなタスクを自動実行させるMac用デスクトップアプリケーション。

### Why

- Mac上で人が行える作業は、AIにも行えるはずだ。
- Claude Coworkに、人の代わりにMacで作業してもらおう。
- 業務効率と確実性が、きっとバクアガリするだろう。

## 技術スタック

| 項目 | 選定 |
| --- | --- |
| UI フレームワーク | Swift / SwiftUI |
| データ永続化 | SwiftData |
| Mac間同期 | iCloud (CloudKit) |
| Claude for Mac 制御 | Accessibility API |
| 最小対応OS | macOS 15 Sequoia |

## 機能仕様

### フェーズ1（MVP） ✓

#### タスク管理

- リストビューでタスクを作成・整理する
  - 並べ替え（ドラッグ）
  - 削除・複製
  - カテゴリ分け・カテゴリフィルタ
- タスクはタイトル（任意）、プロンプトテキスト、メモ・備考（任意）を持つ
- タスクの実行結果を保存する
  - ステータス（pending / queued / running / completed / failed / cancelled）
  - Claude の応答テキスト
  - 失敗時のエラー内容

#### Claude for Mac のコントロール

- タスク実行時のみ Claude for Mac を制御する（タスクがなければ制御しない）
- タスク実行前に環境準備（`prepareEnvironment`）を行う:
  1. Claude for Macの起動確認・起動（未起動時）+ バージョンチェック
  2. 3タブ判定（Chat/Cowork/Code）→ Chat/Code なら Cmd+2 で Cowork に切替
  3. Cowork ビジー待機（「メッセージをキューに追加」ボタンが消えるまで5秒間隔でポーリング）
  4. 作業フォルダの設定（CGEventクリックでポップアップを開き、一致するフォルダを選択）
- タブ判定は各タブ固有のUI要素の存在で行う（AXRadioButton.selected は Electron で信頼できないため）
- ビジー/アイドル状態の判別:
  - 応答待機: AXButton label「応答を停止」の有無で判定
  - Coworkビジー: AXButton label「メッセージをキューに追加」の有無で判定
- タスクのプロンプトテキストをClaude for Macに送信し、応答を取得する
  - テキスト入力: クリップボード経由（Cmd+V）で入力（AXValue設定ではElectronのReact状態が更新されないため）
  - 送信: Returnキーで送信（送信ボタンのAXPressがElectronで機能しないため）
- タスクキューによる順次処理（実行中に新タスクが追加された場合はキューに入り、順次実行）
- 実行中のタスクのキャンセル（応答完了後にキャンセル処理）

#### Accessibility API 権限

- 初回起動時にAccessibility APIの権限をリクエストする
- 権限が未付与の場合、システム設定への誘導バナーを表示する
- 権限が拒否されている間はタスク実行機能を無効化する

#### アプリ内ログ

- バージョンチェック結果やタスク実行の経過をアプリ内ログとして記録する
- ログ閲覧画面を設ける（レベルフィルタ対応）

### フェーズ2（スケジュール実行） ✓

#### スケジュール実行

- 日時指定でタスクをスケジュール設定する
- SchedulerServiceが30秒間隔でスケジュールチェック→TaskManagerへ投入
- 繰り返し設定に対応:
  - 毎日（指定時刻）
  - 毎週（指定曜日・時刻）
  - 毎月（指定日・時刻、末日超過時はクランプ）
  - 毎年（指定月日・時刻、閏年非対応時はクランプ）
  - カスタム（任意間隔 × 単位: 時間/日/週/月/年）
- 自動実行モードでスケジュール実行を制御:
  - オフ（nil / .off）: スケジュール到来時に自動実行しない
  - オン（.on）: どのMacでも自動実行する
  - このMacだけオン（.thisDeviceOnly）: 設定したMacでのみ自動実行する

### フェーズ3

#### Mac間同期

- iCloud（CloudKit）を利用して複数Macデバイス間でタスク情報を同期する

#### バージョン対応の自動化

- Claude for Macの新バージョン検出時、UIコンポーネントをチェックする
- UIコンポーネントパス情報に変更があれば自動的に更新する

## データモデル

### CTask

| プロパティ | 型 | 説明 |
| --- | --- | --- |
| id | UUID | 一意識別子 |
| title | String? | タスクタイトル（任意） |
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
| scheduledAt | Date? | スケジュール実行日時 |
| repeatRule | RepeatRule? | 繰り返しルール |
| autoExecution | AutoExecutionMode? | 自動実行モード |

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

| 値 | ラベル | 色 | 説明 |
| --- | --- | --- | --- |
| pending | 未実行 | secondary | 未実行状態 |
| queued | 待機中 | blue | 実行キューで順番待ち |
| running | 実行中 | blue | Claude に送信中・応答待ち |
| completed | 完了 | green | 正常完了 |
| failed | 失敗 | red | 実行失敗 |
| cancelled | キャンセル | secondary | ユーザーによるキャンセル |

### RepeatRule

| ケース | パラメータ | 説明 |
| --- | --- | --- |
| daily | hour, minute | 毎日指定時刻に実行 |
| weekly | dayOfWeek, hour, minute | 毎週指定曜日・時刻に実行（1=日〜7=土） |
| monthly | day, hour, minute | 毎月指定日・時刻に実行（末日超過時はクランプ） |
| yearly | month, day, hour, minute | 毎年指定月日・時刻に実行（閏年非対応時はクランプ） |
| custom | interval, unit, hour, minute | カスタム間隔で実行 |

### RepeatUnit

| 値 | ラベル | Calendar.Component |
| --- | --- | --- |
| hours | 時間 | .hour |
| days | 日 | .day |
| weeks | 週 | .weekOfYear |
| months | 月 | .month |
| years | 年 | .year |

### AutoExecutionMode

| ケース | パラメータ | 説明 |
| --- | --- | --- |
| off | - | 自動実行しない |
| on | - | どのMacでも自動実行する |
| thisDeviceOnly | deviceId: String | 指定デバイスでのみ自動実行する |

## アーキテクチャ

```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
│  (タスクリスト、詳細/編集、ログ閲覧)       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│            Task Manager                 │
│   (タスク実行制御、キュー管理、キャンセル)   │
└───────┬───────────┬──────────┬──────────┘
        │           │          │
┌───────▼──────┐ ┌──▼────────┐ ┌▼───────────────┐
│  SwiftData   │ │ Claude    │ │ Scheduler      │
│  (永続化)    │ │ Controller│ │ Service        │
└──────────────┘ └───────────┘ └────────────────┘
```

### レイヤー構成

- **View層** - SwiftUIによるUI。NavigationSplitView 3カラム構成（サイドバー / タスクリスト or ログ / 詳細）
- **Task Manager** - タスクの実行制御、キュー管理、キャンセル処理を担当
- **Scheduler Service** - 30秒間隔でスケジュールチェックし、到来タスクをTaskManagerへ投入
- **SwiftData** - タスク・ログデータの永続化。フェーズ3でiCloud同期を有効化
- **Claude Controller** - Accessibility APIを通じたClaude for Macの起動・状態監視・プロンプト送信・応答取得

## UI構成

### リストビュー (TaskListView)

- カテゴリフィルタ（チップ形式、横スクロール）
- タスク行:
  - カテゴリ（上段、caption、secondary）
  - タイトル or プロンプト冒頭（中段）
  - ステータスラベル + アイコン行（下段）:
    - 自動実行アイコン（bolt: blue=オン, purple=このMac）
    - スケジュールアイコン（clock: orange）
    - 繰り返しアイコン（repeat: teal）
    - スケジュール日時テキスト（secondary）
  - 右端: 実行ボタン / 停止ボタン / プログレス

### 詳細ビュー (TaskDetailView)

- ヘッダー: ステータスバッジ（完了/失敗/キャンセル時） + 実行日時
- 実行インジケータ（待機中/実行中）
- スケジュール: トグル + 日付 + 時刻 + 繰り返しピッカー（インライン）
- 編集: タイトル + カテゴリ + プロンプト + メモ
- 結果: 応答テキスト / エラーメッセージ

### ツールバー (ContentView.detailToolbar)

- 追加(+) / 複製 / 削除 ボタン
- 自動実行モード切替ボタン（オフ/オン/このMac）

## 未決定事項

- [ ] タスク実行失敗時のリトライポリシー
- [ ] アプリのメニューバー常駐の有無
