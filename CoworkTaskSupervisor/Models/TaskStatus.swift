import Foundation
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable {
  case pending
  case queued
  case running
  case completed
  case failed
  case cancelled

  var label: String {
    switch self {
    case .pending: "未実行"
    case .queued: "待機中"
    case .running: "実行中"
    case .completed: "完了"
    case .failed: "失敗"
    case .cancelled: "キャンセル"
    }
  }

  var color: Color {
    switch self {
    case .pending: .secondary
    case .queued: .blue
    case .running: .blue
    case .completed: .green
    case .failed: .red
    case .cancelled: .secondary
    }
  }
}
