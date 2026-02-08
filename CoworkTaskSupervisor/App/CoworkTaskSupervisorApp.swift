import SwiftUI
import SwiftData

@main
struct CoworkTaskSupervisorApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(for: [CTask.self, AppLog.self])
    .commands {
      CommandGroup(replacing: .newItem) {}
    }

    Settings {
      SettingsView()
    }
  }
}
