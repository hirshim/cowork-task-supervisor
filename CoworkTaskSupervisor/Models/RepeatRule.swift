import Foundation

enum RepeatUnit: String, Codable, Equatable, CaseIterable {
  case hours, days, weeks, months, years

  var label: String {
    switch self {
    case .hours: return "時間";
    case .days: return "日";
    case .weeks: return "週";
    case .months: return "月";
    case .years: return "年";
    }
  }

  var calendarComponent: Calendar.Component {
    switch self {
    case .hours: return .hour;
    case .days: return .day;
    case .weeks: return .weekOfYear;
    case .months: return .month;
    case .years: return .year;
    }
  }
}

enum RepeatRule: Codable, Equatable {
  case daily(hour: Int, minute: Int)
  case weekly(dayOfWeek: Int, hour: Int, minute: Int)  // dayOfWeek: 1=日曜...7=土曜 (Calendar準拠)
  case monthly(day: Int, hour: Int, minute: Int)        // day: 1-31（末日超過時はクランプ）
  case yearly(month: Int, day: Int, hour: Int, minute: Int)  // month: 1-12, day: 1-31
  case custom(interval: Int, unit: RepeatUnit, hour: Int, minute: Int)
}
