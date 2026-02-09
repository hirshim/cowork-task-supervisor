import AppKit
import ApplicationServices

@MainActor
final class ClaudeController {
  static let BUNDLE_IDENTIFIER = "com.anthropic.claudefordesktop";

  private let logManager: LogManager;
  private let accessibilityService: AccessibilityService;
  private var hasLoggedVersion = false;
  private var lastPreparedAt: Date?;
  private static let PREPARE_CACHE_DURATION: TimeInterval = 300;

  init(logManager: LogManager, accessibilityService: AccessibilityService) {
    self.logManager = logManager;
    self.accessibilityService = accessibilityService;
    observeClaudeTermination();
  }

  private func observeClaudeTermination() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.bundleIdentifier == Self.BUNDLE_IDENTIFIER else { return };
      Task { @MainActor [weak self] in
        self?.lastPreparedAt = nil;
        self?.logManager.warning("Claude for Macが終了しました。次回タスク実行時に再起動します。");
      }
    };
  }

  // MARK: - 基本制御

  var isClaudeRunning: Bool {
    NSWorkspace.shared.runningApplications.contains {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    };
  }

  func launchClaude() async throws {
    if isClaudeRunning {
      logManager.info("Claude for Macは既に起動中です");
      return;
    }

    guard let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: Self.BUNDLE_IDENTIFIER
    ) else {
      let message = "Claude for Macが見つかりません。インストールされているか確認してください。";
      logManager.error(message);
      throw ClaudeControllerError.appNotFound;
    };

    let configuration = NSWorkspace.OpenConfiguration();
    try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration);
    logManager.info("Claude for Macを起動しました");
  }

  func getClaudeVersion() -> String? {
    guard let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: Self.BUNDLE_IDENTIFIER
    ) else { return nil };

    let bundle = Bundle(url: appURL);
    let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String;
    if let version {
      logManager.info("Claude for Mac バージョン: \(version)");
    }
    return version;
  }

  // MARK: - Accessibility制御
  // UI要素情報は docs/ax-inspection.md に基づく

  private static let LABEL_STOP_BUTTON = "応答を停止";
  private static let LABEL_SEND_BUTTON_INITIAL = "タスクを開始";
  private static let LABEL_SEND_BUTTON_CONVERSATION = "メッセージを送信";
  private static let POLLING_INTERVAL: Duration = .milliseconds(500);
  private static let DEFAULT_RESPONSE_TIMEOUT_SECONDS = 300;

  private var responseTimeout: Duration {
    let seconds = UserDefaults.standard.integer(forKey: AppSettingsKey.RESPONSE_TIMEOUT_SECONDS);
    return .seconds(seconds > 0 ? seconds : Self.DEFAULT_RESPONSE_TIMEOUT_SECONDS);
  }

  private static let LABEL_COWORK_TAB = "Cowork";
  private static let TITLE_WORK_FOLDER_POPUP = "フォルダで作業";

  // macOS 仮想キーコード
  private static let VIRTUAL_KEY_2: UInt16 = 0x13;
  private static let VIRTUAL_KEY_V: UInt16 = 0x09;
  private static let VIRTUAL_KEY_RETURN: UInt16 = 0x24;
  private static let VIRTUAL_KEY_ESCAPE: UInt16 = 0x35;

  func isIdle(appElement: AXUIElement) -> Bool {
    appElement.findFirst(role: kAXButtonRole, label: Self.LABEL_STOP_BUTTON) == nil;
  }

  // MARK: - 環境準備

  @discardableResult
  func prepareEnvironment(force: Bool = false) async throws -> AXUIElement {
    if !force, let lastPreparedAt,
       Date().timeIntervalSince(lastPreparedAt) < Self.PREPARE_CACHE_DURATION,
       isClaudeRunning {
      guard let appElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) else {
        throw ClaudeControllerError.elementNotFound("application");
      };
      logManager.info("環境準備済み（キャッシュ）");
      return appElement;
    }

    guard accessibilityService.isAccessibilityGranted else {
      logManager.error("アクセシビリティ権限が付与されていません");
      throw ClaudeControllerError.accessibilityNotGranted;
    };

    let appElement = try await ensureClaudeLaunched();
    await ensureCoworkTab(appElement: appElement);
    await ensureWorkFolder(appElement: appElement);

    lastPreparedAt = Date();
    logManager.info("環境準備が完了しました");
    return appElement;
  }

  private func ensureClaudeLaunched() async throws -> AXUIElement {
    if !isClaudeRunning {
      try await launchClaude();
      try await Task.sleep(for: .seconds(3));
    }

    // フォアグラウンドにしてAXツリーへのアクセスを確保（起動直後・既存プロセス両方）
    activateClaude();
    try await Task.sleep(for: .seconds(2));

    if !hasLoggedVersion {
      _ = getClaudeVersion();
      hasLoggedVersion = true;
    }

    guard let appElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) else {
      logManager.error("Claude for MacのAX要素を取得できません");
      throw ClaudeControllerError.elementNotFound("application");
    };
    return appElement;
  }

  private static let TAB_SEARCH_MAX_RETRIES = 15;
  private static let TAB_SEARCH_INTERVAL: Duration = .seconds(1);

  private func ensureCoworkTab(appElement: AXUIElement) async {
    // Coworkタブ固有のUI要素（フォルダポップアップ）が存在すれば切替不要
    // ※ Electron の AXRadioButton.selected 属性は信頼できないため、コンテンツで判定
    if findWorkFolderPopup(in: appElement) != nil {
      logManager.info("Coworkタブは選択済みです");
      return;
    }

    // 起動直後はAXツリーが未完成の場合があるためリトライ検索
    // ポップアップとタブ要素の両方を毎回チェック
    for attempt in 1...Self.TAB_SEARCH_MAX_RETRIES {
      // ポップアップが見つかればCoworkタブ上にいる（AXツリーのロード遅延対策）
      if findWorkFolderPopup(in: appElement) != nil {
        logManager.info("Coworkタブは選択済みです");
        return;
      }
      // タブ要素が見つかればUIはロード済み → 別タブにいる
      let tab = appElement.findFirst(role: kAXRadioButtonRole, label: Self.LABEL_COWORK_TAB)
              ?? appElement.findFirst(role: kAXRadioButtonRole, title: Self.LABEL_COWORK_TAB);
      if tab != nil { break };
      logManager.info("Coworkタブを検索中... (\(attempt)/\(Self.TAB_SEARCH_MAX_RETRIES))");
      try? await Task.sleep(for: Self.TAB_SEARCH_INTERVAL);
    }

    // キーボードショートカット Cmd+2 でCoworkタブ（2番目のタブ）に切替
    logManager.info("Coworkタブに切り替えます");
    activateClaude();
    try? await Task.sleep(for: .milliseconds(500));
    sendKeyboardShortcut(keyCode: Self.VIRTUAL_KEY_2, modifiers: .maskCommand);
    try? await Task.sleep(for: .seconds(1));
    logManager.info("Coworkタブ切り替えコマンドを送信しました");
  }

  /// フォルダポップアップを検索（未設定時の「フォルダで作業」と設定済みフォルダ名の両方に対応）
  private func findWorkFolderPopup(in appElement: AXUIElement) -> AXUIElement? {
    // 未設定時: title = "フォルダで作業"
    if let popup = appElement.findFirst(role: kAXPopUpButtonRole, title: Self.TITLE_WORK_FOLDER_POPUP) {
      return popup;
    }
    // 設定済み時: title がフォルダ名に変わる
    let workFolderPath = UserDefaults.standard.string(forKey: AppSettingsKey.WORK_FOLDER_PATH) ?? "";
    if !workFolderPath.isEmpty {
      let folderName = URL(fileURLWithPath: workFolderPath).lastPathComponent;
      if let popup = appElement.findFirst(role: kAXPopUpButtonRole, title: folderName) {
        return popup;
      }
    }
    return nil;
  }

  private func ensureWorkFolder(appElement: AXUIElement) async {
    let workFolderPath = UserDefaults.standard.string(forKey: AppSettingsKey.WORK_FOLDER_PATH) ?? "";
    guard !workFolderPath.isEmpty else { return };

    // タブ切替直後はDOMが再構築中のためリトライ
    var popup: AXUIElement?;
    for attempt in 1...10 {
      popup = findWorkFolderPopup(in: appElement);
      if popup != nil { break };
      logManager.info("フォルダポップアップを検索中... (\(attempt)/10)");
      try? await Task.sleep(for: .seconds(1));
    }
    guard let popup else {
      logManager.warning("フォルダポップアップが見つかりません");
      return;
    };

    // 現在の選択値を確認（titleまたはvalueにフォルダ名が含まれていればスキップ）
    let folderName = URL(fileURLWithPath: workFolderPath).lastPathComponent;
    let currentTitle = popup.title ?? "";
    let currentValue: String = popup.value ?? "";
    if currentTitle.contains(folderName) || currentValue.contains(folderName) {
      logManager.info("作業フォルダは設定済みです: \(folderName)");
      return;
    }

    // ポップアップを開く（Electron では AXPress が効かないため CGEvent クリック）
    logManager.info("作業フォルダを設定します: \(workFolderPath)");
    activateClaude();
    try? await Task.sleep(for: .milliseconds(300));
    clickElement(popup);
    try? await Task.sleep(for: .seconds(1));

    // 全要素の value/title/label をチェックしてフォルダ名に一致するクリック可能な要素を検索
    let matchedItem = findClickableElementWithText(folderName, in: appElement);

    if let matchedItem {
      clickElement(matchedItem);
      try? await Task.sleep(for: .milliseconds(300));
      logManager.info("作業フォルダを選択しました: \(folderName)");
    } else {
      logManager.warning("作業フォルダが一覧にありません。Claude for Macで手動追加してください: \(workFolderPath)");
      sendEscapeKey();
    }
  }

  /// AXツリー全体を走査し、テキスト（value/title/label）に一致するクリック可能な要素を返す
  private func findClickableElementWithText(_ text: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 30 else { return nil };
    var childHadTextMatch = false;
    for child in element.children {
      let role = child.role ?? "";
      let val: String? = child.value;
      let titleAttr = child.title;
      let labelAttr = child.label;

      let directMatch = val?.contains(text) == true
                     || titleAttr?.contains(text) == true
                     || labelAttr?.contains(text) == true;

      if directMatch {
        // AXStaticText/AXImage 以外はクリック可能と判断
        if role != kAXStaticTextRole && role != kAXImageRole {
          return child;
        }
        childHadTextMatch = true;
        continue;
      }

      // 再帰検索
      if let found = findClickableElementWithText(text, in: child, depth: depth + 1) {
        return found;
      }
    }

    // 子にテキスト一致があったが StaticText/Image だった場合、この要素がクリック可能な親
    if childHadTextMatch {
      return element;
    }

    return nil;
  }

  private func activateClaude() {
    guard let claudeApp = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    }) else { return };
    claudeApp.activate();
  }

  /// AX要素の中心座標にマウスクリックを送信（cghidEventTap 経由）
  private func clickElement(_ element: AXUIElement) {
    var positionValue: AnyObject?;
    var sizeValue: AnyObject?;
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionValue, let sizeValue else {
      logManager.warning("clickElement: 座標取得に失敗");
      return;
    };

    var position = CGPoint.zero;
    var size = CGSize.zero;
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position);
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size);

    let clickPoint = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2);

    let source = CGEventSource(stateID: .hidSystemState);
    guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
          let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else { return };

    mouseDown.post(tap: .cghidEventTap);
    mouseUp.post(tap: .cghidEventTap);
  }

  private func sendEscapeKey() {
    let source = CGEventSource(stateID: .hidSystemState);
    guard let escDown = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_ESCAPE, keyDown: true),
          let escUp = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_ESCAPE, keyDown: false) else { return };
    guard let claudeApp = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    }) else { return };
    escDown.postToPid(claudeApp.processIdentifier);
    escUp.postToPid(claudeApp.processIdentifier);
  }

  /// キーボードショートカットをClaude プロセスに送信（postToPid経由）
  private func sendKeyboardShortcut(keyCode: UInt16, modifiers: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState);
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
      logManager.warning("sendKeyboardShortcut: CGEvent生成に失敗");
      return;
    };
    keyDown.flags = modifiers;
    keyUp.flags = modifiers;
    guard let claudeApp = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    }) else { return };
    keyDown.postToPid(claudeApp.processIdentifier);
    keyUp.postToPid(claudeApp.processIdentifier);
  }

  // MARK: - プロンプト送信

  func sendPrompt(_ prompt: String) async throws -> String {
    let appElement = try await prepareEnvironment();

    // Claude をフォアグラウンドに切り替え（キーイベント送信に毎回必要）
    guard let claudeApp = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    }) else {
      throw ClaudeControllerError.elementNotFound("Claude process");
    };
    activateClaude();
    try await Task.sleep(for: .milliseconds(500));

    let pid = claudeApp.processIdentifier;

    // テキスト入力フィールドを検索（AXTextArea）してフォーカス
    guard let textField = appElement.findFirst(role: kAXTextAreaRole) else {
      throw ClaudeControllerError.elementNotFound("テキスト入力フィールド");
    };
    textField.setAttribute(kAXFocusedAttribute, value: true as AnyObject);
    try await Task.sleep(for: .milliseconds(200));

    // クリップボード経由でプロンプトを入力（AXValue設定ではElectronのReact状態が更新されないため）
    let pasteboard = NSPasteboard.general;
    let previousContents = pasteboard.string(forType: .string);
    pasteboard.clearContents();
    pasteboard.setString(prompt, forType: .string);

    // Cmd+V をClaude プロセスに直接送信
    let source = CGEventSource(stateID: .hidSystemState);
    guard let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_V, keyDown: true),
          let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_V, keyDown: false) else {
      logManager.error("CGEvent（Cmd+V）の生成に失敗しました");
      throw ClaudeControllerError.sendFailed("キーイベント生成失敗");
    };
    vKeyDown.flags = .maskCommand;
    vKeyUp.flags = .maskCommand;
    vKeyDown.postToPid(pid);
    vKeyUp.postToPid(pid);

    // ペースト完了を待機してからクリップボードを復元
    try await Task.sleep(for: .milliseconds(800));

    pasteboard.clearContents();
    if let previousContents {
      pasteboard.setString(previousContents, forType: .string);
    }

    // Return キーで送信（送信ボタンのAXPress が Electron で機能しない場合の対策）
    guard let returnKeyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_RETURN, keyDown: true),
          let returnKeyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_RETURN, keyDown: false) else {
      logManager.error("CGEvent（Return）の生成に失敗しました");
      throw ClaudeControllerError.sendFailed("キーイベント生成失敗");
    };
    returnKeyDown.postToPid(pid);
    returnKeyUp.postToPid(pid);

    logManager.info("プロンプトを送信しました");

    // 応答を待機
    let response = try await waitForResponse(appElement: appElement, prompt: prompt);
    return response;
  }

  private func waitForResponse(appElement: AXUIElement, prompt: String) async throws -> String {
    let startTime = ContinuousClock.now;

    // 停止ボタンが表示されるまで待機（応答生成開始の確認）
    while isIdle(appElement: appElement) {
      if ContinuousClock.now - startTime > responseTimeout {
        logManager.error("応答開始がタイムアウトしました");
        throw ClaudeControllerError.timeout;
      }
      try await Task.sleep(for: Self.POLLING_INTERVAL);
    }

    logManager.info("応答生成を検知しました");

    // 停止ボタンが消えるまで待機（応答完了の確認）
    while !isIdle(appElement: appElement) {
      if ContinuousClock.now - startTime > responseTimeout {
        logManager.error("応答待機がタイムアウトしました");
        throw ClaudeControllerError.timeout;
      }
      try await Task.sleep(for: Self.POLLING_INTERVAL);
    }

    // 応答完了後、少し待機してDOMの安定化を待つ
    try await Task.sleep(for: .milliseconds(500));

    // 全テキストを収集し、送信したプロンプトの後に出現するテキストを抽出
    let fullText = appElement.collectText();
    var rawResponse: String?;

    // プロンプト全文で最後の出現位置を検索
    if let range = fullText.range(of: prompt, options: .backwards) {
      let text = String(fullText[range.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines);
      if !text.isEmpty {
        rawResponse = text;
      }
    }

    // フォールバック: プロンプト先頭80文字で検索（改行等でテキスト表示が異なる場合）
    if rawResponse == nil {
      let promptPrefix = String(prompt.prefix(80));
      if promptPrefix.count >= 10,
         let range = fullText.range(of: promptPrefix, options: .backwards) {
        let text = String(fullText[range.upperBound...])
          .trimmingCharacters(in: .whitespacesAndNewlines);
        if !text.isEmpty {
          rawResponse = text;
        }
      }
    }

    guard let rawResponse else {
      logManager.warning("応答テキストを取得できませんでした");
      return "";
    }

    // UIクローム（入力欄プレースホルダ、免責事項等）を除去し、折り返し改行を結合
    let response = mergeWrappedLines(trimUIChrome(rawResponse));
    logManager.info("応答を受信しました（\(response.count)文字）");
    return response;
  }

  // Claude for Mac のUI要素テキスト（応答の後に続くプレースホルダ・免責事項等）を除去
  private static let UI_CHROME_MARKERS = [
    "\n返信...",
    "\n返信…",
    "\nReply to",
    "\nReply…",
    "\nClaude は AI のため",
    "\nClaude is an AI",
    "\nOpus",
    "\nSonnet",
    "\nHaiku",
  ];

  // Electronのビジュアル折り返しで生じた改行を結合（句末文字で終わる行は段落区切りとして保持）
  private func mergeWrappedLines(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n");
    var merged = "";
    let paragraphEnders: Set<Character> = ["。", "！", "？", "」", "）", ".", "!", "?", ":", "："];
    for (i, line) in lines.enumerated() {
      if i == 0 {
        merged = line;
        continue;
      }
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        merged += "\n\n";
        continue;
      }
      if let prev = merged.last, paragraphEnders.contains(prev) {
        merged += "\n" + line;
      } else {
        merged += line;
      }
    }
    return merged;
  }

  private func trimUIChrome(_ text: String) -> String {
    var result = text;
    for marker in Self.UI_CHROME_MARKERS {
      if let range = result.range(of: marker) {
        result = String(result[..<range.lowerBound]);
        break;
      }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines);
  }
}

enum ClaudeControllerError: Error, LocalizedError {
  case appNotFound
  case accessibilityNotGranted
  case elementNotFound(String)
  case sendFailed(String)
  case timeout

  var errorDescription: String? {
    switch self {
    case .appNotFound:
      "Claude for Macが見つかりません"
    case .accessibilityNotGranted:
      "アクセシビリティ権限が付与されていません"
    case .elementNotFound(let element):
      "UI要素が見つかりません: \(element)"
    case .sendFailed(let reason):
      "プロンプト送信に失敗しました: \(reason)"
    case .timeout:
      "タイムアウトしました"
    }
  }
}
