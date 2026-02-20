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
        scheduleSection
        editableSection
        if task.status == .completed || task.status == .failed || task.status == .cancelled {
          resultSection
        }
      }
      .padding()
    }
    .frame(minWidth: 300)
  }

  private var headerSection: some View {
    HStack {
      if task.status == .completed || task.status == .failed || task.status == .cancelled {
        Text(task.status.label)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(task.status.color.opacity(0.2))
          .foregroundStyle(task.status.color)
          .clipShape(Capsule())
      }
      if let executedAt = task.executedAt {
        Text("実行: \(executedAt.formatted())")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var editableSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("タイトル（任意）", text: optionalBinding(\.title))
          .font(.title2)
          .fontWeight(.semibold)
          .textFieldStyle(.plain)
          .focused($focusedField, equals: .title)
          .padding(8)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(.secondary.opacity(0.1))
          )
        TextField("カテゴリ（任意）", text: optionalBinding(\.category))
          .font(.callout)
          .textFieldStyle(.roundedBorder)
          .focused($focusedField, equals: .category)
          .frame(width: 120)
        if task.status == .pending {
          Text(task.status.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(task.status.color.opacity(0.2))
            .foregroundStyle(task.status.color)
            .clipShape(Capsule())
        }
      }

      Text("プロンプト")
        .font(.headline)
      ZStack(alignment: .topLeading) {
        if task.prompt.isEmpty {
          Text("プロンプトを入力")
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
        }
        TextEditor(text: $task.prompt)
          .font(.body)
          .lineSpacing(6)
          .scrollContentBackground(.hidden)
          .contentMargins(.top, 8, for: .scrollContent)
          .focused($focusedField, equals: .prompt)
      }
      .frame(minHeight: 80)
      .padding(8)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(.secondary.opacity(0.1))
      )

      Text("メモ")
        .font(.headline)
      ZStack(alignment: .topLeading) {
        if (task.comment ?? "").isEmpty {
          Text("メモ（任意）")
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
        }
        TextEditor(text: optionalBinding(\.comment))
          .font(.body)
          .lineSpacing(4)
          .foregroundStyle(.secondary)
          .scrollContentBackground(.hidden)
          .contentMargins(.top, 8, for: .scrollContent)
          .focused($focusedField, equals: .comment)
      }
      .frame(minHeight: 60)
      .padding(8)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(.secondary.opacity(0.1))
      )
    }
    .disabled(task.status == .queued || task.status == .running)
  }

  // MARK: - スケジュール

  private enum RepeatType: Hashable {
    case none, daily, weekly, monthly, yearly, custom
  }

  private static let WEEKDAY_LABELS = ["日", "月", "火", "水", "木", "金", "土"];
  private static let MONTH_LABELS = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"];
  private static let DEFAULT_HOUR = 9;

  // MARK: Binding ヘルパー

  private var scheduleEnabledBinding: Binding<Bool> {
    Binding(
      get: { task.scheduledAt != nil },
      set: { enabled in
        if enabled {
          let calendar = Calendar.current;
          let now = Date();
          let today9am = calendar.date(bySettingHour: Self.DEFAULT_HOUR, minute: 0, second: 0, of: now)!;
          task.scheduledAt = now < today9am ? today9am : calendar.date(byAdding: .day, value: 1, to: today9am);
          task.updatedAt = Date();
        } else {
          task.scheduledAt = nil;
          task.repeatRule = nil;
          task.autoExecution = nil;
          task.updatedAt = Date();
        }
      }
    );
  }

  private var dateOnlyBinding: Binding<Date> {
    Binding(
      get: { task.scheduledAt ?? Date() },
      set: { newDate in
        let calendar = Calendar.current;
        let oldDate = task.scheduledAt ?? Date();
        let hour = calendar.component(.hour, from: oldDate);
        let minute = calendar.component(.minute, from: oldDate);
        var components = calendar.dateComponents([.year, .month, .day], from: newDate);
        components.hour = hour;
        components.minute = minute;
        components.second = 0;
        task.scheduledAt = calendar.date(from: components) ?? newDate;
        task.updatedAt = Date();
      }
    );
  }

  private var timeBinding: Binding<Date> {
    Binding(
      get: { task.scheduledAt ?? Date() },
      set: { newDate in
        let calendar = Calendar.current;
        let oldDate = task.scheduledAt ?? Date();
        let hour = calendar.component(.hour, from: newDate);
        let minute = calendar.component(.minute, from: newDate);
        var components = calendar.dateComponents([.year, .month, .day], from: oldDate);
        components.hour = hour;
        components.minute = minute;
        components.second = 0;
        task.scheduledAt = calendar.date(from: components) ?? newDate;
        syncRepeatRuleTime(hour: hour, minute: minute);
        task.updatedAt = Date();
      }
    );
  }

  private func syncRepeatRuleTime(hour: Int, minute: Int) {
    guard let rule = task.repeatRule else { return };
    switch rule {
    case .daily:
      task.repeatRule = .daily(hour: hour, minute: minute);
    case .weekly(let dayOfWeek, _, _):
      task.repeatRule = .weekly(dayOfWeek: dayOfWeek, hour: hour, minute: minute);
    case .monthly(let day, _, _):
      task.repeatRule = .monthly(day: day, hour: hour, minute: minute);
    case .yearly(let month, let day, _, _):
      task.repeatRule = .yearly(month: month, day: day, hour: hour, minute: minute);
    case .custom(let interval, let unit, _, _):
      task.repeatRule = .custom(interval: interval, unit: unit, hour: hour, minute: minute);
    }
  }

  private var repeatTypeBinding: Binding<RepeatType> {
    Binding(
      get: {
        guard let rule = task.repeatRule else { return .none };
        switch rule {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .custom: return .custom
        }
      },
      set: { newType in
        let calendar = Calendar.current;
        let date = task.scheduledAt ?? Date();
        let hour = calendar.component(.hour, from: date);
        let minute = calendar.component(.minute, from: date);
        switch newType {
        case .none:
          task.repeatRule = nil;
        case .daily:
          task.repeatRule = .daily(hour: hour, minute: minute);
        case .weekly:
          let dayOfWeek = calendar.component(.weekday, from: date);
          task.repeatRule = .weekly(dayOfWeek: dayOfWeek, hour: hour, minute: minute);
        case .monthly:
          let day = calendar.component(.day, from: date);
          task.repeatRule = .monthly(day: day, hour: hour, minute: minute);
        case .yearly:
          let month = calendar.component(.month, from: date);
          let day = calendar.component(.day, from: date);
          task.repeatRule = .yearly(month: month, day: day, hour: hour, minute: minute);
        case .custom:
          task.repeatRule = .custom(interval: 1, unit: .days, hour: hour, minute: minute);
        }
        task.updatedAt = Date();
      }
    );
  }

  private var weekdayBinding: Binding<Int> {
    Binding(
      get: {
        if case .weekly(let dayOfWeek, _, _) = task.repeatRule {
          return dayOfWeek;
        }
        return Calendar.current.component(.weekday, from: Date());
      },
      set: { newDay in
        if case .weekly(_, let hour, let minute) = task.repeatRule {
          task.repeatRule = .weekly(dayOfWeek: newDay, hour: hour, minute: minute);
          task.updatedAt = Date();
        }
      }
    );
  }

  private var monthDayBinding: Binding<Int> {
    Binding(
      get: {
        if case .monthly(let day, _, _) = task.repeatRule {
          return day;
        }
        return Calendar.current.component(.day, from: Date());
      },
      set: { newDay in
        if case .monthly(_, let hour, let minute) = task.repeatRule {
          task.repeatRule = .monthly(day: newDay, hour: hour, minute: minute);
          task.updatedAt = Date();
        }
      }
    );
  }

  private var yearlyMonthBinding: Binding<Int> {
    Binding(
      get: {
        if case .yearly(let month, _, _, _) = task.repeatRule {
          return month;
        }
        return Calendar.current.component(.month, from: Date());
      },
      set: { newMonth in
        if case .yearly(_, let day, let hour, let minute) = task.repeatRule {
          task.repeatRule = .yearly(month: newMonth, day: day, hour: hour, minute: minute);
          task.updatedAt = Date();
        }
      }
    );
  }

  private var yearlyDayBinding: Binding<Int> {
    Binding(
      get: {
        if case .yearly(_, let day, _, _) = task.repeatRule {
          return day;
        }
        return Calendar.current.component(.day, from: Date());
      },
      set: { newDay in
        if case .yearly(let month, _, let hour, let minute) = task.repeatRule {
          task.repeatRule = .yearly(month: month, day: newDay, hour: hour, minute: minute);
          task.updatedAt = Date();
        }
      }
    );
  }

  private var customIntervalBinding: Binding<Int> {
    Binding(
      get: {
        if case .custom(let interval, _, _, _) = task.repeatRule {
          return interval;
        }
        return 1;
      },
      set: { newInterval in
        if case .custom(_, let unit, let hour, let minute) = task.repeatRule {
          task.repeatRule = .custom(interval: max(1, newInterval), unit: unit, hour: hour, minute: minute);
          task.updatedAt = Date();
        }
      }
    );
  }

  private var customUnitBinding: Binding<RepeatUnit> {
    Binding(
      get: {
        if case .custom(_, let unit, _, _) = task.repeatRule {
          return unit;
        }
        return .days;
      },
      set: { newUnit in
        if case .custom(let interval, _, let hour, let minute) = task.repeatRule {
          task.repeatRule = .custom(interval: interval, unit: newUnit, hour: hour, minute: minute);
          task.updatedAt = Date();
        }
      }
    );
  }

  // MARK: scheduleSection

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Toggle(isOn: scheduleEnabledBinding) {
          Label("スケジュール", systemImage: "calendar")
            .font(.headline)
        }
        if task.scheduledAt != nil {
          DatePicker(
            "日付",
            selection: dateOnlyBinding,
            in: Calendar.current.startOfDay(for: Date())...,
            displayedComponents: [.date]
          )
          .labelsHidden()
          DatePicker(
            "時刻",
            selection: timeBinding,
            displayedComponents: [.hourAndMinute]
          )
          .labelsHidden()
          Picker(selection: repeatTypeBinding) {
            Text("なし").tag(RepeatType.none);
            Text("毎日").tag(RepeatType.daily);
            Text("毎週").tag(RepeatType.weekly);
            Text("毎月").tag(RepeatType.monthly);
            Text("毎年").tag(RepeatType.yearly);
            Text("カスタム").tag(RepeatType.custom);
          } label: {
            Label("繰り返し", systemImage: "repeat")
          }
          if case .weekly = task.repeatRule {
            Picker("曜日", selection: weekdayBinding) {
              ForEach(1...7, id: \.self) { day in
                Text(Self.WEEKDAY_LABELS[day - 1]).tag(day);
              }
            }
          }
          if case .monthly = task.repeatRule {
            Picker("日", selection: monthDayBinding) {
              ForEach(1...31, id: \.self) { day in
                Text("\(day)日").tag(day);
              }
            }
          }
          if case .yearly = task.repeatRule {
            Picker("月", selection: yearlyMonthBinding) {
              ForEach(1...12, id: \.self) { month in
                Text(Self.MONTH_LABELS[month - 1]).tag(month);
              }
            }
            Picker("日", selection: yearlyDayBinding) {
              ForEach(1...31, id: \.self) { day in
                Text("\(day)日").tag(day);
              }
            }
          }
          if case .custom = task.repeatRule {
            Stepper(value: customIntervalBinding, in: 1...999) {
              Text("\(customIntervalBinding.wrappedValue)")
            }
            Picker("単位", selection: customUnitBinding) {
              ForEach(RepeatUnit.allCases, id: \.self) { unit in
                Text(unit.label).tag(unit);
              }
            }
          }
        }
      }
      if task.scheduledAt != nil && !task.isAutoExecutionEnabled {
        Label("自動実行がオフのため、スケジュール到来時に自動実行されません", systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .disabled(task.status == .queued || task.status == .running)
  }

  // MARK: - 結果表示

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

