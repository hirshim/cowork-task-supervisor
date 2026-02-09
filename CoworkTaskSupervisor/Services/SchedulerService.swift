import Foundation
import SwiftData

@MainActor
final class SchedulerService {
  private static let CHECK_INTERVAL: Duration = .seconds(30);

  private let modelContext: ModelContext;
  private let taskManager: TaskManager;
  private let logManager: LogManager;
  private var loopTask: Task<Void, Never>?;

  init(modelContext: ModelContext, taskManager: TaskManager, logManager: LogManager) {
    self.modelContext = modelContext;
    self.taskManager = taskManager;
    self.logManager = logManager;
  }

  func start() {
    loopTask = Task {
      checkScheduledTasks();
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.CHECK_INTERVAL);
        checkScheduledTasks();
      }
    };
    logManager.info("スケジューラを開始しました（間隔: 30秒）");
  }

  func stop() {
    loopTask?.cancel();
    loopTask = nil;
    logManager.info("スケジューラを停止しました");
  }

  private func checkScheduledTasks() {
    let now = Date();
    let descriptor = FetchDescriptor<CTask>();
    guard let tasks = try? modelContext.fetch(descriptor) else { return };

    let dueTasks = tasks.filter {
      guard let scheduledAt = $0.scheduledAt else { return false };
      return scheduledAt <= now
        && $0.status != .queued
        && $0.status != .running
        && $0.isAutoExecutionEnabled;
    };

    for task in dueTasks {
      if let rule = task.repeatRule {
        task.scheduledAt = calculateNextScheduledAt(from: task.scheduledAt!, rule: rule);
      } else {
        task.scheduledAt = nil;
      }
      task.updatedAt = Date();

      Task { [taskManager] in
        await taskManager.executeTask(task);
      };
      logManager.info("スケジュールタスクを実行キューに追加", taskId: task.id);
    }
  }

  func calculateNextScheduledAt(from baseDate: Date, rule: RepeatRule) -> Date {
    let calendar = Calendar.current;
    var next: Date;

    switch rule {
    case .daily(let hour, let minute):
      var components = calendar.dateComponents([.year, .month, .day], from: baseDate);
      components.hour = hour;
      components.minute = minute;
      components.second = 0;
      next = calendar.date(from: components) ?? baseDate;
      next = calendar.date(byAdding: .day, value: 1, to: next) ?? next;

    case .weekly(let dayOfWeek, let hour, let minute):
      // baseDate と同じ週の対象曜日を求め、1週間後を返す
      var components = calendar.dateComponents([.year, .month, .day], from: baseDate);
      components.hour = hour;
      components.minute = minute;
      components.second = 0;
      let base = calendar.date(from: components) ?? baseDate;
      let currentWeekday = calendar.component(.weekday, from: base);
      let diff = (dayOfWeek - currentWeekday + 7) % 7;
      let sameWeekTarget = calendar.date(byAdding: .day, value: diff, to: base) ?? base;
      next = calendar.date(byAdding: .weekOfYear, value: 1, to: sameWeekTarget) ?? sameWeekTarget;

    case .monthly(let day, let hour, let minute):
      var components = calendar.dateComponents([.year, .month], from: baseDate);
      let range = calendar.range(of: .day, in: .month, for: baseDate);
      let maxDay = range?.upperBound ?? 29;
      components.day = min(day, maxDay - 1);
      components.hour = hour;
      components.minute = minute;
      components.second = 0;
      next = calendar.date(from: components) ?? baseDate;
      next = calendar.date(byAdding: .month, value: 1, to: next) ?? next;

      // 翌月の末日にもクランプ
      if let nextRange = calendar.range(of: .day, in: .month, for: next) {
        let nextMaxDay = nextRange.upperBound - 1;
        if day > nextMaxDay {
          var nextComponents = calendar.dateComponents([.year, .month], from: next);
          nextComponents.day = nextMaxDay;
          nextComponents.hour = hour;
          nextComponents.minute = minute;
          nextComponents.second = 0;
          next = calendar.date(from: nextComponents) ?? next;
        }
      }

    case .yearly(let month, let day, let hour, let minute):
      var components = calendar.dateComponents([.year], from: baseDate);
      components.month = month;
      components.hour = hour;
      components.minute = minute;
      components.second = 0;
      // day=1 で対象月の日数レンジを取得し、クランプ（例: 非閏年の2月29日→28日）
      components.day = 1;
      let firstOfMonth = calendar.date(from: components) ?? baseDate;
      if let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
        components.day = min(day, range.upperBound - 1);
      } else {
        components.day = day;
      }
      next = calendar.date(from: components) ?? baseDate;
      next = calendar.date(byAdding: .year, value: 1, to: next) ?? next;

    case .custom(let interval, let unit, _, _):
      next = calendar.date(byAdding: unit.calendarComponent, value: interval, to: baseDate) ?? baseDate;
    }

    // 結果が過去なら未来になるまで進める
    let now = Date();
    while next <= now {
      switch rule {
      case .daily:
        next = calendar.date(byAdding: .day, value: 1, to: next) ?? next;
      case .weekly:
        next = calendar.date(byAdding: .weekOfYear, value: 1, to: next) ?? next;
      case .monthly(let day, let hour, let minute):
        // 翌月1日を基準にレンジ取得→元のdayでクランプ再構築（31日→28日→31日の再展開対応）
        var components = calendar.dateComponents([.year, .month], from: next);
        components.month = (components.month ?? 0) + 1;
        components.hour = hour;
        components.minute = minute;
        components.second = 0;
        components.day = 1;
        let firstOfMonth = calendar.date(from: components) ?? next;
        if let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
          components.day = min(day, range.upperBound - 1);
        } else {
          components.day = day;
        }
        next = calendar.date(from: components) ?? next;
      case .yearly(_, let day, let hour, let minute):
        // 翌年の同月1日を基準にレンジ取得→元のdayでクランプ再構築
        var components = calendar.dateComponents([.year, .month], from: next);
        components.year = (components.year ?? 0) + 1;
        components.hour = hour;
        components.minute = minute;
        components.second = 0;
        components.day = 1;
        let firstOfMonth = calendar.date(from: components) ?? next;
        if let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
          components.day = min(day, range.upperBound - 1);
        } else {
          components.day = day;
        }
        next = calendar.date(from: components) ?? next;
      case .custom(let interval, let unit, _, _):
        next = calendar.date(byAdding: unit.calendarComponent, value: interval, to: next) ?? next;
      }
    }

    return next;
  }
}
