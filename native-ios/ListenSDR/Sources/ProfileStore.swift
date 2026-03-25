import Foundation
import Combine
import Security

protocol ProfilePasswordStore {
  func password(for profileID: UUID) -> String?
  @discardableResult
  func store(password: String, for profileID: UUID) -> Bool
  @discardableResult
  func removePassword(for profileID: UUID) -> Bool
}

private final class KeychainProfilePasswordStore: ProfilePasswordStore {
  private let service = "ListenSDR.profile-passwords.v1"

  func password(for profileID: UUID) -> String? {
    var query = baseQuery(for: profileID)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard
      status == errSecSuccess,
      let data = item as? Data,
      let password = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return password
  }

  @discardableResult
  func store(password: String, for profileID: UUID) -> Bool {
    let data = Data(password.utf8)
    var addQuery = baseQuery(for: profileID)
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return true
    }
    guard addStatus == errSecDuplicateItem else {
      return false
    }

    let updateQuery = baseQuery(for: profileID)
    let attributesToUpdate = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
    return updateStatus == errSecSuccess
  }

  @discardableResult
  func removePassword(for profileID: UUID) -> Bool {
    let status = SecItemDelete(baseQuery(for: profileID) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private func baseQuery(for profileID: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: profileID.uuidString,
    ]
  }
}

@MainActor
final class ProfileStore: ObservableObject {
  @Published private(set) var profiles: [SDRConnectionProfile] = []
  @Published var selectedProfileID: UUID? {
    didSet { persistSelection() }
  }

  private let profilesKey = "ListenSDR.profiles.v1"
  private let selectedProfileKey = "ListenSDR.selectedProfile.v1"
  private let defaults: UserDefaults
  private let passwordStore: any ProfilePasswordStore

  init(
    defaults: UserDefaults = .standard,
    passwordStore: any ProfilePasswordStore = KeychainProfilePasswordStore()
  ) {
    self.defaults = defaults
    self.passwordStore = passwordStore
    load()
    if selectedProfileID == nil {
      selectedProfileID = profiles.first?.id
    }
  }

  var selectedProfile: SDRConnectionProfile? {
    guard let selectedProfileID else { return nil }
    return profiles.first(where: { $0.id == selectedProfileID })
  }

  func firstProfile(where predicate: (SDRConnectionProfile) -> Bool) -> SDRConnectionProfile? {
    profiles.first(where: predicate)
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
    _ = passwordStore.removePassword(for: profile.id)

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

  func matchingProfile(for profile: SDRConnectionProfile) -> SDRConnectionProfile? {
    guard let index = indexOfMatchingProfile(profile) else {
      return nil
    }
    return profiles[index]
  }

  private func load() {
    if let rawData = defaults.data(forKey: profilesKey),
       let decoded = try? JSONDecoder().decode([SDRConnectionProfile].self, from: rawData) {
      profiles = decoded.map { profile in
        if !profile.password.isEmpty {
          return profile
        }
        guard let storedPassword = passwordStore.password(for: profile.id) else {
          return profile
        }
        var hydrated = profile
        hydrated.password = storedPassword
        return hydrated
      }

      if migrateLegacyStoredPasswordsIfNeeded() {
        persistProfiles()
      }
    }

    if let selectedRaw = defaults.string(forKey: selectedProfileKey) {
      selectedProfileID = UUID(uuidString: selectedRaw)
    }
  }

  private func persistProfiles() {
    let persistedProfiles = profiles.map { profile -> SDRConnectionProfile in
      var persisted = profile
      if profile.password.isEmpty {
        _ = passwordStore.removePassword(for: profile.id)
        persisted.password = ""
        return persisted
      }

      if passwordStore.store(password: profile.password, for: profile.id) {
        persisted.password = ""
      }
      return persisted
    }

    guard let data = try? JSONEncoder().encode(persistedProfiles) else { return }
    defaults.set(data, forKey: profilesKey)
  }

  private func persistSelection() {
    defaults.set(selectedProfileID?.uuidString, forKey: selectedProfileKey)
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

  @discardableResult
  private func migrateLegacyStoredPasswordsIfNeeded() -> Bool {
    var migrated = false

    for index in profiles.indices {
      let profile = profiles[index]
      guard !profile.password.isEmpty else { continue }
      guard passwordStore.store(password: profile.password, for: profile.id) else { continue }
      migrated = true
    }

    return migrated
  }
}
