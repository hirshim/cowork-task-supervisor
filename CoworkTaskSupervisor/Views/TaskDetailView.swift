import SwiftUI

struct TaskDetailView: View {
  let task: CTask;

  @EnvironmentObject private var accessibilityService: AccessibilityService;
  @State private var isEditingTask = false;

  var onExecute: ((CTask) -> Void)?;

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        headerSection
        executeSection
        promptSection
        if let comment = task.comment, !comment.isEmpty {
          commentSection(comment)
        }
        if task.status == .completed || task.status == .failed {
          resultSection
        }
      }
      .padding()
    }
    .frame(minWidth: 300)
    .toolbar {
      ToolbarItem {
        Button("編集") {
          isEditingTask = true;
        }
      }
    }
    .sheet(isPresented: $isEditingTask) {
      TaskFormView(task: task)
    }
  }

  private var executeSection: some View {
    Group {
      if task.status == .pending || task.status == .failed {
        Button(action: {
          onExecute?(task);
        }) {
          HStack {
            Image(systemName: "play.fill")
            Text("実行")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!accessibilityService.isAccessibilityGranted)
      } else if task.status == .running {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("実行中...")
            .foregroundStyle(.secondary)
        }
      }
    }
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
      if let category = task.category {
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

  private var promptSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("プロンプト")
        .font(.headline)
      Text(task.prompt)
        .textSelection(.enabled)
    }
  }

  private func commentSection(_ comment: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("メモ・備考")
        .font(.headline)
      Text(comment)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
  }

  private var resultSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let response = task.response, !response.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("応答")
            .font(.headline)
          Text(response)
            .textSelection(.enabled)
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
}
