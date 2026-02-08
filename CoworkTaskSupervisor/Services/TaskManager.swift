import Foundation
import SwiftData

@MainActor
final class TaskManager {
  private let modelContext: ModelContext;
  private let claudeController: ClaudeController;
  private let logManager: LogManager;

  private var isExecuting = false;

  init(modelContext: ModelContext, claudeController: ClaudeController, logManager: LogManager) {
    self.modelContext = modelContext;
    self.claudeController = claudeController;
    self.logManager = logManager;
  }

  func executeTask(_ task: CTask) async {
    guard !isExecuting else {
      logManager.warning("別のタスクを実行中です", taskId: task.id);
      return;
    };

    isExecuting = true;
    task.status = .running;
    task.executedAt = Date();
    task.updatedAt = Date();
    logManager.info("タスク実行を開始します: \(task.prompt.prefix(50))", taskId: task.id);

    do {
      let response = try await claudeController.sendPrompt(task.prompt);
      task.response = response;
      task.status = .completed;
      task.updatedAt = Date();
      logManager.info("タスクが完了しました", taskId: task.id);
    } catch {
      task.status = .failed;
      task.errorMessage = error.localizedDescription;
      task.updatedAt = Date();
      logManager.error("タスク実行に失敗: \(error.localizedDescription)", taskId: task.id);
    }

    isExecuting = false;
  }
}
