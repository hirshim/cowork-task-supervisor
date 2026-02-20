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

  // MARK: - Undo 用スナップショット

  struct Snapshot {
    let id: UUID;
    let title: String?;
    let prompt: String;
    let comment: String?;
    let status: TaskStatus;
    let category: String?;
    let order: Int;
    let response: String?;
    let errorMessage: String?;
    let createdAt: Date;
    let updatedAt: Date;
    let executedAt: Date?;
    let scheduledAt: Date?;
    let repeatRule: RepeatRule?;
    let autoExecution: AutoExecutionMode?;
  }

  func snapshot() -> Snapshot {
    Snapshot(
      id: id, title: title, prompt: prompt, comment: comment,
      status: status, category: category, order: order,
      response: response, errorMessage: errorMessage,
      createdAt: createdAt, updatedAt: updatedAt, executedAt: executedAt,
      scheduledAt: scheduledAt, repeatRule: repeatRule, autoExecution: autoExecution
    );
  }

  static func restore(from snapshot: Snapshot) -> CTask {
    let task = CTask(
      title: snapshot.title, prompt: snapshot.prompt,
      comment: snapshot.comment, category: snapshot.category,
      order: snapshot.order, scheduledAt: snapshot.scheduledAt,
      repeatRule: snapshot.repeatRule, autoExecution: snapshot.autoExecution
    );
    task.id = snapshot.id;
    task.status = snapshot.status;
    task.response = snapshot.response;
    task.errorMessage = snapshot.errorMessage;
    task.createdAt = snapshot.createdAt;
    task.updatedAt = snapshot.updatedAt;
    task.executedAt = snapshot.executedAt;
    return task;
  }
}
