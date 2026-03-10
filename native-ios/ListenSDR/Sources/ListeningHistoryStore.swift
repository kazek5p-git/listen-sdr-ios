import Foundation

struct RecentReceiverRecord: Identifiable, Codable, Hashable {
  let id: String
  let receiverName: String
  let backend: SDRBackend
  let host: String
  let port: Int
  let useTLS: Bool
  let path: String
  let username: String
  let password: String
  let lastUsedAt: Date

  func makeProfile() -> SDRConnectionProfile {
    SDRConnectionProfile(
      name: receiverName,
      backend: backend,
      host: host,
      port: port,
      useTLS: useTLS,
      path: path,
      username: username,
      password: password
    )
  }
}

struct RecentListeningRecord: Identifiable, Codable, Hashable {
  let id: String
  let receiverID: String
  let receiverName: String
  let backend: SDRBackend
  let host: String
  let port: Int
  let useTLS: Bool
  let path: String
  let username: String
  let password: String
  let frequencyHz: Int
  let mode: DemodulationMode?
  let stationTitle: String?
  let lastHeardAt: Date

  var primaryTitle: String {
    if let stationTitle, !stationTitle.isEmpty {
      return stationTitle
    }
    return FrequencyFormatter.mhzText(fromHz: frequencyHz)
  }

  func makeProfile() -> SDRConnectionProfile {
    SDRConnectionProfile(
      name: receiverName,
      backend: backend,
      host: host,
      port: port,
      useTLS: useTLS,
      path: path,
      username: username,
      password: password
    )
  }
}

@MainActor
final class ListeningHistoryStore: ObservableObject {
  static let shared = ListeningHistoryStore()

  @Published private(set) var recentReceivers: [RecentReceiverRecord] = []
  @Published private(set) var recentListening: [RecentListeningRecord] = []

  private let recentReceiversKey = "ListenSDR.history.recentReceivers.v1"
  private let recentListeningKey = "ListenSDR.history.recentListening.v1"
  private let maxRecentReceivers = 50
  private let maxRecentListening = 150

  private init() {
    load()
  }

  func recordReceiver(_ profile: SDRConnectionProfile) {
    let record = RecentReceiverRecord(
      id: ReceiverIdentity.key(for: profile),
      receiverName: profile.name,
      backend: profile.backend,
      host: profile.host.trimmingCharacters(in: .whitespacesAndNewlines),
      port: profile.port,
      useTLS: profile.useTLS,
      path: profile.normalizedPath,
      username: profile.username,
      password: profile.password,
      lastUsedAt: Date()
    )

    recentReceivers.removeAll { $0.id == record.id }
    recentReceivers.insert(record, at: 0)
    if recentReceivers.count > maxRecentReceivers {
      recentReceivers = Array(recentReceivers.prefix(maxRecentReceivers))
    }
    persistReceivers()
  }

  func recordListening(
    profile: SDRConnectionProfile,
    frequencyHz: Int,
    mode: DemodulationMode?,
    stationTitle: String?
  ) {
    let receiverID = ReceiverIdentity.key(for: profile)
    let normalizedStationTitle = normalizedTitle(stationTitle)
    let entryID = listeningRecordID(receiverID: receiverID, frequencyHz: frequencyHz, mode: mode)
    let record = RecentListeningRecord(
      id: entryID,
      receiverID: receiverID,
      receiverName: profile.name,
      backend: profile.backend,
      host: profile.host.trimmingCharacters(in: .whitespacesAndNewlines),
      port: profile.port,
      useTLS: profile.useTLS,
      path: profile.normalizedPath,
      username: profile.username,
      password: profile.password,
      frequencyHz: frequencyHz,
      mode: mode,
      stationTitle: normalizedStationTitle,
      lastHeardAt: Date()
    )

    if let index = recentListening.firstIndex(where: { $0.id == entryID }) {
      let existing = recentListening.remove(at: index)
      recentListening.insert(
        RecentListeningRecord(
          id: record.id,
          receiverID: record.receiverID,
          receiverName: record.receiverName,
          backend: record.backend,
          host: record.host,
          port: record.port,
          useTLS: record.useTLS,
          path: record.path,
          username: record.username,
          password: record.password,
          frequencyHz: record.frequencyHz,
          mode: record.mode,
          stationTitle: normalizedStationTitle ?? existing.stationTitle,
          lastHeardAt: record.lastHeardAt
        ),
        at: 0
      )
    } else {
      recentListening.insert(record, at: 0)
    }

    if recentListening.count > maxRecentListening {
      recentListening = Array(recentListening.prefix(maxRecentListening))
    }
    persistListening()
  }

  func removeRecentReceiver(_ record: RecentReceiverRecord) {
    recentReceivers.removeAll { $0.id == record.id }
    persistReceivers()
  }

  func removeRecentListening(_ record: RecentListeningRecord) {
    recentListening.removeAll { $0.id == record.id }
    persistListening()
  }

  func clearRecentReceivers() {
    recentReceivers = []
    persistReceivers()
  }

  func clearRecentListening() {
    recentListening = []
    persistListening()
  }

  private func normalizedTitle(_ value: String?) -> String? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return normalized.isEmpty ? nil : normalized
  }

  private func listeningRecordID(
    receiverID: String,
    frequencyHz: Int,
    mode: DemodulationMode?
  ) -> String {
    "\(receiverID)|\(frequencyHz)|\(mode?.rawValue ?? "none")"
  }

  private func load() {
    let defaults = UserDefaults.standard

    if let data = defaults.data(forKey: recentReceiversKey),
      let decoded = try? JSONDecoder().decode([RecentReceiverRecord].self, from: data) {
      recentReceivers = decoded
    }

    if let data = defaults.data(forKey: recentListeningKey),
      let decoded = try? JSONDecoder().decode([RecentListeningRecord].self, from: data) {
      recentListening = decoded
    }
  }

  private func persistReceivers() {
    guard let data = try? JSONEncoder().encode(recentReceivers) else { return }
    UserDefaults.standard.set(data, forKey: recentReceiversKey)
  }

  private func persistListening() {
    guard let data = try? JSONEncoder().encode(recentListening) else { return }
    UserDefaults.standard.set(data, forKey: recentListeningKey)
  }
}
