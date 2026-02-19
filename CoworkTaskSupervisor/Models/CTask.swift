import Foundation
import SwiftData

@Model
final class CTask {
  var id: UUID = UUID()
  var title: String?
  var prompt: String = ""
  var comment: String?
  var status: TaskStatus = TaskStatus.pending
  var category: String?
  var order: Int = 0
  var response: String?
  var errorMessage: String?
  var createdAt: Date = Date()
  var updatedAt: Date = Date()
  var executedAt: Date?
  var scheduledAt: Date?
  var repeatRule: RepeatRule?
  var autoExecution: AutoExecutionMode?

  var isAutoExecutionEnabled: Bool {
    switch autoExecution {
    case .on: return true;
    case .thisDeviceOnly(let deviceId): return deviceId == DeviceIdentifier.current;
    case .off, nil: return false;
    }
  }

  init(
    title: String? = nil,
    prompt: String,
    comment: String? = nil,
    category: String? = nil,
    order: Int = 0,
    scheduledAt: Date? = nil,
    repeatRule: RepeatRule? = nil,
    autoExecution: AutoExecutionMode? = nil
  ) {
    self.id = UUID();
    self.title = title;
    self.prompt = prompt;
    self.comment = comment;
    self.status = .pending;
    self.category = category;
    self.order = order;
    self.response = nil;
    self.errorMessage = nil;
    self.createdAt = Date();
    self.updatedAt = Date();
    self.executedAt = nil;
    self.scheduledAt = scheduledAt;
    self.repeatRule = repeatRule;
    self.autoExecution = autoExecution;
  }
}
