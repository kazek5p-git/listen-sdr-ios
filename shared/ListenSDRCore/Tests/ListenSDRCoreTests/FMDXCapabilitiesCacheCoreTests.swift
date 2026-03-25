import XCTest
@testable import ListenSDRCore

final class FMDXCapabilitiesCacheCoreTests: XCTestCase {
  func testResolvedCapabilitiesMatchCanonicalFixtures() throws {
    let fixture: FMDXCapabilitiesCacheCoreFixtureSet = try FixtureLoader.load("fmdx-capabilities-cache-core-cases.json")

    for entry in fixture.cases {
      XCTAssertEqual(
        FMDXCapabilitiesCacheCore.resolve(
          primary: .init(fixture: entry.input.primary),
          fallback: entry.input.fallback.map(FMDXCapabilitiesPolicyCore.Capabilities.init(fixture:))
        ),
        .init(
          capabilities: .init(fixture: entry.expected.capabilities),
          usedFallbackCapabilities: entry.expected.usedFallbackCapabilities,
          primarySnapshotWasMeaningful: entry.expected.primarySnapshotWasMeaningful,
          shouldPersistResolvedCapabilities: entry.expected.shouldPersistResolvedCapabilities
        ),
        entry.label
      )
    }
  }
}
