import XCTest
@testable import ListenSDRCore

final class ReceiverDirectorySelectionCoreTests: XCTestCase {
  func testMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load(
      "receiver-directory-selection-core-cases.json",
      as: ReceiverDirectorySelectionFixtureSet.self
    )

    for testCase in fixture.countryOptionCases {
      let entries = try testCase.entries.map(SharedReceiverDirectoryEntry.init(fixture:))
      let backend = try SDRBackend(fixtureValue: testCase.backend)
      let sortOption = try SharedReceiverDirectoryCountrySortOption(
        fixtureValue: testCase.sortOption
      )
      let result = ReceiverDirectorySelectionCore.availableCountryOptions(
        entries: entries,
        backend: backend,
        sortOption: sortOption
      )
      let expected = testCase.expected.map {
        SharedReceiverDirectoryCountryOption(
          countryLabel: $0.countryLabel,
          receiverCount: $0.receiverCount
        )
      }

      XCTAssertEqual(
        result,
        expected,
        testCase.label
      )
    }

    for testCase in fixture.deduplicatedCases {
      let entries = try testCase.entries.map(SharedReceiverDirectoryEntry.init(fixture:))
      let result = ReceiverDirectorySelectionCore.deduplicatedAndSorted(entries)

      XCTAssertEqual(result.map(\.id), testCase.expectedOrder, testCase.label)
      XCTAssertEqual(
        result.map(\.status.rawValue),
        testCase.expectedStatuses,
        testCase.label
      )
      XCTAssertEqual(
        result.map(\.detailText),
        testCase.expectedDetailTexts,
        testCase.label
      )
    }

    for testCase in fixture.filteredCases {
      let entries = try testCase.entries.map(SharedReceiverDirectoryEntry.init(fixture:))
      let backend = try SDRBackend(fixtureValue: testCase.backend)
      let statusFilter = try SharedReceiverDirectoryStatusFilter(
        fixtureValue: testCase.statusFilter
      )
      let sortOption = try SharedReceiverDirectorySortOption(
        fixtureValue: testCase.sortOption
      )
      let result = ReceiverDirectorySelectionCore.filteredEntries(
        entries,
        backend: backend,
        searchText: testCase.searchText,
        statusFilter: statusFilter,
        sortOption: sortOption,
        selectedCountry: testCase.selectedCountry,
        favoritesOnly: testCase.favoritesOnly,
        favoriteReceiverIDs: Set(testCase.favoriteReceiverIDs)
      )

      XCTAssertEqual(result.map(\.id), testCase.expectedOrder, testCase.label)
    }
  }
}
