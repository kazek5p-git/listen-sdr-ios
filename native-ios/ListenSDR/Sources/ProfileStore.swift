import Foundation
import Combine

@MainActor
final class ProfileStore: ObservableObject {
  @Published private(set) var profiles: [SDRConnectionProfile] = []
  @Published var selectedProfileID: UUID? {
    didSet { persistSelection() }
  }

  private let profilesKey = "ListenSDR.profiles.v1"
  private let selectedProfileKey = "ListenSDR.selectedProfile.v1"

  init() {
    load()
    if selectedProfileID == nil {
      selectedProfileID = profiles.first?.id
    }
  }

  var selectedProfile: SDRConnectionProfile? {
    guard let selectedProfileID else { return nil }
    return profiles.first(where: { $0.id == selectedProfileID })
  }

  func upsert(_ profile: SDRConnectionProfile) {
    if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
      profiles[index] = profile
    } else {
      profiles.append(profile)
    }

    profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    if selectedProfileID == nil {
      selectedProfileID = profile.id
    }

    persistProfiles()
  }

  func delete(_ profile: SDRConnectionProfile) {
    guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    profiles.remove(at: index)

    if selectedProfileID == profile.id {
      selectedProfileID = profiles.first?.id
    }

    persistProfiles()
  }

  func updateSelection(_ id: UUID?) {
    selectedProfileID = id
  }

  func upsertImportedProfile(_ profile: SDRConnectionProfile) -> SDRConnectionProfile {
    if let existingIndex = indexOfMatchingProfile(profile) {
      return profiles[existingIndex]
    }

    profiles.append(profile)
    profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    if selectedProfileID == nil {
      selectedProfileID = profile.id
    }

    persistProfiles()
    return profile
  }

  func hasMatchingProfile(_ profile: SDRConnectionProfile) -> Bool {
    indexOfMatchingProfile(profile) != nil
  }

  private func load() {
    let defaults = UserDefaults.standard

    if let rawData = defaults.data(forKey: profilesKey),
       let decoded = try? JSONDecoder().decode([SDRConnectionProfile].self, from: rawData) {
      profiles = decoded
    }

    if let selectedRaw = defaults.string(forKey: selectedProfileKey) {
      selectedProfileID = UUID(uuidString: selectedRaw)
    }
  }

  private func persistProfiles() {
    guard let data = try? JSONEncoder().encode(profiles) else { return }
    UserDefaults.standard.set(data, forKey: profilesKey)
  }

  private func persistSelection() {
    UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: selectedProfileKey)
  }

  private func indexOfMatchingProfile(_ profile: SDRConnectionProfile) -> Int? {
    let normalizedHost = profile.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedPath = profile.normalizedPath.lowercased()

    return profiles.firstIndex { existing in
      existing.backend == profile.backend &&
      existing.useTLS == profile.useTLS &&
      existing.port == profile.port &&
      existing.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedHost &&
      existing.normalizedPath.lowercased() == normalizedPath
    }
  }
}
