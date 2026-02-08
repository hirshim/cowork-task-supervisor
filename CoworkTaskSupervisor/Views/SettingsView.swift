import SwiftUI

struct SettingsView: View {
  @AppStorage(AppSettingsKey.WORK_FOLDER_PATH) private var workFolderPath: String = "";

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
    }
    .formStyle(.grouped)
    .frame(width: 450, height: 200)
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
