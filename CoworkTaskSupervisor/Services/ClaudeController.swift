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

    // テキスト入力フィールドを検索（AXTextArea）
    guard let textField = appElement.findFirst(role: kAXTextAreaRole) else {
      throw ClaudeControllerError.elementNotFound("テキスト入力フィールド");
    };

    // プロンプトを入力
    guard textField.setAttribute(kAXValueAttribute, value: prompt as AnyObject) else {
      throw ClaudeControllerError.sendFailed("テキストの設定に失敗");
    };

    // 送信ボタンを検索（初期画面: 「タスクを開始」、会話中: 「メッセージを送信」）
    let sendButton = appElement.findFirst(role: kAXButtonRole, label: Self.LABEL_SEND_BUTTON_CONVERSATION)
      ?? appElement.findFirst(role: kAXButtonRole, label: Self.LABEL_SEND_BUTTON_INITIAL);

    guard let sendButton else {
      throw ClaudeControllerError.elementNotFound("送信ボタン");
    };

    guard sendButton.performAction(kAXPressAction) else {
      throw ClaudeControllerError.sendFailed("送信ボタンの押下に失敗");
    };

    logManager.info("プロンプトを送信しました");

    // 応答を待機
    let response = try await waitForResponse(appElement: appElement);
    return response;
  }

  private func waitForResponse(appElement: AXUIElement) async throws -> String {
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

    // 応答コンテナから最後の応答グループのテキストを収集
    let responseGroups = appElement.findAll(role: kAXGroupRole);
    for group in responseGroups.reversed() {
      let text = group.collectText();
      if !text.isEmpty && text.count > 10 {
        logManager.info("応答を受信しました");
        return text;
      }
    }

    logManager.warning("応答テキストを取得できませんでした");
    return "";
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
