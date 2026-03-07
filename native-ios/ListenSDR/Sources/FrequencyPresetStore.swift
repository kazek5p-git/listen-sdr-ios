import Foundation
import Combine

struct FrequencyPreset: Identifiable, Codable, Equatable {
  var id: UUID
  var name: String
  var frequencyHz: Int
  var mode: DemodulationMode
  var profileID: UUID?
  var profileName: String?
  var createdAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    frequencyHz: Int,
    mode: DemodulationMode,
    profileID: UUID? = nil,
    profileName: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.frequencyHz = frequencyHz
    self.mode = mode
    self.profileID = profileID
    self.profileName = profileName
    self.createdAt = createdAt
  }
}

@MainActor
final class FrequencyPresetStore: ObservableObject {
  @Published private(set) var presets: [FrequencyPreset] = []
  private let defaultsKey = "ListenSDR.frequencyPresets.v1"

  init() {
    load()
  }

  func addPreset(
    name: String,
    frequencyHz: Int,
    mode: DemodulationMode,
    profileID: UUID?,
    profileName: String?
  ) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName = trimmed.isEmpty ? defaultName(for: frequencyHz, mode: mode) : trimmed
    let preset = FrequencyPreset(
      name: resolvedName,
      frequencyHz: frequencyHz,
      mode: mode,
      profileID: profileID,
      profileName: profileName
    )
    presets.insert(preset, at: 0)
    persist()
  }

  func removePreset(_ preset: FrequencyPreset) {
    presets.removeAll { $0.id == preset.id }
    persist()
  }

  func defaultName(for frequencyHz: Int, mode: DemodulationMode) -> String {
    "\(FrequencyFormatter.mhzText(fromHz: frequencyHz)) \(mode.displayName)"
  }

  func presets(for profileID: UUID?) -> [FrequencyPreset] {
    presets.filter { preset in
      preset.profileID == nil || preset.profileID == profileID
    }
  }

  private func load() {
    guard let raw = UserDefaults.standard.data(forKey: defaultsKey),
      let decoded = try? JSONDecoder().decode([FrequencyPreset].self, from: raw)
    else {
      presets = []
      return
    }

    presets = decoded.sorted { $0.createdAt > $1.createdAt }
  }

  private func persist() {
    guard let encoded = try? JSONEncoder().encode(presets) else { return }
    UserDefaults.standard.set(encoded, forKey: defaultsKey)
  }
}
