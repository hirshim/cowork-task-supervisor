import SwiftUI
import SwiftData

enum SidebarSection: Hashable {
  case tasks
  case logs
}

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext;
  @State private var selectedTask: CTask?;
  @State private var selectedSection: SidebarSection? = .tasks;
  @StateObject private var accessibilityService = AccessibilityService();
  @State private var taskManager: TaskManager?;

  var body: some View {
    VStack(spacing: 0) {
      if !accessibilityService.isAccessibilityGranted {
        accessibilityBanner
      }
      NavigationSplitView {
        List(selection: $selectedSection) {
          NavigationLink(value: SidebarSection.tasks) {
            Label("タスク", systemImage: "checklist")
          }
          NavigationLink(value: SidebarSection.logs) {
            Label("ログ", systemImage: "doc.text")
          }
        }
        .navigationTitle("メニュー")
      } content: {
        switch selectedSection {
        case .tasks:
          TaskListView(selectedTask: $selectedTask, onExecute: executeTask)
        case .logs:
          LogListView()
        case nil:
          Text("セクションを選択してください")
            .foregroundStyle(.secondary)
        }
      } detail: {
        Group {
          if selectedSection == .tasks, let selectedTask {
            TaskDetailView(task: selectedTask, onExecute: executeTask)
          } else if selectedSection == .tasks {
            Text("タスクを選択してください")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .frame(minWidth: 700, minHeight: 400)
    .environmentObject(accessibilityService)
    .onAppear {
      setupServices();
    }
    .onChange(of: selectedSection) {
      selectedTask = nil;
    }
  }

  private func setupServices() {
    guard taskManager == nil else { return };
    let log = LogManager(modelContext: modelContext);
    let claude = ClaudeController(logManager: log, accessibilityService: accessibilityService);
    let manager = TaskManager(modelContext: modelContext, claudeController: claude, logManager: log);
    self.taskManager = manager;
  }

  private func executeTask(_ task: CTask) {
    guard let taskManager else { return };
    Task {
      await taskManager.executeTask(task);
    }
  }

  private var accessibilityBanner: some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text("アクセシビリティ権限が必要です。Claude for Macを制御するには権限を付与してください。")
        .font(.callout)
      Spacer()
      Button("権限を付与") {
        accessibilityService.requestAccessibility();
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.orange.opacity(0.1))
  }
}
