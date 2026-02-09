import Foundation

enum DeviceIdentifier {
  static var current: String {
    if let id = UserDefaults.standard.string(forKey: AppSettingsKey.DEVICE_ID) {
      return id;
    }
    let id = UUID().uuidString;
    UserDefaults.standard.set(id, forKey: AppSettingsKey.DEVICE_ID);
    return id;
  }
}
