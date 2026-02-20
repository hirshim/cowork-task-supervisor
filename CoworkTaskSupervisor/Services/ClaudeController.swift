import AppKit
import ApplicationServices

@MainActor
final class ClaudeController {
  static let BUNDLE_IDENTIFIER = "com.anthropic.claudefordesktop";

  private let logManager: LogManager;
  private let accessibilityService: AccessibilityService;
  private let configManager: UIElementConfigManager;
  private var hasLoggedVersion = false;

  init(logManager: LogManager, accessibilityService: AccessibilityService, configManager: UIElementConfigManager) {
    self.logManager = logManager;
    self.accessibilityService = accessibilityService;
    self.configManager = configManager;
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
        self?.hasLoggedVersion = false;
        self?.logManager.warning("Claude for Macが終了しました。次回タスク実行時に再起動します。");
      }
    };
  }

  // MARK: - 基本制御

  var isClaudeRunning: Bool { claudeApp != nil }

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

  private static let POLLING_INTERVAL: Duration = .milliseconds(500);
  private static let DEFAULT_RESPONSE_TIMEOUT_SECONDS = 300;

  private var responseTimeout: Duration {
    let seconds = UserDefaults.standard.integer(forKey: AppSettingsKey.RESPONSE_TIMEOUT_SECONDS);
    return .seconds(seconds > 0 ? seconds : Self.DEFAULT_RESPONSE_TIMEOUT_SECONDS);
  }

  private static let BUSY_POLL_INTERVAL: Duration = .seconds(5);
  private static let AX_TREE_MAX_RETRIES = 3;

  // macOS 仮想キーコード
  private static let VIRTUAL_KEY_2: UInt16 = 0x13;
  private static let VIRTUAL_KEY_N: UInt16 = 0x2D;
  private static let VIRTUAL_KEY_R: UInt16 = 0x0F;
  private static let VIRTUAL_KEY_V: UInt16 = 0x09;
  private static let VIRTUAL_KEY_RETURN: UInt16 = 0x24;
  private static let VIRTUAL_KEY_END: UInt16 = 0x77;
  private static let VIRTUAL_KEY_DOWN_ARROW: UInt16 = 0x7D;
  private static let VIRTUAL_KEY_ESCAPE: UInt16 = 0x35;

  private func isIdle(appElement: AXUIElement) -> Bool {
    configManager.config.stopButton.find(in: appElement) == nil;
  }

  // MARK: - 環境準備

  @discardableResult
  func prepareEnvironment() async throws -> AXUIElement {
    guard accessibilityService.isAccessibilityGranted else {
      logManager.error("アクセシビリティ権限が付与されていません");
      throw ClaudeControllerError.accessibilityNotGranted;
    };

    // 1. Claude の起動確認
    var appElement = try await ensureClaudeLaunched();

    // 2. タブ判定 → Chat/Code なら Cowork に切替
    try await ensureCoworkTab(appElement: appElement);

    // タブ切替後、Electron が DOM を再構築するため appElement を再取得
    if let freshElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) {
      appElement = freshElement;
    }

    // 3. Cowork がビジー（実行中）なら待機
    try await waitUntilCoworkIdle(appElement: appElement);

    // 4. 作業フォルダの設定
    await ensureWorkFolder(appElement: appElement);

    logManager.info("環境準備が完了しました");
    return appElement;
  }

  private func ensureClaudeLaunched() async throws -> AXUIElement {
    if !isClaudeRunning {
      try await launchClaude();
      try await Task.sleep(for: .seconds(3));
    }

    activateClaude();
    try await Task.sleep(for: .milliseconds(500));

    guard let appElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) else {
      logManager.error("Claude for MacのAX要素を取得できません");
      throw ClaudeControllerError.elementNotFound("application");
    };

    if !hasLoggedVersion {
      if let version = getClaudeVersion() {
        configManager.verifyAndUpdate(appElement: appElement, version: version);
      }
      hasLoggedVersion = true;
    }

    return appElement;
  }

  // MARK: - タブ判定
  // 判定ロジックは docs/RESULT.md に基づく:
  // A(セッションアクティビティパネル) or B(タスクを片付けましょう) → Cowork確定

  /// coworkMarkers のいずれかが存在すれば Cowork タブと判定
  private func isCoworkTab(appElement: AXUIElement) -> Bool {
    configManager.config.coworkMarkers.contains(where: { $0.find(in: appElement) != nil });
  }

  /// Coworkタブへの切替（Cowork以外なら Cmd+2 で切替、リトライ付き）
  private func ensureCoworkTab(appElement: AXUIElement) async throws {
    if isCoworkTab(appElement: appElement) {
      logManager.info("Coworkタブは選択済みです");
      return;
    }

    // Cowork以外 → 切替
    logManager.info("Coworkタブに切り替えます");
    switchToCoworkTab();
    try await Task.sleep(for: .seconds(1));

    // 切替後のリトライ確認
    for attempt in 1...Self.AX_TREE_MAX_RETRIES {
      activateClaude();
      try await Task.sleep(for: .seconds(1));

      guard let freshElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) else {
        continue;
      }
      if isCoworkTab(appElement: freshElement) {
        logManager.info("Coworkタブへの切替を確認");
        return;
      }
      logManager.info("Coworkタブを確認中... (\(attempt)/\(Self.AX_TREE_MAX_RETRIES))");
    }

    logManager.error("Coworkタブへの切替を確認できません。Claude for MacのUI構造が変更された可能性があります");
    throw ClaudeControllerError.elementNotFound("Coworkタブ");
  }

  private func switchToCoworkTab() {
    activateClaude();
    sendKeyboardShortcut(keyCode: Self.VIRTUAL_KEY_2, modifiers: .maskCommand);
  }

  // MARK: - Cowork ビジー待機

  /// Coworkが実行中（「応答を停止」ボタンが存在）の間、ポーリング待機
  private func waitUntilCoworkIdle(appElement: AXUIElement) async throws {
    guard !isIdle(appElement: appElement) else {
      return; // 既にアイドル
    }
    logManager.info("Cowork実行中のため待機します");
    let startTime = ContinuousClock.now;
    while !isIdle(appElement: appElement) {
      if ContinuousClock.now - startTime > responseTimeout {
        logManager.error("Coworkアイドル待機がタイムアウトしました");
        throw ClaudeControllerError.timeout;
      }
      try await Task.sleep(for: Self.BUSY_POLL_INTERVAL);
    }
    logManager.info("Coworkがアイドルになりました");
  }

  /// フォルダポップアップを検索（未設定時の「フォルダで作業」と設定済みフォルダ名の両方に対応）
  /// コールドスタート時に title ではなく label（AXDescription）にテキストが格納される場合があるため両方検索
  private func findWorkFolderPopup(in appElement: AXUIElement) -> AXUIElement? {
    let popupMarker = configManager.config.workFolderPopup;
    // 未設定時: title or label = "フォルダで作業"
    if let popup = popupMarker.find(in: appElement)
                ?? appElement.findFirst(role: popupMarker.role, label: popupMarker.value) {
      return popup;
    }
    // 設定済み時: title/label がフォルダ名に変わる
    let workFolderPath = UserDefaults.standard.string(forKey: AppSettingsKey.WORK_FOLDER_PATH) ?? "";
    if !workFolderPath.isEmpty {
      let folderName = URL(fileURLWithPath: workFolderPath).lastPathComponent;
      if let popup = appElement.findFirst(role: kAXPopUpButtonRole, title: folderName)
                  ?? appElement.findFirst(role: kAXPopUpButtonRole, label: folderName) {
        return popup;
      }
    }
    return nil;
  }

  private func ensureWorkFolder(appElement: AXUIElement) async {
    let workFolderPath = UserDefaults.standard.string(forKey: AppSettingsKey.WORK_FOLDER_PATH) ?? "";
    guard !workFolderPath.isEmpty else { return };

    // AXツリー構築遅延に備えて最大3回リトライ
    var popup: AXUIElement?;
    for attempt in 1...Self.AX_TREE_MAX_RETRIES {
      popup = findWorkFolderPopup(in: appElement);
      if popup != nil { break };
      logManager.info("フォルダポップアップを検索中... (\(attempt)/\(Self.AX_TREE_MAX_RETRIES))");
      try? await Task.sleep(for: .seconds(1));
    }
    guard let popup else {
      logManager.warning("フォルダポップアップが見つかりません。UI構造が変更された可能性があります");
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
    guard depth < AXUIElement.MAX_DEPTH else { return nil };
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

  private var claudeApp: NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    };
  }

  private func activateClaude() {
    claudeApp?.activate();
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
    // positionValue/sizeValue は AXValueRef（CFType）— CFTypeID で型を検証
    guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
      logManager.warning("clickElement: AXValue型変換に失敗");
      return;
    };
    // swiftlint:disable:next force_cast
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position);
    // swiftlint:disable:next force_cast
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
          let escUp = CGEvent(keyboardEventSource: source, virtualKey: Self.VIRTUAL_KEY_ESCAPE, keyDown: false),
          let pid = claudeApp?.processIdentifier else { return };
    escDown.postToPid(pid);
    escUp.postToPid(pid);
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
    guard let pid = claudeApp?.processIdentifier else { return };
    keyDown.postToPid(pid);
    keyUp.postToPid(pid);
  }

  // MARK: - プロンプト送信

  private static let PROMPT_INPUT_DESCRIPTION = "クロードにプロンプトを入力してください";

  func sendPrompt(_ prompt: String) async throws -> String {
    let appElement = try await prepareEnvironment();

    // Claude をフォアグラウンドに切り替え（キーイベント送信に毎回必要）
    guard let pid = claudeApp?.processIdentifier else {
      throw ClaudeControllerError.elementNotFound("Claude process");
    };
    activateClaude();
    try await Task.sleep(for: .milliseconds(500));

    // 新規会話を開始（Cmd+N）
    sendKeyboardShortcut(keyCode: Self.VIRTUAL_KEY_N, modifiers: .maskCommand);
    try await Task.sleep(for: .seconds(1));

    // テキスト入力フィールドを description で検索してフォーカス
    var textField: AXUIElement?;
    for attempt in 1...Self.AX_TREE_MAX_RETRIES {
      // Cmd+N後のDOM再構築に備えてappElementを再取得
      let currentElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) ?? appElement;
      textField = currentElement.findFirst(role: kAXTextAreaRole, label: Self.PROMPT_INPUT_DESCRIPTION);
      if textField != nil { break };
      logManager.info("入力フィールドを検索中... (\(attempt)/\(Self.AX_TREE_MAX_RETRIES))");
      try await Task.sleep(for: .seconds(1));
    }
    guard let textField else {
      throw ClaudeControllerError.elementNotFound("テキスト入力フィールド");
    };
    _ = textField.setAttribute(kAXFocusedAttribute, value: true as AnyObject);
    try await Task.sleep(for: .milliseconds(200));

    // クリップボード経由でプロンプトを入力（AXValue設定ではElectronのReact状態が更新されないため）
    let pasteboard = NSPasteboard.general;
    let previousContents = pasteboard.string(forType: .string);
    pasteboard.clearContents();
    pasteboard.setString(prompt, forType: .string);
    defer {
      pasteboard.clearContents();
      if let previousContents {
        pasteboard.setString(previousContents, forType: .string);
      }
    }

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

  private static let EXECUTION_SAFETY_TIMEOUT: Duration = .seconds(3600);

  private func waitForResponse(appElement: AXUIElement, prompt: String) async throws -> String {
    let startTime = ContinuousClock.now;

    // Phase 1: 停止ボタンが表示されるまで待機（応答生成開始の確認）
    // → responseTimeout（デフォルト5分）で打ち切り（送信失敗の検出）
    while isIdle(appElement: appElement) {
      if ContinuousClock.now - startTime > responseTimeout {
        logManager.error("応答開始がタイムアウトしました");
        throw ClaudeControllerError.timeout;
      }
      try await Task.sleep(for: Self.POLLING_INTERVAL);
    }

    logManager.info("応答生成を検知しました");

    // Phase 2: 停止ボタンが消えるまで待機（応答完了の確認）
    // → 停止ボタンが存在する限り Claude は処理中なのでタイムアウトしない
    //   安全上限（1時間）のみ設定
    let executionStart = ContinuousClock.now;
    while !isIdle(appElement: appElement) {
      let elapsed = ContinuousClock.now - executionStart;
      if elapsed > Self.EXECUTION_SAFETY_TIMEOUT {
        logManager.error("応答生成の安全上限（1時間）に達しました");
        throw ClaudeControllerError.timeout;
      }
      // 5分ごとに経過を記録
      let minutes = Int(elapsed.components.seconds) / 60;
      if minutes > 0 && Int(elapsed.components.seconds) % 300 == 0 {
        logManager.info("応答生成中... （\(minutes)分経過）");
      }
      try await Task.sleep(for: Self.POLLING_INTERVAL);
    }

    // 応答完了後、少し待機してDOMの安定化を待つ
    try await Task.sleep(for: .milliseconds(500));

    // 会話の末尾にスクロール（仮想DOMで応答テキストがレンダリングされるように）
    // Escape で入力フィールドのフォーカスを解除し、End キーでページ末尾へ
    activateClaude();
    sendEscapeKey();
    try await Task.sleep(for: .milliseconds(200));
    sendKeyboardShortcut(keyCode: Self.VIRTUAL_KEY_END, modifiers: []);
    try await Task.sleep(for: .milliseconds(500));

    // 応答テキスト抽出
    var rawResponse: String?;
    var bestFullText = "";
    var usedFallback = false;

    for extractAttempt in 0..<3 {
      let currentElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) ?? appElement;
      let fullText = currentElement.collectText();
      logManager.info("collectText: \(fullText.count)文字取得（試行\(extractAttempt + 1)）");

      // 最も多くテキストを取得できた結果を保持（リロードで減少する場合に備える）
      if fullText.count > bestFullText.count {
        bestFullText = fullText;
      }

      // 1. プロンプト全文で最後の出現位置を検索
      if let range = fullText.range(of: prompt, options: .backwards) {
        let text = String(fullText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines);
        if !text.isEmpty { rawResponse = text; break; }
      }
      // 2. プロンプト1行目で検索（長い会話でプロンプトがスクロールアウトしても1行目が残る場合）
      if rawResponse == nil {
        let firstLine = prompt.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "";
        if firstLine.count >= 10,
           let range = fullText.range(of: firstLine, options: .backwards) {
          let text = String(fullText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines);
          if !text.isEmpty { rawResponse = text; break; }
        }
      }
      // 3. プロンプト先頭80文字で検索（改行等でテキスト表示が異なる場合）
      if rawResponse == nil {
        let promptPrefix = String(prompt.prefix(80));
        if promptPrefix.count >= 10,
           let range = fullText.range(of: promptPrefix, options: .backwards) {
          let text = String(fullText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines);
          if !text.isEmpty { rawResponse = text; break; }
        }
      }

      // テキストが十分にあるのにプロンプトが見つからない → リロードせずフォールバックへ
      // （Cmd+R はDOMコンテンツを破壊するため、テキストがある場合はリロードしない）
      if fullText.count > 100 {
        logManager.info("プロンプトが見つかりませんが、テキストは取得済み（\(fullText.count)文字）。フォールバックへ移行");
        break;
      }

      // テキストが少ない/空の場合のみ Cmd+R でリロードしてリトライ
      if extractAttempt < 2 {
        logManager.info("応答テキストが取得できません。ページをリロードします（\(extractAttempt + 1)/2）");
        sendKeyboardShortcut(keyCode: Self.VIRTUAL_KEY_R, modifiers: .maskCommand);
        try await Task.sleep(for: .seconds(2));
        // リロード後、再度末尾にスクロール
        sendEscapeKey();
        try await Task.sleep(for: .milliseconds(200));
        sendKeyboardShortcut(keyCode: Self.VIRTUAL_KEY_END, modifiers: []);
        try await Task.sleep(for: .milliseconds(500));
      }
    }

    // フォールバック: プロンプトがAXツリーに存在しない場合（長い会話で完全にスクロールアウト）
    //   → 保持した最良テキストからCowork最終応答を抽出して返す
    if rawResponse == nil && !bestFullText.isEmpty {
      let withoutChrome = trimUIChrome(bestFullText).trimmingCharacters(in: .whitespacesAndNewlines);
      if !withoutChrome.isEmpty {
        let lastResponse = extractLastCoworkResponse(withoutChrome);
        logManager.info("フォールバック: 最終応答を抽出しました（\(lastResponse.count)/\(withoutChrome.count)文字）");
        rawResponse = lastResponse;
        usedFallback = true;
      }
    }

    guard let rawResponse else {
      logManager.warning("応答テキストを取得できませんでした");
      return "";
    }

    // 思考プロセス除去 → UIクローム除去
    // フォールバック（Cowork長会話）では mergeWrappedLines を適用しない（構造化テキストの改行を保持）
    let processed = trimUIChrome(stripThinkingSection(rawResponse));
    let response = usedFallback ? processed : mergeWrappedLines(processed);
    logManager.info("応答を受信しました（\(response.count)文字）");
    return response;
  }

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

  /// Cowork会話テキストから最終応答を抽出
  /// ツールコール完了マーカー「完了」を区切りとして、最後のセクションを返す
  private func extractLastCoworkResponse(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n");

    // 末尾から遡って、独立した「完了」行を探す
    // （collectText()では「完了」が独立したAXStaticTextとして収集されるため、独立行として存在する）
    var lastCompletionIndex = -1;
    for i in stride(from: lines.count - 1, through: 0, by: -1) {
      if lines[i].trimmingCharacters(in: .whitespaces) == "完了" {
        lastCompletionIndex = i;
        break;
      }
    }

    if lastCompletionIndex >= 0 && lastCompletionIndex < lines.count - 1 {
      let resultLines = Array(lines[(lastCompletionIndex + 1)...]);
      let result = resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines);
      if !result.isEmpty {
        return result;
      }
    }

    return text; // 「完了」が見つからない場合は全テキストを返す
  }

  /// 思考プロセス（extended thinking）セクションを除去
  private func stripThinkingSection(_ text: String) -> String {
    guard let startRange = text.range(of: "思考プロセス") else { return text; }
    let afterThinking = text[startRange.lowerBound...];
    if let endRange = afterThinking.range(of: "\n完了") {
      let afterEnd = String(text[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines);
      let beforeThinking = String(text[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines);
      return beforeThinking.isEmpty ? afterEnd : beforeThinking + "\n" + afterEnd;
    }
    return String(text[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines);
  }

  private func trimUIChrome(_ text: String) -> String {
    var result = text;
    for marker in configManager.config.uiChromeMarkers {
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
