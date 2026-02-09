import ApplicationServices

extension AXUIElement {
  private static let MAX_DEPTH = 30;

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
    return texts.joined(separator: "\n");
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
