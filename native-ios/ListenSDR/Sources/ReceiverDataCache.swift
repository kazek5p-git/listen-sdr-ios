import Foundation

struct ChannelScannerResult: Identifiable, Codable, Equatable, Hashable {
  let id: String
  let name: String
  let frequencyHz: Int
  let mode: DemodulationMode?
  let signal: Double
  let signalUnit: String
  let detectedAt: Date
}

struct CachedReceiverData: Codable {
  var openWebRXProfiles: [OpenWebRXProfileOption]
  var selectedOpenWebRXProfileID: String?
  var lastOpenWebRXBookmark: SDRServerBookmark?
  var serverBookmarks: [SDRServerBookmark]
  var openWebRXBandPlan: [SDRBandPlanEntry]
  var savedChannelScannerResults: [ChannelScannerResult]
  var fmdxServerPresets: [SDRServerBookmark]
  var fmdxCapabilities: FMDXCapabilities?
  var fmdxSavedScanResults: [FMDXBandScanResult]
  var savedAt: Date

  static let empty = CachedReceiverData(
    openWebRXProfiles: [],
    selectedOpenWebRXProfileID: nil,
    lastOpenWebRXBookmark: nil,
    serverBookmarks: [],
    openWebRXBandPlan: [],
    savedChannelScannerResults: [],
    fmdxServerPresets: [],
    fmdxCapabilities: nil,
    fmdxSavedScanResults: [],
    savedAt: .distantPast
  )

  private enum CodingKeys: String, CodingKey {
    case openWebRXProfiles
    case selectedOpenWebRXProfileID
    case lastOpenWebRXBookmark
    case serverBookmarks
    case openWebRXBandPlan
    case savedChannelScannerResults
    case fmdxServerPresets
    case fmdxCapabilities
    case fmdxSavedScanResults
    case savedAt
  }

  init(
    openWebRXProfiles: [OpenWebRXProfileOption],
    selectedOpenWebRXProfileID: String?,
    lastOpenWebRXBookmark: SDRServerBookmark?,
    serverBookmarks: [SDRServerBookmark],
    openWebRXBandPlan: [SDRBandPlanEntry],
    savedChannelScannerResults: [ChannelScannerResult],
    fmdxServerPresets: [SDRServerBookmark],
    fmdxCapabilities: FMDXCapabilities?,
    fmdxSavedScanResults: [FMDXBandScanResult],
    savedAt: Date
  ) {
    self.openWebRXProfiles = openWebRXProfiles
    self.selectedOpenWebRXProfileID = selectedOpenWebRXProfileID
    self.lastOpenWebRXBookmark = lastOpenWebRXBookmark
    self.serverBookmarks = serverBookmarks
    self.openWebRXBandPlan = openWebRXBandPlan
    self.savedChannelScannerResults = savedChannelScannerResults
    self.fmdxServerPresets = fmdxServerPresets
    self.fmdxCapabilities = fmdxCapabilities
    self.fmdxSavedScanResults = fmdxSavedScanResults
    self.savedAt = savedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    openWebRXProfiles = try container.decodeIfPresent([OpenWebRXProfileOption].self, forKey: .openWebRXProfiles) ?? []
    selectedOpenWebRXProfileID = try container.decodeIfPresent(String.self, forKey: .selectedOpenWebRXProfileID)
    lastOpenWebRXBookmark = try container.decodeIfPresent(SDRServerBookmark.self, forKey: .lastOpenWebRXBookmark)
    serverBookmarks = try container.decodeIfPresent([SDRServerBookmark].self, forKey: .serverBookmarks) ?? []
    openWebRXBandPlan = try container.decodeIfPresent([SDRBandPlanEntry].self, forKey: .openWebRXBandPlan) ?? []
    savedChannelScannerResults =
      try container.decodeIfPresent([ChannelScannerResult].self, forKey: .savedChannelScannerResults) ?? []
    fmdxServerPresets = try container.decodeIfPresent([SDRServerBookmark].self, forKey: .fmdxServerPresets) ?? []
    fmdxCapabilities = try container.decodeIfPresent(FMDXCapabilities.self, forKey: .fmdxCapabilities)
    fmdxSavedScanResults = try container.decodeIfPresent([FMDXBandScanResult].self, forKey: .fmdxSavedScanResults) ?? []
    savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
  }
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
