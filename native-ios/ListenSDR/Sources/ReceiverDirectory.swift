import Foundation
import Combine

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
      locationLabel: locationLabel,
      softwareVersion: softwareVersion,
      latitude: latitude,
      longitude: longitude
    )
  }
}

private struct DirectoryEndpoint {
  let host: String
  let port: Int
  let path: String
  let useTLS: Bool
  let absoluteURL: String
}

private struct FMDXDirectoryResponse: Decodable {
  let dataset: [FMDXDirectoryRow]
}

private struct FMDXDirectoryRow: Decodable {
  let name: String?
  let tuner: String?
  let version: String?
  let city: String?
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
      let location = locationLabel(city: row.city, country: row.countryName)
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
    request.setValue("ListenSDR/1.0", forHTTPHeaderField: "User-Agent")
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
    let pattern = "var receivers = (\\[.*?\\]);\\s*\\$\\('\\.map-container'\\)\\.addReceivers\\(receivers\\);"
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    guard
      let match = regex.firstMatch(in: html, options: [], range: nsRange),
      match.numberOfRanges > 1,
      let jsonRange = Range(match.range(at: 1), in: html)
    else {
      throw SDRClientError.unsupported("Receiverbook map format changed and cannot be parsed.")
    }
    return String(html[jsonRange])
  }

  private func parseEndpoint(from raw: String) -> DirectoryEndpoint? {
    var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { return nil }

    if !candidate.contains("://") {
      candidate = "http://\(candidate)"
    }

    candidate = candidate.replacingOccurrences(of: " ", with: "%20")

    guard var components = URLComponents(string: candidate),
      let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
      !host.isEmpty
    else {
      return nil
    }

    let scheme = (components.scheme ?? "http").lowercased()
    let useTLS = scheme == "https"
    let port = components.port ?? (useTLS ? 443 : 80)
    let path = components.path.isEmpty ? "/" : components.path

    components.scheme = useTLS ? "https" : "http"
    components.host = host
    components.port = port
    components.path = path
    components.query = nil
    components.fragment = nil

    guard let normalizedURL = components.url else {
      return nil
    }

    return DirectoryEndpoint(
      host: host.lowercased(),
      port: port,
      path: path,
      useTLS: useTLS,
      absoluteURL: normalizedURL.absoluteString
    )
  }

  private func entryID(backend: SDRBackend, endpoint: DirectoryEndpoint) -> String {
    "\(backend.rawValue)|\(endpoint.useTLS ? "https" : "http")|\(endpoint.host)|\(endpoint.port)|\(endpoint.path.lowercased())"
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

  private func fmdxStatus(from raw: Int?) -> ReceiverDirectoryStatus {
    switch raw {
    case 1:
      return .available
    case 2:
      return .limited
    case 0:
      return .unreachable
    default:
      return .unknown
    }
  }

  private func matchesReceiverbookType(_ value: String, backend: SDRBackend) -> Bool {
    switch backend {
    case .kiwiSDR:
      return value.contains("kiwi")
    case .openWebRX:
      return value.contains("openwebrx")
    case .fmDxWebserver:
      return false
    }
  }

  private func deduplicatedAndSorted(_ entries: [ReceiverDirectoryEntry]) -> [ReceiverDirectoryEntry] {
    var byID: [String: ReceiverDirectoryEntry] = [:]
    byID.reserveCapacity(entries.count)

    for entry in entries {
      if let existing = byID[entry.id] {
        byID[entry.id] = preferredEntry(existing, entry)
      } else {
        byID[entry.id] = entry
      }
    }

    return byID.values.sorted { lhs, rhs in
      if lhs.backend != rhs.backend {
        return backendSortRank(lhs.backend) < backendSortRank(rhs.backend)
      }
      if lhs.status.sortRank != rhs.status.sortRank {
        return lhs.status.sortRank < rhs.status.sortRank
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
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
    request.setValue("ListenSDR/1.0", forHTTPHeaderField: "User-Agent")
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
    switch statusCode {
    case 200...399:
      return .available
    case 401, 403, 423, 429:
      return .limited
    case 400...499:
      return .unreachable
    case 500...599:
      return .unreachable
    default:
      return .unknown
    }
  }

  private func preferredEntry(
    _ lhs: ReceiverDirectoryEntry,
    _ rhs: ReceiverDirectoryEntry
  ) -> ReceiverDirectoryEntry {
    if lhs.status.sortRank != rhs.status.sortRank {
      return lhs.status.sortRank < rhs.status.sortRank ? lhs : rhs
    }

    let lhsDetail = lhs.detailText.count
    let rhsDetail = rhs.detailText.count
    if lhsDetail != rhsDetail {
      return lhsDetail > rhsDetail ? lhs : rhs
    }

    return lhs
  }

  private func backendSortRank(_ backend: SDRBackend) -> Int {
    switch backend {
    case .fmDxWebserver:
      return 0
    case .kiwiSDR:
      return 1
    case .openWebRX:
      return 2
    }
  }
}

@MainActor
final class ReceiverDirectoryViewModel: ObservableObject {
  @Published var selectedBackend: SDRBackend = .fmDxWebserver
  @Published var searchText: String = ""
  @Published private(set) var entries: [ReceiverDirectoryEntry] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isProbingStatus = false
  @Published private(set) var lastRefreshDate: Date?
  @Published private(set) var errorMessage: String?

  let supportedBackends: [SDRBackend] = [.fmDxWebserver, .kiwiSDR, .openWebRX]

  private let service: ReceiverDirectoryService
  private let notificationService: DirectoryChangeNotificationService
  private var autoRefreshTask: Task<Void, Never>?
  private var statusProbeTask: Task<Void, Never>?
  private var lastProbeDateByBackend: [SDRBackend: Date] = [:]

  private let cacheEntriesKey = "ListenSDR.directory.entries.v1"
  private let cacheRefreshDateKey = "ListenSDR.directory.refreshDate.v1"
  private let refreshIntervalSeconds: UInt64 = 900
  private let staleAfterSeconds: TimeInterval = 900
  private let statusProbeIntervalSeconds: TimeInterval = 1_800

  init(
    service: ReceiverDirectoryService = ReceiverDirectoryService(),
    notificationService: DirectoryChangeNotificationService? = nil
  ) {
    self.service = service
    self.notificationService = notificationService ?? .shared
    loadCache()
    self.notificationService.requestAuthorizationIfNeeded()
  }

  var filteredEntries: [ReceiverDirectoryEntry] {
    let selected = entries.filter { $0.backend == selectedBackend }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return selected }

    return selected.filter { entry in
      if entry.name.lowercased().contains(query) {
        return true
      }
      if entry.host.lowercased().contains(query) {
        return true
      }
      if let location = entry.locationLabel?.lowercased(), location.contains(query) {
        return true
      }
      return false
    }
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
        try? await Task.sleep(nanoseconds: refreshIntervalSeconds * 1_000_000_000)
        if Task.isCancelled {
          return
        }
        guard let self else { return }
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

  func refresh(force: Bool) async {
    if isLoading {
      return
    }
    if !force, !shouldRefresh {
      return
    }

    isLoading = true
    errorMessage = nil

    do {
      let previousEntries = entries
      let fetched = try await service.fetchAllEntries()
      let mergedEntries = sortEntries(applyKnownStatuses(to: fetched))
      entries = mergedEntries
      lastRefreshDate = Date()
      persistCache()
      Diagnostics.log(
        category: "Directory",
        message: "Directory refreshed (\(fetched.count) receivers)"
      )

      if !previousEntries.isEmpty {
        let newlyAddedByBackend = newlyAddedReceivers(previous: previousEntries, current: mergedEntries)
        if !newlyAddedByBackend.isEmpty {
          notificationService.notifyNewReceiversIfNeeded(groupedByBackend: newlyAddedByBackend)
          Diagnostics.log(
            category: "Directory",
            message: "New receivers detected: \(newlyAddedByBackend)"
          )
        }
      }
    } catch {
      errorMessage = error.localizedDescription
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
    source.sorted { lhs, rhs in
      if lhs.backend != rhs.backend {
        return backendSortRank(lhs.backend) < backendSortRank(rhs.backend)
      }
      if lhs.status.sortRank != rhs.status.sortRank {
        return lhs.status.sortRank < rhs.status.sortRank
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  private func backendSortRank(_ backend: SDRBackend) -> Int {
    switch backend {
    case .fmDxWebserver:
      return 0
    case .kiwiSDR:
      return 1
    case .openWebRX:
      return 2
    }
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
    let defaults = UserDefaults.standard

    if let raw = defaults.data(forKey: cacheEntriesKey),
      let decoded = try? JSONDecoder().decode([ReceiverDirectoryEntry].self, from: raw) {
      entries = decoded
    }

    if let cachedDate = defaults.object(forKey: cacheRefreshDateKey) as? Date {
      lastRefreshDate = cachedDate
    }
  }

  private func persistCache() {
    guard let encoded = try? JSONEncoder().encode(entries) else { return }
    let defaults = UserDefaults.standard
    defaults.set(encoded, forKey: cacheEntriesKey)
    defaults.set(lastRefreshDate, forKey: cacheRefreshDateKey)
  }
}
