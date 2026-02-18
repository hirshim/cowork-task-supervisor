# Claude for Mac Accessibility Inspector 調査結果

## 調査環境

- Claude for Mac バージョン: 1.1.3363（頻繁にバージョンアップあり — 週5回レベル）
- macOS バージョン: 15.x
- 調査日: 2026-02-08（初回）、2026-02-09（Coworkタブ・フォルダポップアップ追記）、2026-02-18（3タブ判定・Cowork状態追加）
- アプリ基盤: Electron（BrowserAccessibilityCocoa / WebView ベース）

## 調査方法

1. Accessibility Inspector を起動（Xcode > Open Developer Tool > Accessibility Inspector）
2. ターゲットを Claude for Mac に設定
3. 各UI要素を Inspect して role / identifier / 階層を記録

## UI要素マップ

### テキスト入力フィールド（プロンプト送信先）

- **role**: AXTextArea
- **subrole**: なし
- **identifier**: None
- **label**: 「クロードにプロンプトを入力してください」
- **Automation Type**: Text View
- **DOM Identifier**: Empty string
- **DOM Class List**: 2 items
- **階層パス**: AXApplication > AXWindow > ... > AXGroup [BrowserAccessibilityCocoa] > AXTextArea
- **Children**: 1 item
- **備考**: identifier が None のため、role (AXTextArea) + label で特定する。Keyboard Focused = true で入力可能状態を確認可能。

### 送信ボタン（初期画面: 「始めましょう →」）

- **role**: AXButton
- **subrole**: None
- **identifier**: None
- **label**: 「タスクを開始」
- **Automation Type**: Button
- **DOM Class List**: 26 items
- **DOM Identifier**: Empty string
- **階層パス**: AXApplication > AXWindow [ElectronNSWindow] > ... > AXGroup > AXButton
- **Children**: 2 items（「始めましょう」テキスト + 矢印イメージ）
- **備考**: 初期画面（Coworkタブ）の送信ボタン。親要素は AXGroup。

### 送信ボタン（会話中: ⬆）

- **role**: AXButton（親 AXGroup の子要素）
- **subrole**: （要確認）
- **identifier**: None
- **label**: 「メッセージを送信」
- **階層パス**: AXApplication > AXWindow [ElectronNSWindow] > ... > AXGroup > AXButton
- **備考**: 会話開始後の送信ボタン。親は AXGroup（Role: AXGroup, Children: 1 item）。初期画面の「タスクを開始」ボタンとは別要素。処理中は停止ボタンに置き換わる（要調査）。

### 応答表示エリア（応答コンテナ）

- **role**: AXGroup
- **subrole**: None
- **identifier**: None
- **Automation Type**: Group
- **DOM Class List**: 5 items
- **Element Busy**: false（応答完了後）
- **Children**: 16 items（見出し、段落、コードブロック等の集合）
- **Frame**: x: 53.0 y: 300.0 width: 721.0 height: 1140.0
- **階層パス**: AXApplication > AXWindow [ElectronNSWindow] > ... > AXGroup（応答コンテナ）
- **子要素の構成**:
  - AXHeading — 見出し（title に見出しテキスト）
  - AXStaticText — 段落テキスト
  - AXGroup — コードブロック等
- **備考**: Value は Empty。テキスト取得には子要素を再帰的に走査し、AXHeading の title や AXStaticText の value を収集する必要あり。Element Busy が応答生成中に true になるか要確認（ビジー判定に使える可能性）。

### 停止ボタン（応答生成中のみ表示）

- **role**: AXButton
- **subrole**: None
- **identifier**: None
- **label**: 「応答を停止」
- **Automation Type**: Button
- **DOM Class List**: 24 items
- **Actions**: 押す, メニューを表示
- **Frame**: x: 658.0 y: 1361.0 width: 33.0 height: 32.0（送信ボタンと同じ位置）
- **階層パス**: AXApplication > AXWindow [ElectronNSWindow] > ... > AXGroup > AXButton
- **備考**: 応答生成中のみ表示。アイドル時は「メッセージを送信」ボタンに置き換わる。

### ビジー/アイドル判定

- **確定方針**: AXButton label「応答を停止」の有無で判定
  - **存在する** → ビジー（応答生成中）
  - **存在しない** → アイドル（「メッセージを送信」ボタンが表示）
- **実装**: `findFirst(role: kAXButtonRole)` で全ボタンを走査し、label が「応答を停止」のものを検索
- **Cowork タブでのビジー判定**: 「メッセージをキューに追加」ボタン（下記参照）

### キューに追加ボタン（Cowork 実行中のみ表示）

- **role**: AXButton
- **label**: 「メッセージをキューに追加」（AXDescription）
- **title**: なし
- **備考**: Cowork タブで何かを実行中の場合のみ表示。タスク実行前のビジー判定に使用。

### プロジェクト設定（作業フォルダ）

- **role**: AXPopUpButton
- **subrole**: None
- **identifier**: None
- **title**: 「フォルダで作業」
- **Automation Type**: PopUp Button
- **DOM Identifier**: radix-_r_5jl_（動的IDの可能性あり、信頼しない）
- **DOM Class List**: 36 items
- **Has Popup**: true
- **Expanded**: false
- **Actions**: 押す, メニューを表示
- **階層パス**: AXApplication > AXWindow [ElectronNSWindow] > ... > AXGroup > AXPopUpButton
- **操作手順**: Press アクションでポップアップを開き、フォルダを選択
- **備考**: title「フォルダで作業」で特定可能。DOM Identifier は radix 接頭辞のため動的生成の可能性が高い。
- **コールドスタート時の注意**: 起動直後やタブ切替直後は、title ではなく label（AXDescription）にテキストが格納される場合がある。検索時は title と label の両方にフォールバックすること。
- **選択済み時の title 変化**: フォルダ選択後は title が「フォルダで作業」からフォルダ名（例: 「Claude Cowork」）に変わる。

### タブ判定（3タブ構成）

Claude for Mac は Chat / Cowork / Code の3タブ構成。各タブにはタブ固有のUI要素がある。
`AXRadioButton.selected` は Electron で信頼できないため、**固有要素の存在**で現在のタブを判定する。

| タブ    | 固有要素                          | role           | 属性                  |
| ------- | --------------------------------- | -------------- | --------------------- |
| Chat    | 「文章作成」                      | AXRadioButton  | title                 |
| Chat    | 「サイドバーを開く」              | AXButton       | title                 |
| Cowork  | 「フォルダで作業」or フォルダ名   | AXPopUpButton  | title                 |
| Cowork  | 「メッセージをキューに追加」      | AXButton       | label (AXDescription) |
| Code    | 「許可を確認」                    | AXButton       | title                 |
| Code    | 「編集を自動承認」                | AXButton       | title                 |
| Code    | 「プランモード」                  | AXButton       | title                 |

- **切替**: Chat = Cmd+1、Cowork = Cmd+2、Code = Cmd+3
- **操作**: AXPress は Electron で効かないため、キーボードショートカット（postToPid経由）で切替
- **タブ切替後**: Electron が DOM を再構築するため、appElement の再取得が必要

### フォルダポップアップ内メニュー項目

- **role**: AXMenuItem
- **title**: フォルダ名（フルパス表示）
- **階層深度**: depth=13 程度（深いネスト）
- **操作**: CGEvent クリックで選択（AXPress は Electron で機能しない）
- **備考**: `AXStaticText.value` ではなく `AXMenuItem.title` にテキストが格納される

## Electron 固有の制約

- **AXPress アクション**: ボタン・ポップアップ等で効かない → CGEvent クリック or キーボードショートカットを使用
- **AXRadioButton.selected**: 値が信頼できない → コンテンツの存在で判定
- **AXValue 設定**: テキストフィールドに AXValue を直接設定しても React 状態が更新されない → クリップボード経由（Cmd+V）で入力
- **コールドスタート時の AX ツリー遅延**: 起動直後やタブ切替直後は AX ツリーの構築が遅延し、要素が見つからない場合がある → activateClaude() + リトライで対応

## ウィンドウ全体の階層構造

```text
AXApplication "Claude"
└── AXWindow
    ├── ...
    └── ...
```

## ClaudeController への反映状況

調査結果は以下の箇所に反映済み:

- `prepareEnvironment()` — 環境準備の全体フロー（起動→タブ判定→ビジー待機→フォルダ設定）
- `detectCurrentTab()` — 3タブ（Chat/Cowork/Code）の固有要素で現在のタブを判定
- `ensureCoworkTab()` — detectCurrentTab() で判定、Chat/Code なら Cmd+2 で切替、unknown はリトライ（最大3回）
- `waitUntilCoworkIdle()` — 「メッセージをキューに追加」ボタンでビジー判定、5秒間隔ポーリング
- `ensureWorkFolder()` — AXPopUpButton を title/label で検索（リトライ最大3回）、CGEvent クリックで操作
- `findWorkFolderPopup()` — title と label（AXDescription）の両方にフォールバック検索
- `sendPrompt()` — AXTextArea でテキスト入力フィールドを特定、Cmd+V でペースト、Return で送信
- `waitForResponse()` — AXGroup を走査し、子要素の AXStaticText / AXHeading からテキスト収集
- `isIdle()` — AXButton label「応答を停止」の有無で判定（sendPrompt 内の応答待機用）
