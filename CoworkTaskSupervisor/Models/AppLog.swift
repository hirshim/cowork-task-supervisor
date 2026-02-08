import Foundation
import SwiftData

@Model
final class AppLog {
  var id: UUID
  var taskId: UUID?
  var message: String
  var level: LogLevel
  var createdAt: Date

  init(
    message: String,
    level: LogLevel,
    taskId: UUID? = nil
  ) {
    self.id = UUID();
    self.taskId = taskId;
    self.message = message;
    self.level = level;
    self.createdAt = Date();
  }
}
