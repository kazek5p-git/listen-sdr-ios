import XCTest
@testable import ListenSDRCore

final class FMDXCapabilitiesMergeCoreTests: XCTestCase {
  func testMergedCapabilitiesMatchCanonicalFixtures() throws {
    let fixture: FMDXCapabilitiesMergeCoreFixtureSet = try FixtureLoader.load("fmdx-capabilities-merge-core-cases.json")

    for entry in fixture.cases {
      XCTAssertEqual(
        FMDXCapabilitiesMergeCore.merged(
          primary: .init(fixture: entry.input.primary),
          fallback: entry.input.fallback.map(FMDXCapabilitiesPolicyCore.Capabilities.init(fixture:))
        ),
        .init(fixture: entry.expected),
        entry.label
      )
    }
  }
}
