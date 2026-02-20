# Cowork状態判定に必要なUIコンポーネント分析結果

## 1. 要素詳細表

| # | 要素名 | Role | Subrole | Role Description | Title | Description |
|---|---|---|---|---|---|---|
| A | セッションアクティビティパネル | AXGroup | AXLandmarkComplementary | グループ | *(なし)* | セッションアクティビティパネル |
| B | タスクを片付けましょう | AXHeading | *(なし)* | 見出し | タスクを片付けましょう | *(なし)* |
| C | 応答を停止 | AXButton | *(なし)* | ボタン | *(なし)* | 応答を停止 |

## 2. 9状態での存在マトリクス

| 状態 | A: セッションアクティビティパネル | B: タスクを片付けましょう | C: 応答を停止 |
|---|:---:|:---:|:---:|
| Chat 初期 | - | - | - |
| Chat 処理中 | - | - | ○ |
| Chat 処理後 | - | - | - |
| Cowork 初期 | - | ○ | - |
| Cowork 処理中 | ○ | - | ○ |
| Cowork 処理後 | ○ | - | - |
| Code 初期 | - | - | - |
| Code 処理中 | - | - | - |
| Code 処理後 | - | - | - |

## 3. 判定ロジック

```
if A or B:
    # Cowork確定
    if B:
        state = "Cowork 初期状態"
    elif C:
        state = "Cowork 処理中"
    else:
        state = "Cowork 処理後"
else:
    state = "Cowork以外（Chat or Code）"
```

**備考**: 要素Cの「応答を停止」はChat処理中にも出現するが、Cowork判定（A or B）の後に使用するため誤判定は発生しない。
