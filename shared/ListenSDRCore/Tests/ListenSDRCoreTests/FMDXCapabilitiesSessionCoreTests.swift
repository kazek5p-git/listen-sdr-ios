import XCTest
@testable import ListenSDRCore

final class FMDXCapabilitiesSessionCoreTests: XCTestCase {
  func testRestoredStateMatchesCanonicalFixtures() throws {
    let fixture: FMDXCapabilitiesSessionCoreFixtureSet = try FixtureLoader.load(
      "fmdx-capabilities-session-core-cases.json"
    )

    for testCase in fixture.restoreCases {
      XCTAssertEqual(
        FMDXCapabilitiesSessionCore.State(
          capabilities: .init(fixture: testCase.expected.capabilities),
          hasConfirmedSnapshot: testCase.expected.hasConfirmedSnapshot,
          usedCachedCapabilities: testCase.expected.usedCachedCapabilities
        ),
        FMDXCapabilitiesSessionCore.restoredState(
          cached: testCase.cached.map(FMDXCapabilitiesPolicyCore.Capabilities.init(fixture:))
        ),
        testCase.label
      )
    }
  }

  func testConnectedStateMatchesCanonicalFixtures() throws {
    let fixture: FMDXCapabilitiesSessionCoreFixtureSet = try FixtureLoader.load(
      "fmdx-capabilities-session-core-cases.json"
    )

    for testCase in fixture.connectedCases {
      XCTAssertEqual(
        FMDXCapabilitiesSessionCore.State(
          capabilities: .init(fixture: testCase.expected.capabilities),
          hasConfirmedSnapshot: testCase.expected.hasConfirmedSnapshot,
          usedCachedCapabilities: testCase.expected.usedCachedCapabilities
        ),
        FMDXCapabilitiesSessionCore.connectedState(
          resolution: .init(
            capabilities: .init(fixture: testCase.resolution.capabilities),
            usedFallbackCapabilities: testCase.resolution.usedFallbackCapabilities,
            primarySnapshotWasMeaningful: testCase.resolution.primarySnapshotWasMeaningful,
            shouldPersistResolvedCapabilities: testCase.resolution.shouldPersistResolvedCapabilities
          )
        ),
        testCase.label
      )
    }
  }
}
