import Foundation

enum AutoExecutionMode: Codable, Equatable {
  case off
  case on
  case thisDeviceOnly(deviceId: String)
}
