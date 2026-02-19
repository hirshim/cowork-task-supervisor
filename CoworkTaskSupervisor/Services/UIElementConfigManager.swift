import ApplicationServices
import Foundation

@Observable
@MainActor
final class UIElementConfigManager {
  private static let USER_DEFAULTS_KEY = "UIElementConfig";

  private(set) var config: UIElementConfig;
  private let logManager: LogManager;

  init(logManager: LogManager) {
    self.logManager = logManager;
    self.config = Self.load() ?? .default;
  }

  // MARK: - バージョン検証・自動検出

  /// 新バージョン検出時にUI要素の存在を検証し、必要に応じて自動検出を行う
  func verifyAndUpdate(appElement: AXUIElement, version: String) {
    if config.verifiedVersion == version {
      return;
    }

    logManager.info("Claude for Mac \(version) のUI要素を検証中...");

    var updatedConfig = config;
    var missingCount = 0;
    var updatedCount = 0;

    // タブ判定マーカーの検証
    missingCount += verifyMarkers(updatedConfig.coworkMarkers, label: "Cowork", in: appElement);
    missingCount += verifyMarkers(updatedConfig.chatMarkers, label: "Chat", in: appElement);
    missingCount += verifyMarkers(updatedConfig.codeMarkers, label: "Code", in: appElement);

    // 操作用要素の検証
    let operationMarkers: [(String, ElementMarker)] = [
      ("停止ボタン", updatedConfig.stopButton),
      ("キューボタン", updatedConfig.queueButton),
      ("作業フォルダポップアップ", updatedConfig.workFolderPopup),
    ];

    for (name, marker) in operationMarkers {
      if marker.find(in: appElement) == nil {
        logManager.warning("UI要素が見つかりません: \(name) (\(marker.value))");

        // 同じ role で自動検出を試みる
        let candidates = autoDiscover(role: marker.role, in: appElement);
        if !candidates.isEmpty {
          let candidateNames = candidates.map { $0.value }.joined(separator: ", ");
          logManager.info("  候補: \(candidateNames)");
          updatedCount += 1;
        }
        missingCount += 1;
      }
    }

    if missingCount == 0 {
      logManager.info("全UI要素の検証OK — バージョン \(version) 対応確認");
      updatedConfig.verifiedVersion = version;
      config = updatedConfig;
      save();
    } else if missingCount <= 2 {
      logManager.warning("\(missingCount)個のUI要素が見つかりません。フォールバック設定で動作を継続します");
      updatedConfig.verifiedVersion = version;
      config = updatedConfig;
      save();
    } else {
      logManager.error("多数のUI要素が見つかりません（\(missingCount)個）。Claude for Mac \(version) は未対応の可能性があります");
      // verifiedVersion は更新しない（次回も検証を試みる）
    }
  }

  /// 自動検出: 指定 role の全要素から title/label を収集して候補リストを返す
  func autoDiscover(role: String, in appElement: AXUIElement) -> [ElementMarker] {
    let elements = appElement.findAll(role: role);
    var candidates: [ElementMarker] = [];

    for element in elements {
      if let title = element.title, !title.isEmpty {
        candidates.append(ElementMarker(role: role, attribute: .title, value: title));
      }
      if let label = element.label, !label.isEmpty {
        candidates.append(ElementMarker(role: role, attribute: .label, value: label));
      }
    }

    return candidates;
  }

  // MARK: - Private

  private func verifyMarkers(_ markers: [ElementMarker], label: String, in appElement: AXUIElement) -> Int {
    var missing = 0;
    for marker in markers {
      if marker.find(in: appElement) == nil {
        logManager.warning("\(label)タブマーカーが見つかりません: \(marker.value)");
        missing += 1;
      }
    }
    return missing;
  }

  private static func load() -> UIElementConfig? {
    guard let data = UserDefaults.standard.data(forKey: USER_DEFAULTS_KEY) else { return nil };
    return try? JSONDecoder().decode(UIElementConfig.self, from: data);
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(config) else { return };
    UserDefaults.standard.set(data, forKey: Self.USER_DEFAULTS_KEY);
  }
}
