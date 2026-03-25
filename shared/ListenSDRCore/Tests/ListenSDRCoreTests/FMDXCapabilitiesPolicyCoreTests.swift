import XCTest
@testable import ListenSDRCore

final class FMDXCapabilitiesPolicyCoreTests: XCTestCase {
  func testMeaningfulCapabilitySnapshotMatchesCanonicalFixtures() throws {
    let fixture: FMDXCapabilitiesPolicyCoreFixtureSet = try FixtureLoader.load("fmdx-capabilities-policy-core-cases.json")

    for entry in fixture.cases {
      XCTAssertEqual(
        FMDXCapabilitiesPolicyCore.isMeaningful(.init(fixture: entry.capabilities)),
        entry.expected,
        entry.label
      )
    }
  }
}
