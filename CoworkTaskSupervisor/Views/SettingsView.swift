import SwiftUI

struct SettingsView: View {
  @AppStorage(AppSettingsKey.WORK_FOLDER_PATH) private var workFolderPath: String = "";
  @AppStorage(AppSettingsKey.RESPONSE_TIMEOUT_SECONDS) private var responseTimeoutSeconds: Int = 300;

  var body: some View {
    Form {
      Section("作業フォルダ") {
        HStack {
          Text(workFolderPath.isEmpty ? "未設定" : workFolderPath)
            .foregroundStyle(workFolderPath.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("選択…") {
            selectFolder();
          }
        }
        if !workFolderPath.isEmpty {
          Button("クリア", role: .destructive) {
            workFolderPath = "";
          }
        }
      }
      Section("応答タイムアウト") {
        HStack {
          TextField("秒", value: $responseTimeoutSeconds, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
          Text("秒（デフォルト: 300）")
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 450, height: 250)
  }

  private func selectFolder() {
    let panel = NSOpenPanel();
    panel.canChooseDirectories = true;
    panel.canChooseFiles = false;
    panel.allowsMultipleSelection = false;
    panel.message = "Claude for Mac の作業フォルダを選択してください";
    if panel.runModal() == .OK, let url = panel.url {
      workFolderPath = url.path(percentEncoded: false);
    }
  }
}
