import XCTest
@testable import ListenSDRCore

final class FMDXCapabilitiesSyncCoreTests: XCTestCase {
  func testSynchronizationMatchesCanonicalFixtures() throws {
    let fixture: FMDXCapabilitiesSyncCoreFixtureSet = try FixtureLoader.load("fmdx-capabilities-sync-core-cases.json")

    for entry in fixture.syncCases {
      let result = try FMDXCapabilitiesSyncCore.synchronizedState(
        settings: .init(fixture: entry.input.settings),
        selectedBandwidthID: entry.input.selectedBandwidthID,
        capabilities: .init(fixture: entry.input.capabilities)
      )

      XCTAssertEqual(result.settings, try .init(fixture: entry.expected.settings), entry.label)
      XCTAssertEqual(result.resolvedBandwidthID, entry.expected.resolvedBandwidthID, entry.label)
      XCTAssertEqual(result.changedSettings, entry.expected.changedSettings, entry.label)
      XCTAssertEqual(result.forcedFMBandFallback, entry.expected.forcedFMBandFallback, entry.label)
    }
  }
}
