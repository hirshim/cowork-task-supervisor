# Claude for Mac Accessibility Inspector 調査結果

## 調査環境

- Claude for Mac バージョン:
- macOS バージョン:
- 調査日:

## 調査方法

1. Accessibility Inspector を起動（Xcode > Open Developer Tool > Accessibility Inspector）
2. ターゲットを Claude for Mac に設定
3. 各UI要素を Inspect して role / identifier / 階層を記録

## UI要素マップ

### テキスト入力フィールド（プロンプト送信先）

- **role**:
- **subrole**:
- **identifier**:
- **階層パス**: Window > ... >
- **備考**:

### 送信ボタン

- **role**:
- **subrole**:
- **identifier**:
- **階層パス**: Window > ... >
- **備考**:

### 応答表示エリア

- **role**:
- **subrole**:
- **identifier**:
- **階層パス**: Window > ... >
- **備考**: 応答テキストの取得方法（value / children の StaticText 等）

### ビジー/アイドル インジケーター

- **role**:
- **subrole**:
- **identifier**:
- **階層パス**: Window > ... >
- **判定方法**: （要素の有無 / value の変化 / etc.）
- **備考**:

### プロジェクト設定（作業フォルダ）

- **role**:
- **subrole**:
- **identifier**:
- **階層パス**: Window > ... >
- **操作手順**:
- **備考**:

## ウィンドウ全体の階層構造

```text
AXApplication "Claude"
└── AXWindow
    ├── ...
    └── ...
```

## ClaudeController への反映メモ

調査結果に基づいて更新が必要な箇所:

- `sendPrompt()` — テキスト入力フィールドの role / identifier
- `sendPrompt()` — 送信ボタンの role / identifier
- `waitForResponse()` — 応答テキスト取得の role / 取得方法
- `waitForResponse()` — アイドル判定ロジック
