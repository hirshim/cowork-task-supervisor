import Foundation
import SwiftData

@MainActor
final class TaskManager {
  private let modelContext: ModelContext;
  private let claudeController: ClaudeController;
  private let logManager: LogManager;

  private var isExecuting = false;
  private var isCancelled = false;
  private var pendingQueue: [CTask] = [];

  init(modelContext: ModelContext, claudeController: ClaudeController, logManager: LogManager) {
    self.modelContext = modelContext;
    self.claudeController = claudeController;
    self.logManager = logManager;
  }

  func executeTask(_ task: CTask) async {
    if isExecuting {
      if !pendingQueue.contains(where: { $0.id == task.id }) {
        pendingQueue.append(task);
        task.status = .queued;
        task.updatedAt = Date();
        logManager.info("タスクをキューに追加しました（キュー: \(pendingQueue.count)件）", taskId: task.id);
      }
      return;
    }

    await runTask(task);

    while let next = pendingQueue.first {
      pendingQueue.removeFirst();
      await runTask(next);
    }
  }

  func prepareEnvironment() async {
    do {
      try await claudeController.prepareEnvironment();
    } catch {
      logManager.warning("環境準備に失敗: \(error.localizedDescription)");
    }
  }

  func cancelCurrentTask() {
    isCancelled = true;
    logManager.info("タスクのキャンセルをリクエストしました");
  }

  private func runTask(_ task: CTask) async {
    isExecuting = true;
    isCancelled = false;
    task.status = .running;
    task.response = nil;
    task.errorMessage = nil;
    task.executedAt = Date();
    task.updatedAt = Date();
    logManager.info("タスク実行を開始します: \(task.prompt.prefix(50))", taskId: task.id);

    do {
      let response = try await claudeController.sendPrompt(task.prompt);
      if isCancelled {
        task.status = .cancelled;
        task.updatedAt = Date();
        logManager.info("タスクがキャンセルされました", taskId: task.id);
      } else {
        task.response = response;
        task.errorMessage = nil;
        task.status = .completed;
        task.updatedAt = Date();
        logManager.info("タスクが完了しました", taskId: task.id);
      }
    } catch {
      if isCancelled {
        task.status = .cancelled;
        task.updatedAt = Date();
        logManager.info("タスクがキャンセルされました", taskId: task.id);
      } else {
        task.status = .failed;
        task.response = nil;
        task.errorMessage = error.localizedDescription;
        task.updatedAt = Date();
        logManager.error("タスク実行に失敗: \(error.localizedDescription)", taskId: task.id);
      }
    }

    isCancelled = false;
    isExecuting = false;
  }
}
