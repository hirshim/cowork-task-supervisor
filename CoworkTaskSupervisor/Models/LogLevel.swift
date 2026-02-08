import Foundation
import SwiftUI

enum LogLevel: String, Codable, CaseIterable {
  case info
  case warning
  case error

  var label: String {
    switch self {
    case .info: "情報"
    case .warning: "警告"
    case .error: "エラー"
    }
  }

  var color: Color {
    switch self {
    case .info: .secondary
    case .warning: .orange
    case .error: .red
    }
  }
}
