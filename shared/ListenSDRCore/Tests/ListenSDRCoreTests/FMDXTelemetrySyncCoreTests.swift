import XCTest
@testable import ListenSDRCore

final class FMDXTelemetrySyncCoreTests: XCTestCase {
  func testToggleParsingMatchesCanonicalFixtures() throws {
    let fixture: FMDXTelemetrySyncCoreFixtureSet = try FixtureLoader.load("fmdx-telemetry-sync-core-cases.json")

    for entry in fixture.toggleCases {
      XCTAssertEqual(
        FMDXTelemetrySyncCore.parseToggleState(entry.input),
        entry.expected,
        entry.label
      )
    }
  }

  func testBandwidthSelectionMatchesCanonicalFixtures() throws {
    let fixture: FMDXTelemetrySyncCoreFixtureSet = try FixtureLoader.load("fmdx-telemetry-sync-core-cases.json")

    for entry in fixture.bandwidthSelectionCases {
      XCTAssertEqual(
        FMDXTelemetrySyncCore.resolveBandwidthSelectionID(
          from: entry.rawValue,
          capabilities: FMDXTelemetrySyncCore.Capabilities(
            bandwidths: entry.capabilities.map(FMDXTelemetrySyncCore.BandwidthOption.init)
          )
        ),
        entry.expected,
        entry.label
      )
    }
  }

  func testSynchronizationMatchesCanonicalFixtures() throws {
    let fixture: FMDXTelemetrySyncCoreFixtureSet = try FixtureLoader.load("fmdx-telemetry-sync-core-cases.json")

    for entry in fixture.syncCases {
      let result = try FMDXTelemetrySyncCore.synchronizedState(
        settings: .init(fixture: entry.input.settings),
        telemetry: .init(fixture: entry.input.telemetry),
        capabilities: .init(fixture: entry.input.capabilities),
        bandMemory: .init(fixture: entry.input.bandMemory),
        pendingTuneFrequencyHz: entry.input.pendingTuneFrequencyHz
      )

      XCTAssertEqual(result.settings, try .init(fixture: entry.expected.settings), entry.label)
      XCTAssertEqual(result.bandMemory, try .init(fixture: entry.expected.bandMemory), entry.label)
      XCTAssertEqual(
        result.resolvedAudioMode,
        try entry.expected.audioMode.map(FMDXTelemetrySyncCore.AudioMode.init(fixtureValue:)),
        entry.label
      )
      XCTAssertEqual(result.resolvedAntennaID, entry.expected.antennaID, entry.label)
      XCTAssertEqual(result.resolvedBandwidthID, entry.expected.bandwidthID, entry.label)
      XCTAssertEqual(result.changedSettings, entry.expected.changedSettings, entry.label)
      XCTAssertEqual(
        result.shouldClearPendingTuneConfirmation,
        entry.expected.shouldClearPendingTuneConfirmation,
        entry.label
      )
      XCTAssertEqual(result.reportedFrequencyHz, entry.expected.reportedFrequencyHz, entry.label)
      XCTAssertEqual(
        result.reportedMode,
        try entry.expected.reportedMode.map(DemodulationMode.init(fixtureValue:)),
        entry.label
      )
    }
  }
}
