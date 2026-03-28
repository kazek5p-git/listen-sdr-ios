import Foundation

enum RadioSessionSettingsBackupCodec {
  static func encode(_ settings: RadioSessionSettings) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(settings)
  }

  static func decode(_ data: Data) throws -> RadioSessionSettings {
    try JSONDecoder().decode(RadioSessionSettings.self, from: data)
  }
}
