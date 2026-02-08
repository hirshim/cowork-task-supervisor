import Foundation
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable {
  case pending
  case running
  case completed
  case failed

  var label: String {
    switch self {
    case .pending: "未実行"
    case .running: "実行中"
    case .completed: "完了"
    case .failed: "失敗"
    }
  }

  var color: Color {
    switch self {
    case .pending: .secondary
    case .running: .blue
    case .completed: .green
    case .failed: .red
    }
  }
}
