import Foundation

struct CachedReceiverData: Codable {
  var openWebRXProfiles: [OpenWebRXProfileOption]
  var selectedOpenWebRXProfileID: String?
  var serverBookmarks: [SDRServerBookmark]
  var openWebRXBandPlan: [SDRBandPlanEntry]
  var fmdxServerPresets: [SDRServerBookmark]
  var savedAt: Date

  static let empty = CachedReceiverData(
    openWebRXProfiles: [],
    selectedOpenWebRXProfileID: nil,
    serverBookmarks: [],
    openWebRXBandPlan: [],
    fmdxServerPresets: [],
    savedAt: .distantPast
  )
}

@MainActor
final class ReceiverDataCache {
  static let shared = ReceiverDataCache()

  private let storageKey = "ListenSDR.receiverDataCache.v1"
  private var storage: [String: CachedReceiverData] = [:]

  private init() {
    load()
  }

  func cachedData(for receiverID: String) -> CachedReceiverData? {
    storage[receiverID]
  }

  func update(receiverID: String, mutate: (inout CachedReceiverData) -> Void) {
    var value = storage[receiverID] ?? .empty
    mutate(&value)
    value.savedAt = Date()
    storage[receiverID] = value
    persist()
  }

  private func load() {
    guard
      let data = UserDefaults.standard.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([String: CachedReceiverData].self, from: data)
    else {
      return
    }
    storage = decoded
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(storage) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }
}
