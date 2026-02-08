import SwiftUI
import SwiftData

struct LogListView: View {
  @Query(sort: \AppLog.createdAt, order: .reverse) private var logs: [AppLog];
  @State private var selectedLevel: LogLevel? = nil;

  private var filteredLogs: [AppLog] {
    if let selectedLevel {
      return logs.filter { $0.level == selectedLevel };
    }
    return logs;
  }

  var body: some View {
    VStack(spacing: 0) {
      levelFilter
      logList
    }
    .navigationTitle("ログ")
  }

  private var levelFilter: some View {
    HStack(spacing: 4) {
      FilterChip(label: "すべて", isSelected: selectedLevel == nil) {
        selectedLevel = nil;
      }
      ForEach(LogLevel.allCases, id: \.self) { level in
        FilterChip(label: level.label, isSelected: selectedLevel == level) {
          selectedLevel = level;
        }
      }
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  private var logList: some View {
    List {
      ForEach(filteredLogs) { log in
        logRow(log)
      }
    }
  }

  private func logRow(_ log: AppLog) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(log.level.label)
          .font(.caption2)
          .foregroundStyle(log.level.color)
        Text(log.createdAt.formatted(date: .abbreviated, time: .standard))
          .font(.caption2)
          .foregroundStyle(.secondary)
        if log.taskId != nil {
          Image(systemName: "link")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Text(log.message)
        .font(.callout)
        .lineLimit(3)
    }
  }
}
