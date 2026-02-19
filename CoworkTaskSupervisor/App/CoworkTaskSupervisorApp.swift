import SwiftUI
import SwiftData

@main
struct CoworkTaskSupervisorApp: App {
  let modelContainer: ModelContainer;

  init() {
    let cloudConfig = ModelConfiguration(
      "CloudStore",
      schema: Schema([CTask.self]),
      cloudKitDatabase: .automatic
    );
    let localConfig = ModelConfiguration(
      "LocalStore",
      schema: Schema([AppLog.self])
    );
    do {
      modelContainer = try ModelContainer(
        for: CTask.self, AppLog.self,
        configurations: cloudConfig, localConfig
      );
    } catch {
      fatalError("ModelContainer の初期化に失敗しました: \(error)");
    }

    migrateFromLegacyStoreIfNeeded();
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(modelContainer)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }

    Settings {
      SettingsView()
    }
  }

  /// 旧 default.store から CloudStore/LocalStore へデータを移行する（一度きり）
  private func migrateFromLegacyStoreIfNeeded() {
    let migrationKey = "legacyStoreMigrated";
    guard !UserDefaults.standard.bool(forKey: migrationKey) else { return };

    let legacyURL = URL.applicationSupportDirectory.appendingPathComponent("default.store");
    guard FileManager.default.fileExists(atPath: legacyURL.path) else {
      UserDefaults.standard.set(true, forKey: migrationKey);
      return;
    };

    do {
      let legacyConfig = ModelConfiguration(
        url: legacyURL,
        cloudKitDatabase: .none
      );
      let legacyContainer = try ModelContainer(
        for: CTask.self, AppLog.self,
        configurations: legacyConfig
      );
      let legacyContext = ModelContext(legacyContainer);
      let newContext = ModelContext(modelContainer);

      // CTask の移行
      let tasks = try legacyContext.fetch(FetchDescriptor<CTask>());
      for task in tasks {
        let newTask = CTask(
          title: task.title,
          prompt: task.prompt,
          comment: task.comment,
          category: task.category,
          order: task.order,
          scheduledAt: task.scheduledAt,
          repeatRule: task.repeatRule,
          autoExecution: task.autoExecution
        );
        newTask.id = task.id;
        newTask.status = task.status;
        newTask.response = task.response;
        newTask.errorMessage = task.errorMessage;
        newTask.createdAt = task.createdAt;
        newTask.updatedAt = task.updatedAt;
        newTask.executedAt = task.executedAt;
        newContext.insert(newTask);
      };

      // AppLog の移行
      let logs = try legacyContext.fetch(FetchDescriptor<AppLog>());
      for log in logs {
        let newLog = AppLog(message: log.message, level: log.level, taskId: log.taskId);
        newLog.id = log.id;
        newLog.createdAt = log.createdAt;
        newContext.insert(newLog);
      };

      try newContext.save();
      UserDefaults.standard.set(true, forKey: migrationKey);
      print("旧ストアから移行完了: CTask \(tasks.count)件, AppLog \(logs.count)件");
    } catch {
      print("旧ストアからの移行に失敗: \(error)");
    };
  }
}
