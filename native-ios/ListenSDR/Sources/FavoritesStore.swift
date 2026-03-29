import Foundation

struct FavoriteReceiver: Identifiable, Codable, Hashable {
  let id: String
  let backend: SDRBackend
  let name: String
  let host: String
  let port: Int
  let useTLS: Bool
  let path: String
  let createdAt: Date

  var endpointDescription: String {
    let scheme = useTLS ? "https" : "http"
    let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
    return "\(scheme)://\(host):\(port)\(normalizedPath)"
  }
}

struct FavoriteStation: Identifiable, Codable, Hashable {
  let id: String
  let receiverID: String
  let receiverName: String
  let backend: SDRBackend
  let title: String
  let frequencyHz: Int
  let mode: DemodulationMode?
  let createdAt: Date
}

@MainActor
final class FavoritesStore: ObservableObject {
  @Published private(set) var favoriteReceivers: [FavoriteReceiver] = []
  @Published private(set) var favoriteStations: [FavoriteStation] = []

  private let favoriteReceiversKey = "ListenSDR.favoriteReceivers.v1"
  private let favoriteStationsKey = "ListenSDR.favoriteStations.v1"

  init() {
    load()
  }

  var favoriteReceiverIDs: Set<String> {
    Set(favoriteReceivers.map(\.id))
  }

  func isFavoriteReceiver(_ profile: SDRConnectionProfile) -> Bool {
    favoriteReceiverIDs.contains(ReceiverIdentity.key(for: profile))
  }

  func isFavoriteReceiver(_ entry: ReceiverDirectoryEntry) -> Bool {
    favoriteReceiverIDs.contains(ReceiverIdentity.key(for: entry))
  }

  func toggleReceiver(_ profile: SDRConnectionProfile) {
    let receiver = FavoriteReceiver(
      id: ReceiverIdentity.key(for: profile),
      backend: profile.backend,
      name: profile.name,
      host: profile.host.trimmingCharacters(in: .whitespacesAndNewlines),
      port: profile.port,
      useTLS: profile.useTLS,
      path: profile.normalizedPath,
      createdAt: Date()
    )
    toggleReceiver(receiver)
  }

  func toggleReceiver(_ entry: ReceiverDirectoryEntry) {
    let receiver = FavoriteReceiver(
      id: ReceiverIdentity.key(for: entry),
      backend: entry.backend,
      name: entry.name,
      host: entry.host,
      port: entry.port,
      useTLS: entry.useTLS,
      path: entry.path,
      createdAt: Date()
    )
    toggleReceiver(receiver)
  }

  func toggleStation(
    profile: SDRConnectionProfile,
    title: String,
    frequencyHz: Int,
    mode: DemodulationMode?
  ) {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeTitle = normalizedTitle.isEmpty ? profile.name : normalizedTitle
    let receiverID = ReceiverIdentity.key(for: profile)

    if let index = favoriteStations.firstIndex(where: {
      $0.receiverID == receiverID && $0.frequencyHz == frequencyHz && $0.mode == mode
    }) {
      favoriteStations.remove(at: index)
    } else {
      favoriteStations.insert(
        FavoriteStation(
          id: stationID(receiverID: receiverID, frequencyHz: frequencyHz, mode: mode),
          receiverID: receiverID,
          receiverName: profile.name,
          backend: profile.backend,
          title: safeTitle,
          frequencyHz: frequencyHz,
          mode: mode,
          createdAt: Date()
        ),
        at: 0
      )
      sortFavoriteStations()
    }
    persistStations()
  }

  func removeStation(_ station: FavoriteStation) {
    guard let index = favoriteStations.firstIndex(of: station) else { return }
    favoriteStations.remove(at: index)
    persistStations()
  }

  func stations(for profile: SDRConnectionProfile) -> [FavoriteStation] {
    let receiverID = ReceiverIdentity.key(for: profile)
    return favoriteStations.filter { $0.receiverID == receiverID }
  }

  func favoriteProfiles(in profiles: [SDRConnectionProfile]) -> [SDRConnectionProfile] {
    let byID = Dictionary(uniqueKeysWithValues: profiles.map { (ReceiverIdentity.key(for: $0), $0) })
    return favoriteReceivers.compactMap { byID[$0.id] }
  }

  func restoreBackup(
    favoriteReceivers restoredReceivers: [FavoriteReceiver],
    favoriteStations restoredStations: [FavoriteStation]
  ) {
    favoriteReceivers = restoredReceivers
    sortFavoriteReceivers()
    persistReceivers()

    favoriteStations = restoredStations
    sortFavoriteStations()
    persistStations()
  }

  private func toggleReceiver(_ receiver: FavoriteReceiver) {
    if let index = favoriteReceivers.firstIndex(where: { $0.id == receiver.id }) {
      favoriteReceivers.remove(at: index)
    } else {
      favoriteReceivers.insert(receiver, at: 0)
      sortFavoriteReceivers()
    }
    persistReceivers()
  }

  private func stationID(
    receiverID: String,
    frequencyHz: Int,
    mode: DemodulationMode?
  ) -> String {
    "\(receiverID)|\(frequencyHz)|\(mode?.rawValue ?? "none")"
  }

  private func sortFavoriteReceivers() {
    favoriteReceivers.sort {
      if $0.createdAt != $1.createdAt {
        return $0.createdAt > $1.createdAt
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func sortFavoriteStations() {
    favoriteStations.sort {
      if $0.createdAt != $1.createdAt {
        return $0.createdAt > $1.createdAt
      }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  private func load() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: favoriteReceiversKey),
      let decoded = try? JSONDecoder().decode([FavoriteReceiver].self, from: data) {
      favoriteReceivers = decoded
      sortFavoriteReceivers()
    }
    if let data = defaults.data(forKey: favoriteStationsKey),
      let decoded = try? JSONDecoder().decode([FavoriteStation].self, from: data) {
      favoriteStations = decoded
      sortFavoriteStations()
    }
  }

  private func persistReceivers() {
    guard let data = try? JSONEncoder().encode(favoriteReceivers) else { return }
    UserDefaults.standard.set(data, forKey: favoriteReceiversKey)
  }

  private func persistStations() {
    guard let data = try? JSONEncoder().encode(favoriteStations) else { return }
    UserDefaults.standard.set(data, forKey: favoriteStationsKey)
  }
}
