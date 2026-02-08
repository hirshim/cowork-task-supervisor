import Foundation
import SwiftData

@MainActor
final class LogManager {
  private let modelContext: ModelContext;

  init(modelContext: ModelContext) {
    self.modelContext = modelContext;
  }

  func log(_ message: String, level: LogLevel = .info, taskId: UUID? = nil) {
    let entry = AppLog(message: message, level: level, taskId: taskId);
    modelContext.insert(entry);
  }

  func info(_ message: String, taskId: UUID? = nil) {
    log(message, level: .info, taskId: taskId);
  }

  func warning(_ message: String, taskId: UUID? = nil) {
    log(message, level: .warning, taskId: taskId);
  }

  func error(_ message: String, taskId: UUID? = nil) {
    log(message, level: .error, taskId: taskId);
  }
}
