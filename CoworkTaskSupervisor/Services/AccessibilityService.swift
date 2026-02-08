import AppKit
import ApplicationServices
import Combine

@MainActor
final class AccessibilityService: ObservableObject {
  @Published private(set) var isAccessibilityGranted: Bool = false;

  private var pollingTimer: Timer?;

  init() {
    checkAccessibility();
  }

  func checkAccessibility() {
    isAccessibilityGranted = AXIsProcessTrusted();
  }

  func requestAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary;
    AXIsProcessTrustedWithOptions(options);
    startPolling();
  }

  func startPolling() {
    stopPolling();
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.checkAccessibility();
        if self?.isAccessibilityGranted == true {
          self?.stopPolling();
        }
      }
    };
  }

  func stopPolling() {
    pollingTimer?.invalidate();
    pollingTimer = nil;
  }

  func appElement(for bundleIdentifier: String) -> AXUIElement? {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == bundleIdentifier
    }) else { return nil };
    return AXUIElementCreateApplication(app.processIdentifier);
  }
}
