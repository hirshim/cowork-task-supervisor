import SwiftUI
import SwiftData

struct TaskFormView: View {
  @Environment(\.dismiss) private var dismiss;
  @Environment(\.modelContext) private var modelContext;

  var task: CTask?;

  @State private var prompt: String = "";
  @State private var comment: String = "";
  @State private var category: String = "";

  private var isEditing: Bool { task != nil }

  var body: some View {
    Form {
      Section("プロンプト") {
        TextEditor(text: $prompt)
          .frame(minHeight: 100)
      }

      Section("メモ・備考") {
        TextEditor(text: $comment)
          .frame(minHeight: 60)
      }

      Section("カテゴリ") {
        TextField("カテゴリ名（任意）", text: $category)
      }
    }
    .padding()
    .frame(minWidth: 400, minHeight: 300)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("キャンセル") {
          dismiss();
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(isEditing ? "更新" : "作成") {
          save();
          dismiss();
        }
        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .onAppear {
      if let task {
        prompt = task.prompt;
        comment = task.comment ?? "";
        category = task.category ?? "";
      }
    }
  }

  private func save() {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines);
    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines);
    let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines);

    if let task {
      task.prompt = trimmedPrompt;
      task.comment = trimmedComment.isEmpty ? nil : trimmedComment;
      task.category = trimmedCategory.isEmpty ? nil : trimmedCategory;
      task.updatedAt = Date();
    } else {
      var descriptor = FetchDescriptor<CTask>(sortBy: [SortDescriptor(\.order, order: .reverse)]);
      descriptor.fetchLimit = 1;
      let maxOrder = (try? modelContext.fetch(descriptor).first?.order) ?? -1;
      let newTask = CTask(
        prompt: trimmedPrompt,
        comment: trimmedComment.isEmpty ? nil : trimmedComment,
        category: trimmedCategory.isEmpty ? nil : trimmedCategory,
        order: maxOrder + 1
      );
      modelContext.insert(newTask);
    }
  }
}
