import Foundation
import SwiftData

@MainActor
final class TaskManager {
  private let modelContext: ModelContext;
  private let claudeController: ClaudeController;
  private let logManager: LogManager;

  private static let MAX_QUEUE_SIZE = 50;

  private var isExecuting = false;
  private var isCancelled = false;
  private var pendingQueue: [CTask] = [];

  init(modelContext: ModelContext, claudeController: ClaudeController, logManager: LogManager) {
    self.modelContext = modelContext;
    self.claudeController = claudeController;
    self.logManager = logManager;
    resetStuckTasks();
  }

  /// アプリ起動時に .running / .queued のまま残ったタスクをリセット
  private func resetStuckTasks() {
    let descriptor = FetchDescriptor<CTask>();
    guard let allTasks = try? modelContext.fetch(descriptor) else { return };
    for task in allTasks {
      if task.status == .running || task.status == .queued {
        task.status = .failed;
        task.errorMessage = "アプリ再起動により中断されました";
        task.updatedAt = Date();
        logManager.warning("中断タスクをリセットしました: \(task.title ?? task.prompt.prefix(30).description)", taskId: task.id);
      }
    }
  }

  func executeTask(_ task: CTask) async {
    if isExecuting {
      if !pendingQueue.contains(where: { $0.id == task.id }) {
        if pendingQueue.count >= Self.MAX_QUEUE_SIZE {
          task.status = .failed;
          task.errorMessage = "キューが満杯です（上限: \(Self.MAX_QUEUE_SIZE)件）";
          task.updatedAt = Date();
          logManager.warning("キュー上限に達しました（\(pendingQueue.count)件）", taskId: task.id);
          return;
        }
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

  func cancelCurrentTask() {
    isCancelled = true;
    logManager.info("タスクのキャンセルをリクエストしました");
  }

  private func runTask(_ task: CTask) async {
    isExecuting = true;
    isCancelled = false;

    guard !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      task.status = .failed;
      task.errorMessage = "プロンプトが空です";
      task.updatedAt = Date();
      logManager.error("空のプロンプトで実行が試みられました", taskId: task.id);
      isExecuting = false;
      return;
    }

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
