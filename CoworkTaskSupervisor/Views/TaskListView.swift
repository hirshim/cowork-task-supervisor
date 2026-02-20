import SwiftUI
import SwiftData

struct TaskListView: View {
  @Environment(\.modelContext) private var modelContext;
  @Environment(\.undoManager) private var undoManager;
  @Query(sort: \CTask.order) private var tasks: [CTask];

  @EnvironmentObject private var accessibilityService: AccessibilityService;
  @Binding var selectedTask: CTask?;
  var onExecute: ((CTask) -> Void)?;
  var onCancel: ((CTask) -> Void)?;
  @State private var selectedCategory: String? = nil;

  private var categories: [String] {
    let allCategories = tasks.compactMap(\.category);
    return Array(Set(allCategories)).sorted();
  }

  private var filteredTasks: [CTask] {
    if let selectedCategory {
      return tasks.filter { $0.category == selectedCategory };
    }
    return tasks;
  }

  var body: some View {
    VStack(spacing: 0) {
      categoryFilter
      taskList
    }
    .navigationTitle("タスク")
  }

  private var categoryFilter: some View {
    Group {
      if !categories.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 4) {
            FilterChip(label: "すべて", isSelected: selectedCategory == nil) {
              selectedCategory = nil;
            }
            ForEach(categories, id: \.self) { category in
              FilterChip(label: category, isSelected: selectedCategory == category) {
                selectedCategory = category;
              }
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
        }
        Divider()
      }
    }
  }

  private var taskList: some View {
    Group {
      if tasks.isEmpty {
        ContentUnavailableView("タスクがありません", systemImage: "checklist", description: Text("＋ボタンまたは ⌘N で新規タスクを作成"))
      } else if filteredTasks.isEmpty {
        ContentUnavailableView("一致するタスクがありません", systemImage: "line.3.horizontal.decrease.circle", description: Text("フィルタ条件に一致するタスクがありません"))
      } else {
        List(selection: $selectedTask) {
          ForEach(filteredTasks) { task in
            taskRow(task)
              .tag(task)
          }
          .onMove(perform: moveTasks)
        }
      }
    }
  }

  private func taskRow(_ task: CTask) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        if let category = task.category {
          Text(category)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(task.title ?? (task.prompt.isEmpty ? "新しいタスク" : task.prompt))
          .font(.body)
          .lineLimit(2)
          .lineSpacing(2)
          .foregroundStyle(task.prompt.isEmpty && task.title == nil ? .secondary : .primary)
        HStack(spacing: 4) {
          if task.status == .queued || task.status == .running || task.status == .failed || task.status == .cancelled {
            Text(task.status.label)
              .font(.caption)
              .foregroundStyle(task.status.color)
          }
          if case .on = task.autoExecution {
            Image(systemName: "bolt.fill")
              .font(.caption)
              .foregroundStyle(.blue)
          } else if case .thisDeviceOnly = task.autoExecution {
            Image(systemName: "bolt.fill")
              .font(.caption)
              .foregroundStyle(.purple)
          }
          if task.scheduledAt != nil {
            Image(systemName: "clock")
              .font(.caption)
              .foregroundStyle(.orange)
          }
          if task.repeatRule != nil {
            Image(systemName: "repeat")
              .font(.caption)
              .foregroundStyle(.teal)
          }
          if let scheduledAt = task.scheduledAt {
            Text(scheduledAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute()))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
      if task.status == .running {
        HStack(spacing: 4) {
          ProgressView()
            .controlSize(.small)
          Button(action: { onCancel?(task) }) {
            Image(systemName: "stop.circle.fill")
              .font(.title3)
              .foregroundStyle(.red.opacity(0.7))
          }
          .buttonStyle(.borderless)
          .help("応答完了後にキャンセルされます")
        }
      } else if task.status == .queued {
        ProgressView()
          .controlSize(.small)
      } else {
        Button(action: { onExecute?(task) }) {
          let canExecute = accessibilityService.isAccessibilityGranted && !task.prompt.isEmpty;
          Image(systemName: "play.circle.fill")
            .font(.title3)
            .foregroundStyle(canExecute ? .blue : .gray.opacity(0.4))
        }
        .buttonStyle(.borderless)
        .disabled(!accessibilityService.isAccessibilityGranted || task.prompt.isEmpty)
      }
    }
    .padding(.vertical, 2)
  }

  private func deleteTasks(at offsets: IndexSet) {
    let tasksToDelete = offsets.map { filteredTasks[$0] };
    let snapshots = tasksToDelete.map { $0.snapshot() };
    for task in tasksToDelete {
      if selectedTask == task {
        selectedTask = nil;
      }
      modelContext.delete(task);
    }
    undoManager?.registerUndo(withTarget: modelContext) { ctx in
      for snap in snapshots {
        ctx.insert(CTask.restore(from: snap));
      }
    };
  }

  private func moveTasks(from source: IndexSet, to destination: Int) {
    var reordered = filteredTasks;
    reordered.move(fromOffsets: source, toOffset: destination);

    if selectedCategory != nil {
      // フィルタ中: 全タスクの相対順序を維持しつつ、フィルタ内の順序を反映
      var iter = reordered.makeIterator();
      var merged: [CTask] = [];
      for task in tasks {
        if task.category == selectedCategory {
          if let next = iter.next() {
            merged.append(next);
          }
        } else {
          merged.append(task);
        }
      }
      for (index, task) in merged.enumerated() {
        task.order = index;
        task.updatedAt = Date();
      }
    } else {
      for (index, task) in reordered.enumerated() {
        task.order = index;
        task.updatedAt = Date();
      }
    }
  }
}
