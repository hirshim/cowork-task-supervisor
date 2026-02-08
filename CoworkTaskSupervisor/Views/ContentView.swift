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
        VStack(spacing: 0) {
          detailToolbar
          Divider()
          if selectedSection == .tasks, let selectedTask {
            TaskDetailView(task: selectedTask)
          } else if selectedSection == .tasks {
            Spacer()
            Text("タスクを選択してください")
              .foregroundStyle(.secondary)
            Spacer()
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

  private func addTask() {
    var descriptor = FetchDescriptor<CTask>(sortBy: [SortDescriptor(\.order, order: .reverse)]);
    descriptor.fetchLimit = 1;
    let maxOrder = (try? modelContext.fetch(descriptor).first?.order) ?? -1;
    let newTask = CTask(prompt: "", order: maxOrder + 1);
    modelContext.insert(newTask);
    selectedTask = newTask;
  }

  private func executeTask(_ task: CTask) {
    guard let taskManager else { return };
    Task {
      await taskManager.executeTask(task);
    }
  }

  private func duplicateTask(_ task: CTask) {
    var descriptor = FetchDescriptor<CTask>(sortBy: [SortDescriptor(\.order, order: .reverse)]);
    descriptor.fetchLimit = 1;
    let maxOrder = (try? modelContext.fetch(descriptor).first?.order) ?? -1;
    let newTask = CTask(
      title: task.title,
      prompt: task.prompt,
      comment: task.comment,
      category: task.category,
      order: maxOrder + 1
    );
    modelContext.insert(newTask);
    selectedTask = newTask;
  }

  private func deleteTask(_ task: CTask) {
    if selectedTask == task {
      selectedTask = nil;
    }
    modelContext.delete(task);
  }

  private var detailToolbar: some View {
    HStack(spacing: 16) {
      Button(action: addTask) {
        Image(systemName: "plus")
          .font(.title3)
      }
      .disabled(selectedSection != .tasks)
      .keyboardShortcut("n", modifiers: .command)
      Button(action: { if let selectedTask { duplicateTask(selectedTask) } }) {
        Image(systemName: "doc.on.doc")
          .font(.title3)
      }
      .disabled(selectedTask == nil)
      Button(action: { if let selectedTask { deleteTask(selectedTask) } }) {
        Image(systemName: "trash")
          .font(.title3)
      }
      .disabled(selectedTask == nil)
      Spacer()
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
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
