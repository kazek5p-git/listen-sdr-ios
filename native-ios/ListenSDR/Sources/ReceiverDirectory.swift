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

enum ReceiverCountryResolver {
  private static let englishLocale = Locale(identifier: "en_US_POSIX")
  private static let aliasLocales: [Locale] = [
    englishLocale,
    Locale(identifier: "pl_PL"),
    Locale(identifier: "de_DE"),
    Locale(identifier: "fr_FR"),
    Locale(identifier: "es_ES"),
    Locale(identifier: "it_IT")
  ]
  private static let regionCodes = Set(Locale.Region.isoRegions.map { $0.identifier.uppercased() })
  private static let aliasToRegionCode = buildAliasToRegionCodeMap()
  private static let aliasTokenCounts = Array(
    Set(aliasToRegionCode.keys.map { $0.split(separator: " ").count })
  ).sorted(by: >)

  static func normalizedCountryLabel(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard let regionCode = resolvedCountryCode(fromCountryName: trimmed) else {
      return trimmed
    }

    return localizedCountryName(for: regionCode)
  }

  static func normalizedCountryLabel(countryCode: String?, countryName: String?) -> String? {
    if let regionCode = resolvedCountryCode(countryCode: countryCode, countryName: countryName) {
      return localizedCountryName(for: regionCode)
    }

    return normalizedCountryLabel(countryName)
  }

  static func resolvedCountryCode(countryCode: String?, countryName: String?) -> String? {
    if let regionCode = normalizedRegionCodeToken(countryCode) {
      return regionCode
    }

    return resolvedCountryCode(fromCountryName: countryName)
  }

  static func inferredCountryLabel(locationLabel: String?, host: String) -> String? {
    guard let regionCode = resolvedCountryCode(fromMetadataLabel: locationLabel, host: host) else {
      return nil
    }

    return localizedCountryName(for: regionCode)
  }

  static func resolvedCountryCode(fromCountryName rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let flagRegionCode = extractRegionCodeFromFlag(in: trimmed) {
      return flagRegionCode
    }

    let normalized = normalizedSearchText(trimmed)
    guard !normalized.isEmpty else { return nil }

    if let aliasMatch = aliasToRegionCode[normalized] {
      return aliasMatch
    }

    return normalizedRegionCodeToken(normalized.uppercased())
  }

  static func resolvedCountryCode(fromMetadataLabel locationLabel: String?, host: String?) -> String? {
    if let locationLabel {
      if let flagRegionCode = extractRegionCodeFromFlag(in: locationLabel) {
        return flagRegionCode
      }

      if let directRegionCode = resolvedCountryCode(fromCountryName: locationLabel) {
        return directRegionCode
      }

      if let labelRegionCode = resolvedCountryCode(fromSearchableLabel: locationLabel) {
        return labelRegionCode
      }

      if let uppercaseTokenRegionCode = resolvedCountryCode(fromUppercaseTokens: locationLabel) {
        return uppercaseTokenRegionCode
      }
    }

    return resolvedCountryCode(fromHost: host)
  }

  private static func localizedCountryName(for regionCode: String) -> String {
    Locale.current.localizedString(forRegionCode: regionCode)
      ?? englishLocale.localizedString(forRegionCode: regionCode)
      ?? regionCode
  }

  private static func resolvedCountryCode(fromSearchableLabel label: String) -> String? {
    let tokens = normalizedSearchText(label)
      .split(separator: " ")
      .map(String.init)
    guard !tokens.isEmpty else { return nil }

    for tokenCount in aliasTokenCounts {
      guard tokenCount <= tokens.count else { continue }
      let upperBound = tokens.count - tokenCount
      for startIndex in 0...upperBound {
        let phrase = tokens[startIndex..<(startIndex + tokenCount)].joined(separator: " ")
        if let regionCode = aliasToRegionCode[phrase] {
          return regionCode
        }
      }
    }

    return nil
  }

  private static func resolvedCountryCode(fromUppercaseTokens label: String) -> String? {
    let rawTokens = label
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    for token in rawTokens.reversed() {
      guard token == token.uppercased() else { continue }

      let normalizedToken = normalizedSearchText(token)
      if let aliasMatch = aliasToRegionCode[normalizedToken] {
        return aliasMatch
      }

      if let regionCode = normalizedRegionCodeToken(token) {
        return regionCode
      }
    }

    return nil
  }

  private static func resolvedCountryCode(fromHost host: String?) -> String? {
    guard let host else { return nil }
    let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedHost.isEmpty else { return nil }

    let topLevelDomain = trimmedHost
      .split(separator: ".")
      .last?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()

    return normalizedRegionCodeToken(topLevelDomain)
  }

  private static func normalizedRegionCodeToken(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !trimmed.isEmpty else { return nil }

    if trimmed == "UK" {
      return "GB"
    }

    guard regionCodes.contains(trimmed) else { return nil }
    return trimmed
  }

  private static func extractRegionCodeFromFlag(in value: String) -> String? {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count >= 2 else { return nil }

    for index in 0..<(scalars.count - 1) {
      let first = scalars[index].value
      let second = scalars[index + 1].value
      guard
        (0x1F1E6...0x1F1FF).contains(first),
        (0x1F1E6...0x1F1FF).contains(second),
        let firstScalar = UnicodeScalar(65 + first - 0x1F1E6),
        let secondScalar = UnicodeScalar(65 + second - 0x1F1E6)
      else {
        continue
      }

      let regionCode = "\(Character(firstScalar))\(Character(secondScalar))"
      if let normalized = normalizedRegionCodeToken(regionCode) {
        return normalized
      }
    }

    return nil
  }

  private static func normalizedSearchText(_ value: String) -> String {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: englishLocale
    )

    let separated = folded.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) {
        return Character(scalar)
      }
      return " "
    }

    return String(separated)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func buildAliasToRegionCodeMap() -> [String: String] {
    var aliases: [String: String] = [:]

    for regionCode in regionCodes {
      for locale in aliasLocales {
        if let localizedName = locale.localizedString(forRegionCode: regionCode) {
          registerAlias(localizedName, for: regionCode, into: &aliases)
        }
      }
    }

    let manualAliases: [String: String] = [
      "united states of america": "US",
      "usa": "US",
      "great britain": "GB",
      "britain": "GB",
      "united kingdom": "GB",
      "uk": "GB",
      "england": "GB",
      "scotland": "GB",
      "wales": "GB",
      "northern ireland": "GB",
      "the netherlands": "NL",
      "holland": "NL",
      "czech republic": "CZ",
      "south korea": "KR",
      "republic of korea": "KR",
      "north korea": "KP",
      "dprk": "KP",
      "uae": "AE"
    ]

    for (alias, regionCode) in manualAliases {
      registerAlias(alias, for: regionCode, into: &aliases)
    }

    return aliases
  }

  private static func registerAlias(
    _ rawAlias: String,
    for regionCode: String,
    into aliases: inout [String: String]
  ) {
    let normalizedAlias = normalizedSearchText(rawAlias)
    guard !normalizedAlias.isEmpty else { return }
    aliases[normalizedAlias] = regionCode
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

  private func normalizedLabel(_ value: String?) -> String? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return normalized.isEmpty ? nil : normalized
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
    let receiverCountByCountry = entries
      .filter { $0.backend == selectedBackend }
      .compactMap(\.countryLabel)
      .filter { !$0.isEmpty }
      .reduce(into: [String: Int]()) { partialResult, countryLabel in
        partialResult[countryLabel, default: 0] += 1
      }

    let options = receiverCountByCountry.map { countryLabel, receiverCount in
      ReceiverDirectoryCountryOption(
        countryLabel: countryLabel,
        receiverCount: receiverCount
      )
    }

    let effectiveSortOption: ReceiverDirectoryCountrySortOption = selectedBackend == .fmDxWebserver
      ? countrySortOption
      : .alphabetical

    switch effectiveSortOption {
    case .alphabetical:
      return options.sorted {
        $0.countryLabel.localizedCaseInsensitiveCompare($1.countryLabel) == .orderedAscending
      }
    case .receiverCount:
      return options.sorted { lhs, rhs in
        if lhs.receiverCount != rhs.receiverCount {
          return lhs.receiverCount > rhs.receiverCount
        }
        return lhs.countryLabel.localizedCaseInsensitiveCompare(rhs.countryLabel) == .orderedAscending
      }
    }
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
    var selected = entries.filter { $0.backend == selectedBackend }

    if favoritesOnly {
      selected = selected.filter { favoriteReceiverIDs.contains(ReceiverIdentity.key(for: $0)) }
    }

    if !selectedCountry.isEmpty {
      selected = selected.filter { $0.countryLabel == selectedCountry }
    }

    selected = selected.filter { entry in
      switch statusFilter {
      case .all:
        return true
      case .online:
        return entry.status == .available || entry.status == .limited
      case .availableOnly:
        return entry.status == .available
      case .unavailable:
        return entry.status == .unreachable
      }
    }

    let query = Self.normalizedSearchText(searchText)
    if !query.isEmpty {
      selected = selected.filter { Self.matchesSearch(query: query, entry: $0) }
    }

    return selected.sorted { lhs, rhs in
      switch sortOption {
      case .recommended:
        return compareRecommended(lhs: lhs, rhs: rhs)
      case .name:
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      case .location:
        let lhsLocation = lhs.locationLabel ?? lhs.countryLabel ?? lhs.name
        let rhsLocation = rhs.locationLabel ?? rhs.countryLabel ?? rhs.name
        if lhsLocation.localizedCaseInsensitiveCompare(rhsLocation) != .orderedSame {
          return lhsLocation.localizedCaseInsensitiveCompare(rhsLocation) == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      case .status:
        if lhs.status.sortRank != rhs.status.sortRank {
          return lhs.status.sortRank < rhs.status.sortRank
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      case .source:
        if lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) != .orderedSame {
          return lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
    }
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

  private func compareRecommended(lhs: ReceiverDirectoryEntry, rhs: ReceiverDirectoryEntry) -> Bool {
    if lhs.backend != rhs.backend {
      return backendSortRank(lhs.backend) < backendSortRank(rhs.backend)
    }
    if lhs.status.sortRank != rhs.status.sortRank {
      return lhs.status.sortRank < rhs.status.sortRank
    }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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

  static func normalizedSearchText(_ value: String) -> String {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )

    return folded
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  static func searchableText(for entry: ReceiverDirectoryEntry) -> String {
    normalizedSearchText(
      [
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
      .compactMap { $0 }
      .joined(separator: " ")
    )
  }

  static func matchesSearch(query: String, entry: ReceiverDirectoryEntry) -> Bool {
    let normalizedQuery = normalizedSearchText(query)
    guard !normalizedQuery.isEmpty else { return true }

    let searchableText = searchableText(for: entry)
    if searchableText.contains(normalizedQuery) {
      return true
    }

    let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
    guard queryTokens.count > 1 else { return false }
    return queryTokens.allSatisfy { searchableText.contains($0) }
  }
}
