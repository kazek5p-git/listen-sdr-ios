import Foundation

struct SettingsBackupPayload: Codable, Equatable {
  static let currentSchemaVersion = 2

  var schemaVersion: Int = currentSchemaVersion
  var settings: RadioSessionSettings?
  var profiles: [SDRConnectionProfile]?
  var selectedProfileID: UUID?
  var favoriteReceivers: [FavoriteReceiver]?
  var favoriteStations: [FavoriteStation]?
  var recentReceivers: [RecentReceiverRecord]?
  var recentListening: [RecentListeningRecord]?
  var recentFrequencies: [RecentFrequencyRecord]?

  var hasAnyContent: Bool {
    settings != nil ||
      profiles != nil ||
      favoriteReceivers != nil ||
      favoriteStations != nil ||
      recentReceivers != nil ||
      recentListening != nil ||
      recentFrequencies != nil
  }
}

enum RadioSessionSettingsBackupCodec {
  static func encode(_ settings: RadioSessionSettings) throws -> Data {
    try encode(
      payload: SettingsBackupPayload(
        settings: settings,
        profiles: nil,
        selectedProfileID: nil,
        favoriteReceivers: nil,
        favoriteStations: nil,
        recentReceivers: nil,
        recentListening: nil,
        recentFrequencies: nil
      )
    )
  }

  static func decode(_ data: Data) throws -> RadioSessionSettings {
    let payload = try decodePayload(data)
    guard let settings = payload.settings else {
      throw backupError(code: 4, message: "The selected settings backup file does not include app settings.")
    }
    return settings
  }

  static func encode(payload: SettingsBackupPayload) throws -> Data {
    guard payload.hasAnyContent else {
      throw backupError(code: 5, message: "Choose at least one type of data to include in the backup.")
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payload)
    try validateBackupData(data)
    return data
  }

  static func decodePayload(_ data: Data) throws -> SettingsBackupPayload {
    try validateBackupData(data)

    let decoder = JSONDecoder()
    let topLevelKeys = backupTopLevelKeys(from: data)
    if topLevelKeys.contains(where: payloadFieldNames.contains) {
      let payload = try decoder.decode(SettingsBackupPayload.self, from: data)
      guard payload.hasAnyContent else {
        throw backupError(code: 6, message: "The selected settings backup file does not contain any data to restore.")
      }
      return payload
    }

    if topLevelKeys.isEmpty {
      throw backupError(code: 6, message: "The selected settings backup file does not contain any data to restore.")
    }

    let legacySettings = try decoder.decode(RadioSessionSettings.self, from: data)
    return SettingsBackupPayload(
      settings: legacySettings,
      profiles: nil,
      selectedProfileID: nil,
      favoriteReceivers: nil,
      favoriteStations: nil,
      recentReceivers: nil,
      recentListening: nil,
      recentFrequencies: nil
    )
  }

  static func validateBackupData(_ data: Data) throws {
    let hasMeaningfulContent: Bool
    if let text = String(data: data, encoding: .utf8) {
      hasMeaningfulContent = text.contains(where: { !$0.isWhitespace })
    } else {
      hasMeaningfulContent = !data.isEmpty
    }

    guard hasMeaningfulContent else {
      throw backupError(code: 3, message: "The selected settings backup file is empty.")
    }
  }

  private static func backupError(code: Int, message: String) -> NSError {
    NSError(
      domain: "ListenSDR.SettingsBackup",
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private static func backupTopLevelKeys(from data: Data) -> Set<String> {
    guard
      let jsonObject = try? JSONSerialization.jsonObject(with: data),
      let dictionary = jsonObject as? [String: Any]
    else {
      return []
    }
    return Set(dictionary.keys)
  }

  private static let payloadFieldNames: Set<String> = [
    "schemaVersion",
    "settings",
    "profiles",
    "selectedProfileID",
    "favoriteReceivers",
    "favoriteStations",
    "recentReceivers",
    "recentListening",
    "recentFrequencies",
  ]
}
