import Foundation

public enum SharedReceiverDirectoryStatusFilter: String, Codable, CaseIterable, Sendable {
  case all
  case online
  case availableOnly
  case unavailable
}

public enum SharedReceiverDirectoryCountrySortOption: String, Codable, CaseIterable, Sendable {
  case alphabetical
  case receiverCount
}

public enum SharedReceiverDirectorySortOption: String, Codable, CaseIterable, Sendable {
  case recommended
  case name
  case location
  case status
  case source
}

public struct SharedReceiverDirectoryCountryOption: Equatable, Hashable, Codable, Sendable {
  public let countryLabel: String
  public let receiverCount: Int

  public init(countryLabel: String, receiverCount: Int) {
    self.countryLabel = countryLabel
    self.receiverCount = receiverCount
  }
}

public struct SharedReceiverDirectoryEntry: Equatable, Hashable, Codable, Sendable {
  public let id: String
  public let backend: SDRBackend
  public let name: String
  public let sourceName: String
  public let status: SharedReceiverDirectoryStatus
  public let countryLabel: String?
  public let locationLabel: String?
  public let searchableText: String
  public let detailText: String
  public let receiverIdentity: String

  public init(
    id: String,
    backend: SDRBackend,
    name: String,
    sourceName: String,
    status: SharedReceiverDirectoryStatus,
    countryLabel: String?,
    locationLabel: String?,
    searchableText: String,
    detailText: String,
    receiverIdentity: String
  ) {
    self.id = id
    self.backend = backend
    self.name = name
    self.sourceName = sourceName
    self.status = status
    self.countryLabel = countryLabel
    self.locationLabel = locationLabel
    self.searchableText = searchableText
    self.detailText = detailText
    self.receiverIdentity = receiverIdentity
  }
}

public enum ReceiverDirectorySelectionCore {
  public static func availableCountryOptions(
    entries: [SharedReceiverDirectoryEntry],
    backend: SDRBackend,
    sortOption: SharedReceiverDirectoryCountrySortOption
  ) -> [SharedReceiverDirectoryCountryOption] {
    let counts = entries
      .filter { $0.backend == backend }
      .compactMap { entry in
        normalizedCountryLabel(entry.countryLabel)
      }
      .reduce(into: [String: Int]()) { partialResult, countryLabel in
        partialResult[countryLabel, default: 0] += 1
      }

    let options = counts.map { countryLabel, receiverCount in
      SharedReceiverDirectoryCountryOption(
        countryLabel: countryLabel,
        receiverCount: receiverCount
      )
    }

    switch sortOption {
    case .alphabetical:
      return options.sorted { lhs, rhs in
        let countryCompare = compareStrings(lhs.countryLabel, rhs.countryLabel)
        if countryCompare != .orderedSame {
          return countryCompare == .orderedAscending
        }
        return lhs.receiverCount > rhs.receiverCount
      }

    case .receiverCount:
      return options.sorted { lhs, rhs in
        if lhs.receiverCount != rhs.receiverCount {
          return lhs.receiverCount > rhs.receiverCount
        }
        return compareStrings(lhs.countryLabel, rhs.countryLabel) == .orderedAscending
      }
    }
  }

  public static func filteredEntries(
    _ entries: [SharedReceiverDirectoryEntry],
    backend: SDRBackend,
    searchText: String,
    statusFilter: SharedReceiverDirectoryStatusFilter,
    sortOption: SharedReceiverDirectorySortOption,
    selectedCountry: String,
    favoritesOnly: Bool,
    favoriteReceiverIDs: Set<String>
  ) -> [SharedReceiverDirectoryEntry] {
    let trimmedCountry = selectedCountry.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedQuery = ReceiverDirectorySearchCore.normalizedSearchText(searchText)

    let filtered = entries
      .filter { $0.backend == backend }
      .filter { !favoritesOnly || favoriteReceiverIDs.contains($0.receiverIdentity) }
      .filter { trimmedCountry.isEmpty || $0.countryLabel == trimmedCountry }
      .filter { statusMatches($0.status, filter: statusFilter) }
      .filter { entry in
        normalizedQuery.isEmpty
          || ReceiverDirectorySearchCore.matchesSearch(
            query: normalizedQuery,
            searchableText: entry.searchableText
          )
      }

    return sortEntries(filtered, sortOption: sortOption)
  }

  public static func recommendedSortedEntries(
    _ entries: [SharedReceiverDirectoryEntry]
  ) -> [SharedReceiverDirectoryEntry] {
    sortEntries(entries, sortOption: .recommended)
  }

  public static func sortEntries(
    _ entries: [SharedReceiverDirectoryEntry],
    sortOption: SharedReceiverDirectorySortOption
  ) -> [SharedReceiverDirectoryEntry] {
    entries.sorted { lhs, rhs in
      switch sortOption {
      case .recommended:
        return compareRecommended(lhs: lhs, rhs: rhs)
      case .name:
        return compareStrings(lhs.name, rhs.name) == .orderedAscending
      case .location:
        let locationCompare = compareStrings(lhs.locationSortLabel, rhs.locationSortLabel)
        if locationCompare != .orderedSame {
          return locationCompare == .orderedAscending
        }
        return compareStrings(lhs.name, rhs.name) == .orderedAscending
      case .status:
        if lhs.status.sortRank != rhs.status.sortRank {
          return lhs.status.sortRank < rhs.status.sortRank
        }
        return compareStrings(lhs.name, rhs.name) == .orderedAscending
      case .source:
        let sourceCompare = compareStrings(lhs.sourceName, rhs.sourceName)
        if sourceCompare != .orderedSame {
          return sourceCompare == .orderedAscending
        }
        return compareStrings(lhs.name, rhs.name) == .orderedAscending
      }
    }
  }

  public static func deduplicatedAndSorted(
    _ entries: [SharedReceiverDirectoryEntry]
  ) -> [SharedReceiverDirectoryEntry] {
    var byID: [String: SharedReceiverDirectoryEntry] = [:]
    byID.reserveCapacity(entries.count)

    for entry in entries {
      if let existing = byID[entry.id] {
        byID[entry.id] = preferredEntry(existing, entry)
      } else {
        byID[entry.id] = entry
      }
    }

    return recommendedSortedEntries(Array(byID.values))
  }

  public static func preferredEntry(
    _ lhs: SharedReceiverDirectoryEntry,
    _ rhs: SharedReceiverDirectoryEntry
  ) -> SharedReceiverDirectoryEntry {
    if lhs.status.sortRank != rhs.status.sortRank {
      return lhs.status.sortRank < rhs.status.sortRank ? lhs : rhs
    }

    let lhsDetailLength = lhs.detailText.count
    let rhsDetailLength = rhs.detailText.count
    if lhsDetailLength != rhsDetailLength {
      return lhsDetailLength > rhsDetailLength ? lhs : rhs
    }

    return lhs
  }

  public static func backendSortRank(_ backend: SDRBackend) -> Int {
    switch backend {
    case .fmDxWebserver:
      return 0
    case .kiwiSDR:
      return 1
    case .openWebRX:
      return 2
    }
  }

  private static func statusMatches(
    _ status: SharedReceiverDirectoryStatus,
    filter: SharedReceiverDirectoryStatusFilter
  ) -> Bool {
    switch filter {
    case .all:
      return true
    case .online:
      return status == .available || status == .limited
    case .availableOnly:
      return status == .available
    case .unavailable:
      return status == .unreachable
    }
  }

  private static func compareRecommended(
    lhs: SharedReceiverDirectoryEntry,
    rhs: SharedReceiverDirectoryEntry
  ) -> Bool {
    if lhs.backend != rhs.backend {
      return backendSortRank(lhs.backend) < backendSortRank(rhs.backend)
    }
    if lhs.status.sortRank != rhs.status.sortRank {
      return lhs.status.sortRank < rhs.status.sortRank
    }
    return compareStrings(lhs.name, rhs.name) == .orderedAscending
  }

  private static func normalizedCountryLabel(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func compareStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.localizedCaseInsensitiveCompare(rhs)
  }
}

private extension SharedReceiverDirectoryEntry {
  var locationSortLabel: String {
    locationLabel ?? countryLabel ?? name
  }
}

private extension SharedReceiverDirectoryStatus {
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
