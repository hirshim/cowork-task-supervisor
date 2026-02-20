import ApplicationServices

extension AXUIElement {
  static let MAX_DEPTH = 30;

  func attribute<T>(_ key: String) -> T? {
    var value: AnyObject?;
    let result = AXUIElementCopyAttributeValue(self, key as CFString, &value);
    guard result == .success else { return nil };
    return value as? T;
  }

  func setAttribute(_ key: String, value: AnyObject) -> Bool {
    let result = AXUIElementSetAttributeValue(self, key as CFString, value);
    return result == .success;
  }

  var role: String? {
    attribute(kAXRoleAttribute);
  }

  var title: String? {
    attribute(kAXTitleAttribute);
  }

  var value: String? {
    attribute(kAXValueAttribute);
  }

  var children: [AXUIElement] {
    attribute(kAXChildrenAttribute) ?? [];
  }

  var identifier: String? {
    attribute(kAXIdentifierAttribute);
  }

  var subrole: String? {
    attribute(kAXSubroleAttribute);
  }

  var label: String? {
    attribute(kAXDescriptionAttribute);
  }

  var selected: Bool {
    let value: CFBoolean? = attribute(kAXSelectedAttribute);
    guard let value else { return false };
    return CFBooleanGetValue(value);
  }

  var elementBusy: Bool {
    let busy: CFBoolean? = attribute("AXElementBusy" as String);
    guard let busy else { return false };
    return CFBooleanGetValue(busy);
  }

  var position: CGPoint? {
    var positionValue: AnyObject?;
    guard AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &positionValue) == .success,
          let positionValue,
          CFGetTypeID(positionValue) == AXValueGetTypeID() else { return nil };
    var point = CGPoint.zero;
    // swiftlint:disable:next force_cast
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &point);
    return point;
  }

  func performAction(_ action: String) -> Bool {
    let result = AXUIElementPerformAction(self, action as CFString);
    return result == .success;
  }

  func findFirst(role: String, identifier: String? = nil) -> AXUIElement? {
    findFirst(role: role, identifier: identifier, depth: 0);
  }

  private func findFirst(role: String, identifier: String?, depth: Int) -> AXUIElement? {
    guard depth < Self.MAX_DEPTH else { return nil };
    for child in children {
      if child.role == role {
        if let identifier {
          if child.identifier == identifier {
            return child;
          }
        } else {
          return child;
        }
      }
      if let found = child.findFirst(role: role, identifier: identifier, depth: depth + 1) {
        return found;
      }
    }
    return nil;
  }

  func findFirst(role: String, label: String) -> AXUIElement? {
    findFirst(role: role, label: label, depth: 0);
  }

  private func findFirst(role: String, label: String, depth: Int) -> AXUIElement? {
    guard depth < Self.MAX_DEPTH else { return nil };
    for child in children {
      if child.role == role && child.label == label {
        return child;
      }
      if let found = child.findFirst(role: role, label: label, depth: depth + 1) {
        return found;
      }
    }
    return nil;
  }

  func findFirst(role: String, title: String) -> AXUIElement? {
    findFirst(role: role, title: title, depth: 0);
  }

  private func findFirst(role: String, title: String, depth: Int) -> AXUIElement? {
    guard depth < Self.MAX_DEPTH else { return nil };
    for child in children {
      if child.role == role && child.title == title {
        return child;
      }
      if let found = child.findFirst(role: role, title: title, depth: depth + 1) {
        return found;
      }
    }
    return nil;
  }

  func findAll(role: String) -> [AXUIElement] {
    var results: [AXUIElement] = [];
    findAll(role: role, depth: 0, results: &results);
    return results;
  }

  private func findAll(role: String, depth: Int, results: inout [AXUIElement]) {
    guard depth < Self.MAX_DEPTH else { return };
    for child in children {
      if child.role == role {
        results.append(child);
      }
      child.findAll(role: role, depth: depth + 1, results: &results);
    }
  }

  func collectText() -> String {
    var texts: [String] = [];
    collectText(depth: 0, texts: &texts);

    guard !texts.isEmpty else { return ""; }

    // Electron が AXStaticText を分割する問題への対策:
    // インライン要素の境界で分割されたフラグメントを前のフラグメントに結合
    let midTokenChars: Set<Character> = [":", ";", ",", ")", "）", "」", "】", "/"];
    let listMarkers: Set<Character> = ["-", "*", "•"];
    var lines: [String] = [texts[0]];
    for i in 1..<texts.count {
      let fragment = texts[i];
      let trimmed = fragment.trimmingCharacters(in: .whitespaces);
      guard !trimmed.isEmpty else { continue };

      let shouldMerge: Bool;
      if let first = trimmed.first, midTokenChars.contains(first) {
        // 行頭に来ないはずの文字で始まる（: ; , / 等）
        shouldMerge = true;
      } else if lines.last?.trimmingCharacters(in: .whitespaces).hasSuffix("/") == true {
        // 前の行が "/" で終わる（セパレータの途中で分割された）
        shouldMerge = true;
      } else if fragment.first == " ", let first = trimmed.first, !listMarkers.contains(first) {
        // 先頭スペースで始まるインライン継続（リスト項目は除外）
        shouldMerge = true;
      } else {
        shouldMerge = false;
      }

      if shouldMerge {
        lines[lines.count - 1] += fragment;
      } else {
        lines.append(fragment);
      }
    }
    return lines.joined(separator: "\n");
  }

  private func collectText(depth: Int, texts: inout [String]) {
    guard depth < Self.MAX_DEPTH else { return };
    for child in children {
      if child.role == kAXStaticTextRole, let text = child.value, !text.isEmpty {
        texts.append(text);
      } else if child.role == kAXHeadingRole, let text = child.title, !text.isEmpty {
        texts.append(text);
      }
      child.collectText(depth: depth + 1, texts: &texts);
    }
  }
}
