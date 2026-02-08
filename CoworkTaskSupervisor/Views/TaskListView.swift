import SwiftUI
import SwiftData

struct TaskListView: View {
  @Environment(\.modelContext) private var modelContext;
  @Query(sort: \CTask.order) private var tasks: [CTask];

  @Binding var selectedTask: CTask?;
  @State private var isAddingTask = false;
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
    .toolbar {
      ToolbarItem {
        Button(action: { isAddingTask = true }) {
          Label("追加", systemImage: "plus")
        }
      }
    }
    .sheet(isPresented: $isAddingTask) {
      TaskFormView()
    }
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
    VStack(alignment: .leading, spacing: 2) {
      Text(task.prompt)
        .lineLimit(2)
      HStack(spacing: 4) {
        Text(task.status.label)
          .font(.caption2)
          .foregroundStyle(task.status.color)
        if let category = task.category {
          Text(category)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func deleteTasks(at offsets: IndexSet) {
    for index in offsets {
      let task = filteredTasks[index];
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
