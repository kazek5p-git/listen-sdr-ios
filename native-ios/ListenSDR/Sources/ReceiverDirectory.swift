import Foundation
import Combine
import ListenSDRCore

enum ReceiverDirectoryStatus: String, Codable, CaseIterable {
  case available
  case limited
  case unreachable
  case unknown

  var displayName: String {
    switch self {
    case .available:
      return L10n.text("directory.status.available")
    case .limited:
      return L10n.text("directory.status.limited")
    case .unreachable:
      return L10n.text("directory.status.unreachable")
    case .unknown:
      return L10n.text("directory.status.unknown")
    }
  }

  var sortRank: Int {
    switch self {
    case .available:
      return 0
    case .limited:
      return 1
    case .unknown:
      return 2
    case .unreachable:
      return 3
    }
  }
}

enum ReceiverDirectoryStatusFilter: String, CaseIterable, Identifiable {
  case all
  case online
  case availableOnly
  case unavailable

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all:
      return L10n.text("directory.filter.status.all")
    case .online:
      return L10n.text("directory.filter.status.online")
    case .availableOnly:
      return L10n.text("directory.filter.status.available_only")
    case .unavailable:
      return L10n.text("directory.filter.status.unavailable")
    }
  }
}

enum ReceiverDirectoryCountrySortOption: String, CaseIterable, Identifiable {
  case alphabetical
  case receiverCount

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .alphabetical:
      return L10n.text("directory.country_sort.alphabetical")
    case .receiverCount:
      return L10n.text("directory.country_sort.receiver_count")
    }
  }
}

enum ReceiverDirectorySortOption: String, CaseIterable, Identifiable {
  case recommended
  case name
  case location
  case status
  case source

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .recommended:
      return L10n.text("directory.sort.recommended")
    case .name:
      return L10n.text("directory.sort.name")
    case .location:
      return L10n.text("directory.sort.location")
    case .status:
      return L10n.text("directory.sort.status")
    case .source:
      return L10n.text("directory.sort.source")
    }
  }
}

struct ReceiverDirectoryCountryOption: Identifiable, Hashable {
  let countryLabel: String
  let receiverCount: Int

  var id: String { countryLabel }
}

struct ReceiverDirectoryEntry: Identifiable, Codable, Hashable {
  let id: String
  let backend: SDRBackend
  let name: String
  let host: String
  let port: Int
  let path: String
  let useTLS: Bool
  let endpointURL: String
  let sourceName: String
  let status: ReceiverDirectoryStatus
  let cityLabel: String?
  let countryLabel: String?
  let locationLabel: String?
  let softwareVersion: String?
  let latitude: Double?
  let longitude: Double?

  var endpointDescription: String {
    "\(useTLS ? "https" : "http")://\(host):\(port)\(path)"
  }

  var detailText: String {
    var parts: [String] = [sourceName]
    if let locationLabel, !locationLabel.isEmpty {
      parts.append(locationLabel)
    }
    if let softwareVersion, !softwareVersion.isEmpty {
      parts.append("v\(softwareVersion)")
    }
    return parts.joined(separator: " | ")
  }

  func makeProfile() -> SDRConnectionProfile {
    SDRConnectionProfile(
      name: name,
      backend: backend,
      host: host,
      port: port,
      useTLS: useTLS,
      path: path
    )
  }

  func withStatus(_ updatedStatus: ReceiverDirectoryStatus) -> ReceiverDirectoryEntry {
    ReceiverDirectoryEntry(
      id: id,
      backend: backend,
      name: name,
      host: host,
      port: port,
      path: path,
      useTLS: useTLS,
      endpointURL: endpointURL,
      sourceName: sourceName,
      status: updatedStatus,
      cityLabel: cityLabel,
      countryLabel: countryLabel,
      locationLabel: locationLabel,
      softwareVersion: softwareVersion,
      latitude: latitude,
      longitude: longitude
    )
  }
}

private typealias ReceiverCountryResolver = ListenSDRCore.ReceiverCountryResolver

private typealias DirectoryEndpoint = ListenSDRCore.ReceiverDirectoryEndpoint
private typealias SharedDirectorySelectionEntry = ListenSDRCore.SharedReceiverDirectoryEntry
private typealias SharedDirectoryStatusFilter = ListenSDRCore.SharedReceiverDirectoryStatusFilter
private typealias SharedDirectoryCountrySortOption = ListenSDRCore.SharedReceiverDirectoryCountrySortOption
private typealias SharedDirectorySortOption = ListenSDRCore.SharedReceiverDirectorySortOption
private typealias SharedDirectoryCountryOption = ListenSDRCore.SharedReceiverDirectoryCountryOption

private struct FMDXDirectoryResponse: Decodable {
  let dataset: [FMDXDirectoryRow]
}

private struct FMDXDirectoryRow: Decodable {
  let name: String?
  let tuner: String?
  let version: String?
  let city: String?
  let country: String?
  let countryName: String?
  let url: String?
  let status: Int?
}

private struct ReceiverbookMapRow: Decodable {
  let label: String?
  let location: ReceiverbookLocation?
  let receivers: [ReceiverbookReceiver]
}

private struct ReceiverbookLocation: Decodable {
  let coordinates: [Double]
}

private struct ReceiverbookReceiver: Decodable {
  let label: String?
  let version: String?
  let url: String?
  let type: String?
}

actor ReceiverDirectoryService {
  private let session: URLSession = .shared
  private let maxProbeConcurrency = 16
  private let probeTimeoutSeconds: TimeInterval = 4.0

  func fetchAllEntries() async throws -> [ReceiverDirectoryEntry] {
    async let fmdxEntries = fetchFMDXEntries()
    async let kiwiEntries = fetchReceiverbookEntries(type: "kiwisdr", backend: .kiwiSDR)
    async let openWebRXEntries = fetchReceiverbookEntries(type: "openwebrx", backend: .openWebRX)

    let fmdx = try await fmdxEntries
    let kiwi = try await kiwiEntries
    let openWebRX = try await openWebRXEntries
    let merged = fmdx + kiwi + openWebRX
    return deduplicatedAndSorted(merged)
  }

  func probeStatuses(
    for entries: [ReceiverDirectoryEntry],
    backend: SDRBackend
  ) async -> [String: ReceiverDirectoryStatus] {
    guard backend == .kiwiSDR || backend == .openWebRX else {
      return [:]
    }

    let targets = entries.filter { $0.backend == backend }
    guard !targets.isEmpty else {
      return [:]
    }

    var results: [String: ReceiverDirectoryStatus] = [:]
    results.reserveCapacity(targets.count)

    await withTaskGroup(of: (String, ReceiverDirectoryStatus).self) { group in
      var iterator = targets.makeIterator()

      for _ in 0..<min(maxProbeConcurrency, targets.count) {
        guard let entry = iterator.next() else { break }
        group.addTask { [self] in
          let status = await self.probeEntry(entry)
          return (entry.id, status)
        }
      }

      while let (entryID, status) = await group.next() {
        results[entryID] = status
        if let nextEntry = iterator.next() {
          group.addTask { [self] in
            let status = await self.probeEntry(nextEntry)
            return (nextEntry.id, status)
          }
        }
      }
    }

    return results
  }

  private func fetchFMDXEntries() async throws -> [ReceiverDirectoryEntry] {
    let url = try requiredURL("https://servers.fmdx.org/api/")
    let data = try await fetchData(from: url)
    let response = try JSONDecoder().decode(FMDXDirectoryResponse.self, from: data)

    var entries: [ReceiverDirectoryEntry] = []
    entries.reserveCapacity(response.dataset.count)

    for row in response.dataset {
      guard let rowURL = row.url, let endpoint = parseEndpoint(from: rowURL) else {
        continue
      }

      let trimmedName = row.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let displayName = trimmedName.isEmpty ? endpoint.host : trimmedName
      let city = normalizedLabel(row.city)
      let country = ReceiverCountryResolver.normalizedCountryLabel(
        countryCode: row.country,
        countryName: row.countryName
      )
      let location = locationLabel(city: city, country: country)
      let status = fmdxStatus(from: row.status)

      let entry = ReceiverDirectoryEntry(
        id: entryID(backend: .fmDxWebserver, endpoint: endpoint),
        backend: .fmDxWebserver,
        name: displayName,
        host: endpoint.host,
        port: endpoint.port,
        path: endpoint.path,
        useTLS: endpoint.useTLS,
        endpointURL: endpoint.absoluteURL,
        sourceName: "FMDX.org",
        status: status,
        cityLabel: city,
        countryLabel: country,
        locationLabel: location,
        softwareVersion: row.version,
        latitude: nil,
        longitude: nil
      )
      entries.append(entry)
    }

    return entries
  }

  private func fetchReceiverbookEntries(
    type: String,
    backend: SDRBackend
  ) async throws -> [ReceiverDirectoryEntry] {
    let url = try requiredURL("https://www.receiverbook.de/map?type=\(type)")
    let htmlData = try await fetchData(from: url)
    guard let html = String(data: htmlData, encoding: .utf8) else {
      throw SDRClientError.unsupported("Receiverbook returned invalid map page encoding.")
    }

    let jsonText = try extractReceiverbookJSON(from: html)
    let rows = try JSONDecoder().decode([ReceiverbookMapRow].self, from: Data(jsonText.utf8))

    var entries: [ReceiverDirectoryEntry] = []
    for row in rows {
      let groupLabel = row.label?.trimmingCharacters(in: .whitespacesAndNewlines)
      let coordinates = row.location?.coordinates ?? []
      let longitude = coordinates.count > 0 ? coordinates[0] : nil
      let latitude = coordinates.count > 1 ? coordinates[1] : nil

      for receiver in row.receivers {
        guard
          let rowType = receiver.type?.lowercased(),
          matchesReceiverbookType(rowType, backend: backend),
          let receiverURL = receiver.url,
          let endpoint = parseEndpoint(from: receiverURL)
        else {
          continue
        }

        let nameCandidate = receiver.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (nameCandidate?.isEmpty == false ? nameCandidate : groupLabel) ?? endpoint.host
        let country = ReceiverCountryResolver.inferredCountryLabel(
          locationLabel: groupLabel,
          host: endpoint.host
        )

        let entry = ReceiverDirectoryEntry(
          id: entryID(backend: backend, endpoint: endpoint),
          backend: backend,
          name: displayName,
          host: endpoint.host,
          port: endpoint.port,
          path: endpoint.path,
          useTLS: endpoint.useTLS,
          endpointURL: endpoint.absoluteURL,
          sourceName: "Receiverbook.de",
          status: .unknown,
          cityLabel: nil,
          countryLabel: country,
          locationLabel: groupLabel,
          softwareVersion: receiver.version,
          latitude: latitude,
          longitude: longitude
        )
        entries.append(entry)
      }
    }

    return entries
  }

  private func fetchData(from url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.applyListenSDRNetworkIdentity()
    let (data, response) = try await session.data(for: request)

    guard
      let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw SDRClientError.unsupported("Directory source is currently unavailable: \(url.host ?? "unknown host").")
    }

    return data
  }

  private func requiredURL(_ raw: String) throws -> URL {
    guard let url = URL(string: raw) else {
      throw SDRClientError.invalidURL
    }
    return url
  }

  private func extractReceiverbookJSON(from html: String) throws -> String {
    do {
      return try ReceiverDirectoryParsingCore.extractReceiverbookJSON(from: html)
    } catch let error as ReceiverDirectoryParsingCoreError {
      throw SDRClientError.unsupported(error.localizedDescription)
    }
  }

  private func parseEndpoint(from raw: String) -> DirectoryEndpoint? {
    ReceiverDirectoryParsingCore.parseEndpoint(from: raw)
  }

  private func entryID(backend: SDRBackend, endpoint: DirectoryEndpoint) -> String {
    ReceiverIdentity.key(
      backend: backend,
      host: endpoint.host,
      port: endpoint.port,
      useTLS: endpoint.useTLS,
      path: endpoint.path
    )
  }

  private func locationLabel(city: String?, country: String?) -> String? {
    let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let trimmedCountry = country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if !trimmedCity.isEmpty && !trimmedCountry.isEmpty {
      return "\(trimmedCity), \(trimmedCountry)"
    }
    if !trimmedCity.isEmpty {
      return trimmedCity
    }
    if !trimmedCountry.isEmpty {
      return trimmedCountry
    }
    return nil
  }

  private func normalizedLabel(_ value: String?) -> String? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return normalized.isEmpty ? nil : normalized
  }

  private func fmdxStatus(from raw: Int?) -> ReceiverDirectoryStatus {
    ReceiverDirectoryStatus(sharedStatus: ReceiverDirectoryParsingCore.fmdxStatus(from: raw))
  }

  private func matchesReceiverbookType(_ value: String, backend: SDRBackend) -> Bool {
    ReceiverDirectoryParsingCore.matchesReceiverbookType(value, backend: backend)
  }

  private func deduplicatedAndSorted(_ entries: [ReceiverDirectoryEntry]) -> [ReceiverDirectoryEntry] {
    materializedDirectoryEntries(
      from: ReceiverDirectorySelectionCore.deduplicatedAndSorted(
        entries.map(\.sharedSelectionEntry)
      ),
      sourceEntries: entries
    )
  }

  private func probeEntry(_ entry: ReceiverDirectoryEntry) async -> ReceiverDirectoryStatus {
    guard let url = URL(string: entry.endpointURL) else {
      return .unknown
    }

    let headStatus = await probe(url: url, method: "HEAD")
    switch headStatus {
    case .available, .limited:
      return headStatus
    case .unknown:
      break
    case .unreachable:
      break
    }

    let fallbackStatus = await probe(url: url, method: "GET")
    if fallbackStatus != .unknown {
      return fallbackStatus
    }

    return headStatus
  }

  private func probe(url: URL, method: String) async -> ReceiverDirectoryStatus {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = probeTimeoutSeconds
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.applyListenSDRNetworkIdentity()
    if method == "GET" {
      request.setValue("bytes=0-1024", forHTTPHeaderField: "Range")
    }

    do {
      let (_, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return .unknown
      }
      return mapProbeStatus(from: httpResponse.statusCode)
    } catch {
      return .unreachable
    }
  }

  private func mapProbeStatus(from statusCode: Int) -> ReceiverDirectoryStatus {
    ReceiverDirectoryStatus(sharedStatus: ReceiverDirectoryParsingCore.mapProbeStatus(from: statusCode))
  }
}

private extension ReceiverDirectoryStatus {
  var sharedStatus: SharedReceiverDirectoryStatus {
    switch self {
    case .available:
      return .available
    case .limited:
      return .limited
    case .unreachable:
      return .unreachable
    case .unknown:
      return .unknown
    }
  }

  init(sharedStatus: SharedReceiverDirectoryStatus) {
    switch sharedStatus {
    case .available:
      self = .available
    case .limited:
      self = .limited
    case .unreachable:
      self = .unreachable
    case .unknown:
      self = .unknown
    }
  }
}

@MainActor
final class ReceiverDirectoryViewModel: ObservableObject {
  static let cacheEntriesKey = "ListenSDR.directory.entries.v1"
  static let cacheRefreshDateKey = "ListenSDR.directory.refreshDate.v1"

  @Published var selectedBackend: SDRBackend = .fmDxWebserver
  @Published var searchText: String = ""
  @Published var statusFilter: ReceiverDirectoryStatusFilter = .all
  @Published var sortOption: ReceiverDirectorySortOption = .recommended
  @Published var countrySortOption: ReceiverDirectoryCountrySortOption = .alphabetical
  @Published var selectedCountry: String = ""
  @Published var favoritesOnly = false
  @Published private(set) var entries: [ReceiverDirectoryEntry] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isProbingStatus = false
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isUsingCachedData = false
  @Published private(set) var refreshResultMessage: String?

  let supportedBackends: [SDRBackend] = [.fmDxWebserver, .kiwiSDR, .openWebRX]

  private let service: ReceiverDirectoryService
  private let notificationService: DirectoryChangeNotificationService
  private let defaults: UserDefaults
  private let requestNotificationAuthorization: Bool
  private var autoRefreshTask: Task<Void, Never>?
  private var statusProbeTask: Task<Void, Never>?
  private var lastProbeDateByBackend: [SDRBackend: Date] = [:]

  private let refreshIntervalSeconds: UInt64 = 900
  private let staleAfterSeconds: TimeInterval = 900
  private let statusProbeIntervalSeconds: TimeInterval = 1_800

  init(
    service: ReceiverDirectoryService = ReceiverDirectoryService(),
    notificationService: DirectoryChangeNotificationService? = nil,
    defaults: UserDefaults = .standard,
    requestNotificationAuthorization: Bool = true
  ) {
    self.service = service
    self.notificationService = notificationService ?? .shared
    self.defaults = defaults
    self.requestNotificationAuthorization = requestNotificationAuthorization
    loadCache()
    if requestNotificationAuthorization {
      self.notificationService.requestAuthorizationIfNeeded()
    }
  }

  var availableCountryOptions: [ReceiverDirectoryCountryOption] {
    let effectiveSortOption: ReceiverDirectoryCountrySortOption = selectedBackend == .fmDxWebserver
      ? countrySortOption
      : .alphabetical

    return ReceiverDirectorySelectionCore.availableCountryOptions(
      entries: entries.map(\.sharedSelectionEntry),
      backend: selectedBackend,
      sortOption: effectiveSortOption.sharedSortOption
    )
    .map(ReceiverDirectoryCountryOption.init(sharedOption:))
  }

  var availableCountries: [String] {
    availableCountryOptions.map(\.countryLabel)
  }

  var shouldShowCountrySortControl: Bool {
    selectedBackend == .fmDxWebserver && availableCountryOptions.count > 1
  }

  var canClearCache: Bool {
    !entries.isEmpty
      || lastRefreshDate != nil
      || defaults.object(forKey: Self.cacheEntriesKey) != nil
      || defaults.object(forKey: Self.cacheRefreshDateKey) != nil
  }

  var cacheStatusText: String? {
    guard isUsingCachedData else { return nil }
    if let lastRefreshDate {
      return L10n.text(
        "directory.cache.using_cached_with_date",
        lastRefreshDate.formatted(date: .abbreviated, time: .shortened)
      )
    }
    return L10n.text("directory.cache.using_cached")
  }

  func filteredEntries(favoriteReceiverIDs: Set<String> = []) -> [ReceiverDirectoryEntry] {
    materializedDirectoryEntries(
      from: ReceiverDirectorySelectionCore.filteredEntries(
        entries.map(\.sharedSelectionEntry),
        backend: selectedBackend,
        searchText: searchText,
        statusFilter: statusFilter.sharedStatusFilter,
        sortOption: sortOption.sharedSortOption,
        selectedCountry: selectedCountry,
        favoritesOnly: favoritesOnly,
        favoriteReceiverIDs: favoriteReceiverIDs
      ),
      sourceEntries: entries
    )
  }

  func countryOption(for countryLabel: String) -> ReceiverDirectoryCountryOption? {
    availableCountryOptions.first { $0.countryLabel == countryLabel }
  }

  func countryDisplayTitle(for countryLabel: String) -> String {
    guard let option = countryOption(for: countryLabel) else {
      return countryLabel
    }
    return "\(option.countryLabel) (\(option.receiverCount))"
  }

  var sourceSummaryText: String {
    switch selectedBackend {
    case .fmDxWebserver:
      return L10n.text("directory.source.fmdx")
    case .kiwiSDR:
      return L10n.text("directory.source.kiwi")
    case .openWebRX:
      return L10n.text("directory.source.openwebrx")
    }
  }

  func start() {
    if autoRefreshTask != nil {
      return
    }

    Task { await refresh(force: false) }
    autoRefreshTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        try? await Task.sleep(nanoseconds: self.refreshIntervalSeconds * 1_000_000_000)
        if Task.isCancelled {
          return
        }
        await self.refresh(force: false)
      }
    }
  }

  func stop() {
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
    statusProbeTask?.cancel()
    statusProbeTask = nil
    isProbingStatus = false
  }

  func refresh(force: Bool, userInitiated: Bool = false) async {
    if isLoading {
      return
    }
    if !force, !shouldRefresh {
      return
    }

    if userInitiated {
      refreshResultMessage = nil
    }

    isLoading = true
    errorMessage = nil

    do {
      let previousEntries = entries
      let fetched = try await service.fetchAllEntries()
      let mergedEntries = sortEntries(applyKnownStatuses(to: fetched))
      entries = mergedEntries
      normalizeSelectedCountryIfNeeded()
      lastRefreshDate = Date()
      isUsingCachedData = false
      persistCache()
      Diagnostics.log(
        category: "Directory",
        message: "Directory refreshed (\(fetched.count) receivers)"
      )

      let newlyAddedByBackend = previousEntries.isEmpty
        ? [:]
        : newlyAddedReceivers(previous: previousEntries, current: mergedEntries)

      if !newlyAddedByBackend.isEmpty {
        notificationService.notifyNewReceiversIfNeeded(groupedByBackend: newlyAddedByBackend)
        Diagnostics.log(
          category: "Directory",
          message: "New receivers detected: \(newlyAddedByBackend)"
        )
      }

      if userInitiated {
        let resultMessage = manualRefreshResultMessage(
          previousEntries: previousEntries,
          currentEntries: mergedEntries,
          newlyAddedByBackend: newlyAddedByBackend
        )
        refreshResultMessage = resultMessage
        AppAccessibilityAnnouncementCenter.post(resultMessage)
      }
    } catch {
      errorMessage = error.localizedDescription
      isUsingCachedData = !entries.isEmpty
      if userInitiated {
        AppAccessibilityAnnouncementCenter.post(error.localizedDescription)
      }
      Diagnostics.log(
        severity: .warning,
        category: "Directory",
        message: "Directory refresh failed: \(error.localizedDescription)"
      )
    }

    isLoading = false
    scheduleStatusProbeForSelectedBackend(force: force)
  }

  func scheduleStatusProbeForSelectedBackend(force: Bool = false) {
    let backend = selectedBackend
    guard backend == .kiwiSDR || backend == .openWebRX else {
      statusProbeTask?.cancel()
      statusProbeTask = nil
      isProbingStatus = false
      return
    }

    guard force || shouldProbeStatus(for: backend) else {
      return
    }

    let targets = entries.filter { $0.backend == backend }
    guard !targets.isEmpty else {
      statusProbeTask?.cancel()
      statusProbeTask = nil
      isProbingStatus = false
      return
    }

    statusProbeTask?.cancel()
    isProbingStatus = true

    statusProbeTask = Task { [service] in
      let probeResults = await service.probeStatuses(for: targets, backend: backend)
      if Task.isCancelled {
        return
      }

      await MainActor.run {
        self.applyProbedStatuses(probeResults, backend: backend)
      }
    }
  }

  func clearCache() {
    statusProbeTask?.cancel()
    statusProbeTask = nil
    isProbingStatus = false
    entries = []
    lastRefreshDate = nil
    errorMessage = nil
    isUsingCachedData = false
    selectedCountry = ""
    lastProbeDateByBackend.removeAll()
    defaults.removeObject(forKey: Self.cacheEntriesKey)
    defaults.removeObject(forKey: Self.cacheRefreshDateKey)

    let message = L10n.text("directory.cache.cleared")
    refreshResultMessage = message
    Diagnostics.log(category: "Directory", message: "Directory cache cleared")
    AppAccessibilityAnnouncementCenter.post(message)
  }

  private var shouldRefresh: Bool {
    guard !entries.isEmpty else { return true }
    guard let lastRefreshDate else { return true }
    return Date().timeIntervalSince(lastRefreshDate) >= staleAfterSeconds
  }

  private func shouldProbeStatus(for backend: SDRBackend) -> Bool {
    let backendEntries = entries.filter { $0.backend == backend }
    guard !backendEntries.isEmpty else { return false }

    if backendEntries.contains(where: { $0.status == .unknown }) {
      return true
    }

    guard let lastProbeDate = lastProbeDateByBackend[backend] else {
      return true
    }

    return Date().timeIntervalSince(lastProbeDate) >= statusProbeIntervalSeconds
  }

  private func applyKnownStatuses(to fetched: [ReceiverDirectoryEntry]) -> [ReceiverDirectoryEntry] {
    guard !entries.isEmpty else {
      return fetched
    }

    let knownStatusByEntryID: [String: ReceiverDirectoryStatus] = entries.reduce(into: [:]) { acc, entry in
      acc[entry.id] = entry.status
    }

    return fetched.map { entry in
      guard entry.backend != .fmDxWebserver else {
        return entry
      }

      guard let status = knownStatusByEntryID[entry.id], status != .unknown else {
        return entry
      }

      return entry.withStatus(status)
    }
  }

  private func applyProbedStatuses(
    _ probedStatuses: [String: ReceiverDirectoryStatus],
    backend: SDRBackend
  ) {
    isProbingStatus = false
    lastProbeDateByBackend[backend] = Date()

    guard !probedStatuses.isEmpty else {
      Diagnostics.log(
        severity: .warning,
        category: "Directory",
        message: "Status probe returned no results for \(backend.displayName)"
      )
      return
    }

    var updatedCount = 0
    let updatedEntries = entries.map { entry in
      guard entry.backend == backend, let newStatus = probedStatuses[entry.id] else {
        return entry
      }

      if entry.status != newStatus {
        updatedCount += 1
      }

      return entry.withStatus(newStatus)
    }

    entries = sortEntries(updatedEntries)
    persistCache()
    Diagnostics.log(
      category: "Directory",
      message: "Status probe completed for \(backend.displayName) (\(probedStatuses.count) checked, \(updatedCount) changed)"
    )
  }

  private func sortEntries(_ source: [ReceiverDirectoryEntry]) -> [ReceiverDirectoryEntry] {
    materializedDirectoryEntries(
      from: ReceiverDirectorySelectionCore.recommendedSortedEntries(
        source.map(\.sharedSelectionEntry)
      ),
      sourceEntries: source
    )
  }

  private func newlyAddedReceivers(
    previous: [ReceiverDirectoryEntry],
    current: [ReceiverDirectoryEntry]
  ) -> [SDRBackend: [String]] {
    let previousIDs = Set(previous.map(\.id))
    let newlyAdded = current.filter { !previousIDs.contains($0.id) }
    guard !newlyAdded.isEmpty else { return [:] }

    let grouped = newlyAdded.reduce(into: [SDRBackend: [String]]()) { result, entry in
      let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = trimmedName.isEmpty ? entry.host : trimmedName
      result[entry.backend, default: []].append(name)
    }

    return grouped.reduce(into: [SDRBackend: [String]]()) { result, element in
      let uniqueNames = Array(Set(element.value)).sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
      }
      if !uniqueNames.isEmpty {
        result[element.key] = uniqueNames
      }
    }
  }

  private func loadCache() {
    if let raw = defaults.data(forKey: Self.cacheEntriesKey),
      let decoded = try? JSONDecoder().decode([ReceiverDirectoryEntry].self, from: raw) {
      entries = decoded
      isUsingCachedData = !decoded.isEmpty
    }

    if let cachedDate = defaults.object(forKey: Self.cacheRefreshDateKey) as? Date {
      lastRefreshDate = cachedDate
    }

    normalizeSelectedCountryIfNeeded()
  }

  private func persistCache() {
    guard let encoded = try? JSONEncoder().encode(entries) else { return }
    defaults.set(encoded, forKey: Self.cacheEntriesKey)
    defaults.set(lastRefreshDate, forKey: Self.cacheRefreshDateKey)
  }

  private func normalizeSelectedCountryIfNeeded() {
    guard !selectedCountry.isEmpty else { return }
    guard availableCountries.contains(selectedCountry) else {
      selectedCountry = ""
      return
    }
  }

  private func manualRefreshResultMessage(
    previousEntries: [ReceiverDirectoryEntry],
    currentEntries: [ReceiverDirectoryEntry],
    newlyAddedByBackend: [SDRBackend: [String]]
  ) -> String {
    if previousEntries.isEmpty {
      return L10n.text("directory.refresh.result.initial", currentEntries.count)
    }

    let newReceiverCount = newlyAddedByBackend.values.reduce(0) { partialResult, names in
      partialResult + names.count
    }

    guard newReceiverCount > 0 else {
      return L10n.text("directory.refresh.result.none")
    }

    return L10n.text("directory.refresh.result.updated", newReceiverCount, currentEntries.count)
  }

  nonisolated static func normalizedSearchText(_ value: String) -> String {
    ReceiverDirectorySearchCore.normalizedSearchText(value)
  }

  nonisolated static func searchableText(for entry: ReceiverDirectoryEntry) -> String {
    ReceiverDirectorySearchCore.searchableText(
      fields: [
        entry.name,
        entry.host,
        entry.endpointDescription,
        entry.sourceName,
        entry.cityLabel,
        entry.countryLabel,
        entry.locationLabel,
        entry.softwareVersion,
        entry.backend.displayName,
        entry.status.displayName
      ]
    )
  }

  nonisolated static func matchesSearch(query: String, entry: ReceiverDirectoryEntry) -> Bool {
    ReceiverDirectorySearchCore.matchesSearch(
      query: query,
      searchableText: searchableText(for: entry)
    )
  }
}

private func materializedDirectoryEntries(
  from sharedEntries: [SharedDirectorySelectionEntry],
  sourceEntries: [ReceiverDirectoryEntry]
) -> [ReceiverDirectoryEntry] {
  var entriesByFingerprint = Dictionary(grouping: sourceEntries, by: \.selectionFingerprint)

  return sharedEntries.compactMap { sharedEntry in
    let fingerprint = sharedEntry.selectionFingerprint
    guard var matches = entriesByFingerprint[fingerprint], !matches.isEmpty else {
      return sourceEntries.first { $0.selectionFingerprint == fingerprint }
    }

    let match = matches.removeFirst()
    if matches.isEmpty {
      entriesByFingerprint.removeValue(forKey: fingerprint)
    } else {
      entriesByFingerprint[fingerprint] = matches
    }
    return match
  }
}

private extension ReceiverDirectoryEntry {
  var sharedSelectionEntry: SharedDirectorySelectionEntry {
    SharedDirectorySelectionEntry(
      id: id,
      backend: backend,
      name: name,
      sourceName: sourceName,
      status: status.sharedStatus,
      countryLabel: countryLabel,
      locationLabel: locationLabel,
      searchableText: ReceiverDirectoryViewModel.searchableText(for: self),
      detailText: detailText,
      receiverIdentity: ReceiverIdentity.key(for: self)
    )
  }

  var selectionFingerprint: String {
    sharedSelectionEntry.selectionFingerprint
  }
}

private extension SharedDirectorySelectionEntry {
  var selectionFingerprint: String {
    [
      id,
      backend.rawValue,
      name,
      sourceName,
      status.rawValue,
      countryLabel ?? "",
      locationLabel ?? "",
      searchableText,
      detailText,
      receiverIdentity
    ].joined(separator: "\u{1F}")
  }
}

private extension ReceiverDirectoryStatusFilter {
  var sharedStatusFilter: SharedDirectoryStatusFilter {
    switch self {
    case .all:
      return .all
    case .online:
      return .online
    case .availableOnly:
      return .availableOnly
    case .unavailable:
      return .unavailable
    }
  }
}

private extension ReceiverDirectoryCountrySortOption {
  var sharedSortOption: SharedDirectoryCountrySortOption {
    switch self {
    case .alphabetical:
      return .alphabetical
    case .receiverCount:
      return .receiverCount
    }
  }
}

private extension ReceiverDirectorySortOption {
  var sharedSortOption: SharedDirectorySortOption {
    switch self {
    case .recommended:
      return .recommended
    case .name:
      return .name
    case .location:
      return .location
    case .status:
      return .status
    case .source:
      return .source
    }
  }
}

private extension ReceiverDirectoryCountryOption {
  init(sharedOption: SharedDirectoryCountryOption) {
    self.init(
      countryLabel: sharedOption.countryLabel,
      receiverCount: sharedOption.receiverCount
    )
  }
}
