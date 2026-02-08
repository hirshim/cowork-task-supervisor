import AppKit
import ApplicationServices

@MainActor
final class ClaudeController {
  static let BUNDLE_IDENTIFIER = "com.anthropic.claudefordesktop";

  private let logManager: LogManager;
  private let accessibilityService: AccessibilityService;
  private var hasLoggedVersion = false;

  init(logManager: LogManager, accessibilityService: AccessibilityService) {
    self.logManager = logManager;
    self.accessibilityService = accessibilityService;
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
  private static let RESPONSE_TIMEOUT: Duration = .seconds(120);

  func isIdle(appElement: AXUIElement) -> Bool {
    appElement.findFirst(role: kAXButtonRole, label: Self.LABEL_STOP_BUTTON) == nil;
  }

  func sendPrompt(_ prompt: String) async throws -> String {
    guard accessibilityService.isAccessibilityGranted else {
      logManager.error("アクセシビリティ権限が付与されていません");
      throw ClaudeControllerError.accessibilityNotGranted;
    };

    if !isClaudeRunning {
      try await launchClaude();
      try await Task.sleep(for: .seconds(2));
    }

    if !hasLoggedVersion {
      _ = getClaudeVersion();
      hasLoggedVersion = true;
    }

    guard let appElement = accessibilityService.appElement(for: Self.BUNDLE_IDENTIFIER) else {
      logManager.error("Claude for MacのAX要素を取得できません");
      throw ClaudeControllerError.elementNotFound("application");
    };

    // Claude for Mac をフォアグラウンドに切り替え
    guard let claudeApp = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == Self.BUNDLE_IDENTIFIER
    }) else {
      throw ClaudeControllerError.elementNotFound("Claude process");
    };
    claudeApp.activate();
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
    let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true);
    let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false);
    vKeyDown?.flags = .maskCommand;
    vKeyUp?.flags = .maskCommand;
    vKeyDown?.postToPid(pid);
    vKeyUp?.postToPid(pid);

    try await Task.sleep(for: .milliseconds(500));

    // クリップボードを復元
    if let previousContents {
      pasteboard.clearContents();
      pasteboard.setString(previousContents, forType: .string);
    }

    // Return キーで送信（送信ボタンのAXPress が Electron で機能しない場合の対策）
    let returnKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true);
    let returnKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false);
    returnKeyDown?.postToPid(pid);
    returnKeyUp?.postToPid(pid);

    logManager.info("プロンプトを送信しました");

    // 応答を待機
    let response = try await waitForResponse(appElement: appElement, prompt: prompt);
    return response;
  }

  private func waitForResponse(appElement: AXUIElement, prompt: String) async throws -> String {
    let startTime = ContinuousClock.now;

    // 停止ボタンが表示されるまで待機（応答生成開始の確認）
    while isIdle(appElement: appElement) {
      if ContinuousClock.now - startTime > Self.RESPONSE_TIMEOUT {
        logManager.error("応答開始がタイムアウトしました");
        throw ClaudeControllerError.timeout;
      }
      try await Task.sleep(for: Self.POLLING_INTERVAL);
    }

    logManager.info("応答生成を検知しました");

    // 停止ボタンが消えるまで待機（応答完了の確認）
    while !isIdle(appElement: appElement) {
      if ContinuousClock.now - startTime > Self.RESPONSE_TIMEOUT {
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
