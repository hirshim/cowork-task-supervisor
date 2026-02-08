# Claude for Mac Accessibility Inspector 調査結果

## 調査環境

- Claude for Mac バージョン: （要確認）
- macOS バージョン: 15.x
- 調査日: 2026-02-08
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

## ウィンドウ全体の階層構造

```text
AXApplication "Claude"
└── AXWindow
    ├── ...
    └── ...
```

## ClaudeController への反映状況

調査結果は以下の箇所に反映済み:

- `sendPrompt()` — AXTextArea (role) でテキスト入力フィールドを特定
- `sendPrompt()` — AXButton + label（「メッセージを送信」/「タスクを開始」）で送信ボタンを特定
- `waitForResponse()` — AXGroup を走査し、子要素の AXStaticText / AXHeading からテキスト収集
- `isIdle()` — AXButton label「応答を停止」の有無で判定
