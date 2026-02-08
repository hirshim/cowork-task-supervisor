import SwiftUI
import SwiftData

struct TaskListView: View {
  @Environment(\.modelContext) private var modelContext;
  @Query(sort: \CTask.order) private var tasks: [CTask];

  @EnvironmentObject private var accessibilityService: AccessibilityService;
  @Binding var selectedTask: CTask?;
  var onExecute: ((CTask) -> Void)?;
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
    List(selection: $selectedTask) {
      ForEach(filteredTasks) { task in
        taskRow(task)
          .tag(task)
      }
      .onDelete(perform: deleteTasks)
      .onMove(perform: moveTasks)
    }
  }

  private func taskRow(_ task: CTask) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(task.title ?? (task.prompt.isEmpty ? "新しいタスク" : task.prompt))
          .font(.body)
          .lineLimit(2)
          .lineSpacing(2)
          .foregroundStyle(task.prompt.isEmpty && task.title == nil ? .secondary : .primary)
        HStack(spacing: 4) {
          Text(task.status.label)
            .font(.caption)
            .foregroundStyle(task.status.color)
          if let category = task.category {
            Text(category)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
      if task.status != .running {
        Button(action: { onExecute?(task) }) {
          let canExecute = accessibilityService.isAccessibilityGranted && !task.prompt.isEmpty;
          Image(systemName: "play.circle.fill")
            .font(.title2)
            .foregroundStyle(canExecute ? .blue : .gray.opacity(0.4))
        }
        .buttonStyle(.borderless)
        .disabled(!accessibilityService.isAccessibilityGranted || task.prompt.isEmpty)
      } else {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.vertical, 2)
  }

  private func deleteTasks(at offsets: IndexSet) {
    let tasksToDelete = offsets.map { filteredTasks[$0] };
    for task in tasksToDelete {
      if selectedTask == task {
        selectedTask = nil;
      }
      modelContext.delete(task);
    }
  }

  private func moveTasks(from source: IndexSet, to destination: Int) {
    var reordered = filteredTasks;
    reordered.move(fromOffsets: source, toOffset: destination);
    for (index, task) in reordered.enumerated() {
      task.order = index;
      task.updatedAt = Date();
    }
  }
}
