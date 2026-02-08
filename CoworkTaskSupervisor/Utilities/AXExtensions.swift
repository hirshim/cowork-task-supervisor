import ApplicationServices

extension AXUIElement {
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
    let elements: CFArray? = attribute(kAXChildrenAttribute);
    guard let elements else { return [] };
    return (0..<CFArrayGetCount(elements)).compactMap { index in
      let element = CFArrayGetValueAtIndex(elements, index);
      return (element as! AXUIElement);
    };
  }

  var identifier: String? {
    attribute(kAXIdentifierAttribute);
  }

  var subrole: String? {
    attribute(kAXSubroleAttribute);
  }

  func performAction(_ action: String) -> Bool {
    let result = AXUIElementPerformAction(self, action as CFString);
    return result == .success;
  }

  func findFirst(role: String, identifier: String? = nil) -> AXUIElement? {
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
      if let found = child.findFirst(role: role, identifier: identifier) {
        return found;
      }
    }
    return nil;
  }

  func findAll(role: String) -> [AXUIElement] {
    var results: [AXUIElement] = [];
    for child in children {
      if child.role == role {
        results.append(child);
      }
      results.append(contentsOf: child.findAll(role: role));
    }
    return results;
  }
}
