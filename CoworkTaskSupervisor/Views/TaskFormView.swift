import SwiftUI
import SwiftData

struct TaskFormView: View {
  @Environment(\.dismiss) private var dismiss;
  @Environment(\.modelContext) private var modelContext;

  var task: CTask?;

  @State private var title: String = "";
  @State private var prompt: String = "";
  @State private var comment: String = "";
  @State private var category: String = "";

  private var isEditing: Bool { task != nil }

  var body: some View {
    Form {
      Section("タイトル") {
        TextField("タスク名（任意）", text: $title)
      }

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
        title = task.title ?? "";
        prompt = task.prompt;
        comment = task.comment ?? "";
        category = task.category ?? "";
      }
    }
  }

  private func save() {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines);
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines);
    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines);
    let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines);

    if let task {
      task.title = trimmedTitle.isEmpty ? nil : trimmedTitle;
      task.prompt = trimmedPrompt;
      task.comment = trimmedComment.isEmpty ? nil : trimmedComment;
      task.category = trimmedCategory.isEmpty ? nil : trimmedCategory;
      task.updatedAt = Date();
    } else {
      var descriptor = FetchDescriptor<CTask>(sortBy: [SortDescriptor(\.order, order: .reverse)]);
      descriptor.fetchLimit = 1;
      let maxOrder = (try? modelContext.fetch(descriptor).first?.order) ?? -1;
      let newTask = CTask(
        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
        prompt: trimmedPrompt,
        comment: trimmedComment.isEmpty ? nil : trimmedComment,
        category: trimmedCategory.isEmpty ? nil : trimmedCategory,
        order: maxOrder + 1
      );
      modelContext.insert(newTask);
    }
  }
}
