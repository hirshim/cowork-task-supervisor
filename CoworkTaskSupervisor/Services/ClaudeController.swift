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
  // NOTE: UI要素のrole/identifierはStep 6（Accessibility Inspector調査）の結果に基づいて更新が必要

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

    // TODO: Step 6の調査結果に基づいてUI要素パスを更新
    // テキスト入力フィールドを検索
    guard let textField = appElement.findFirst(role: kAXTextAreaRole) else {
      throw ClaudeControllerError.elementNotFound("テキスト入力フィールド");
    };

    // プロンプトを入力
    guard textField.setAttribute(kAXValueAttribute, value: prompt as AnyObject) else {
      throw ClaudeControllerError.sendFailed("テキストの設定に失敗");
    };

    // TODO: 送信ボタンの特定方法はStep 6の調査結果に依存
    // 送信ボタンを検索して押下
    guard let sendButton = appElement.findFirst(role: kAXButtonRole, identifier: nil) else {
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

  private static let POLLING_INTERVAL: Duration = .milliseconds(500);
  private static let RESPONSE_TIMEOUT: Duration = .seconds(120);

  private func waitForResponse(appElement: AXUIElement) async throws -> String {
    let startTime = ContinuousClock.now;

    while ContinuousClock.now - startTime < Self.RESPONSE_TIMEOUT {
      try await Task.sleep(for: Self.POLLING_INTERVAL);

      // TODO: Step 6の調査結果に基づいてアイドル判定とレスポンス取得を実装
      // 現在はプレースホルダー: テキストエリアから最新の応答を読み取る
      let textAreas = appElement.findAll(role: kAXStaticTextRole);
      if let lastResponse = textAreas.last, let text = lastResponse.value, !text.isEmpty {
        logManager.info("応答を受信しました");
        return text;
      }
    }

    logManager.error("応答待機がタイムアウトしました");
    throw ClaudeControllerError.timeout;
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
