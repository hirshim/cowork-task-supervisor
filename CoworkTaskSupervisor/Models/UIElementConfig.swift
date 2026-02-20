import ApplicationServices

struct ElementMarker: Codable, Sendable {
  var role: String;
  var attribute: ElementAttribute;
  var value: String;

  enum ElementAttribute: String, Codable, Sendable {
    case title
    case label
  }

  func find(in element: AXUIElement) -> AXUIElement? {
    switch attribute {
    case .title:
      return element.findFirst(role: role, title: value);
    case .label:
      return element.findFirst(role: role, label: value);
    }
  }
}

struct UIElementConfig: Codable, Sendable {
  // タブ判定マーカー（いずれか1つでも見つかればそのタブと判定）
  var coworkMarkers: [ElementMarker];
  var chatMarkers: [ElementMarker];
  var codeMarkers: [ElementMarker];

  // 操作用要素
  var stopButton: ElementMarker;
  var queueButton: ElementMarker;
  var workFolderPopup: ElementMarker;

  // UIクローム除去マーカー
  var uiChromeMarkers: [String];

  // 検証済みバージョン
  var verifiedVersion: String?;

  // MARK: - デフォルト設定（現在のハードコード値）

  static let `default` = UIElementConfig(
    coworkMarkers: [
      // A: セッションアクティビティパネル（Cowork処理中・処理後に存在）
      ElementMarker(role: kAXGroupRole, attribute: .label, value: "セッションアクティビティパネル"),
      // B: タスクを片付けましょう（Cowork初期状態に存在）
      ElementMarker(role: "AXHeading", attribute: .title, value: "タスクを片付けましょう"),
    ],
    chatMarkers: [],
    codeMarkers: [],
    stopButton: ElementMarker(role: kAXButtonRole, attribute: .label, value: "応答を停止"),
    queueButton: ElementMarker(role: kAXButtonRole, attribute: .label, value: "メッセージをキューに追加"),
    workFolderPopup: ElementMarker(role: kAXPopUpButtonRole, attribute: .title, value: "フォルダで作業"),
    uiChromeMarkers: [
      "\n返信...",
      "\n返信…",
      "\nReply to",
      "\nReply…",
      "\nClaude は AI のため",
      "\nClaude is an AI",
    ],
    verifiedVersion: nil
  );
}
