import XCTest
@testable import ListenSDRCore

final class ReceiverDirectorySearchCoreTests: XCTestCase {
  func testMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load(
      "receiver-directory-search-core-cases.json",
      as: ReceiverDirectorySearchFixtureSet.self
    )

    for testCase in fixture.normalizedSearchTextCases {
      XCTAssertEqual(
        ReceiverDirectorySearchCore.normalizedSearchText(testCase.input),
        testCase.expected,
        testCase.label
      )
    }

    for testCase in fixture.searchableTextCases {
      XCTAssertEqual(
        ReceiverDirectorySearchCore.searchableText(fields: testCase.fields),
        testCase.expected,
        testCase.label
      )
    }

    for testCase in fixture.matchCases {
      XCTAssertEqual(
        ReceiverDirectorySearchCore.matchesSearch(
          query: testCase.query,
          searchableText: testCase.searchableText
        ),
        testCase.expected,
        testCase.label
      )
    }
  }
}
