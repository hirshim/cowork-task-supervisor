import SwiftUI

struct TaskDetailView: View {
  @Bindable var task: CTask;

  enum Field: Hashable {
    case title, prompt, comment, category
  }
  @FocusState private var focusedField: Field?;

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        headerSection
        if task.status == .running {
          runningIndicator
        }
        editableSection
        if task.status == .completed || task.status == .failed {
          resultSection
        }
      }
      .padding()
    }
    .frame(minWidth: 300)
  }

  private var headerSection: some View {
    HStack {
      Text(task.status.label)
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(task.status.color.opacity(0.2))
        .foregroundStyle(task.status.color)
        .clipShape(Capsule())
      if let category = task.category, !category.isEmpty {
        Text(category)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(.secondary.opacity(0.2))
          .clipShape(Capsule())
      }
      Spacer()
      if let executedAt = task.executedAt {
        Text("実行: \(executedAt.formatted())")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var runningIndicator: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("実行中...")
        .foregroundStyle(.secondary)
    }
  }

  private var editableSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("タイトル（任意）", text: optionalBinding(\.title))
        .font(.title2)
        .fontWeight(.semibold)
        .textFieldStyle(.plain)
        .focused($focusedField, equals: .title)

      Text("プロンプト")
        .font(.headline)
      TextEditor(text: $task.prompt)
        .frame(minHeight: 80)
        .lineSpacing(6)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .focused($focusedField, equals: .prompt)
        .onKeyPress(.tab) {
          focusedField = .comment;
          return .handled;
        }

      Text("メモ・備考")
        .font(.headline)
      TextEditor(text: optionalBinding(\.comment))
        .frame(minHeight: 50)
        .lineSpacing(4)
        .foregroundStyle(.secondary)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .focused($focusedField, equals: .comment)
        .onKeyPress(.tab) {
          focusedField = .category;
          return .handled;
        }

      HStack {
        Text("カテゴリ")
          .font(.headline)
        TextField("カテゴリ（任意）", text: optionalBinding(\.category))
          .textFieldStyle(.roundedBorder)
          .focused($focusedField, equals: .category)
      }
    }
    .disabled(task.status == .running)
  }

  private var resultSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let response = task.response, !response.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("応答")
            .font(.headline)
          Text(response)
            .textSelection(.enabled)
            .lineSpacing(4)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
      }
      if let errorMessage = task.errorMessage, !errorMessage.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("エラー")
            .font(.headline)
            .foregroundStyle(.red)
          Text(errorMessage)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func optionalBinding(_ keyPath: ReferenceWritableKeyPath<CTask, String?>) -> Binding<String> {
    Binding(
      get: { task[keyPath: keyPath] ?? "" },
      set: { task[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
    );
  }
}
