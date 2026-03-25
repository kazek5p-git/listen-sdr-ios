import XCTest
@testable import ListenSDRCore

final class FMDXSessionCoreTests: XCTestCase {
  func testQuickBandResolutionMatchesCanonicalFixtures() throws {
    let fixture: FMDXSessionCoreFixtureSet = try FixtureLoader.load("fmdx-session-core-cases.json")

    for entry in fixture.quickBandCases {
      XCTAssertEqual(
        FMDXSessionCore.quickBand(
          for: entry.frequencyHz,
          mode: try DemodulationMode(fixtureValue: entry.mode)
        ),
        try FMDXQuickBand(fixtureValue: entry.expectedQuickBand),
        entry.label
      )
    }
  }

  func testInferredModeMatchesCanonicalFixtures() throws {
    let fixture: FMDXSessionCoreFixtureSet = try FixtureLoader.load("fmdx-session-core-cases.json")

    for entry in fixture.inferredModeCases {
      XCTAssertEqual(
        FMDXSessionCore.inferredMode(for: entry.frequencyHz),
        try DemodulationMode(fixtureValue: entry.expectedMode),
        entry.label
      )
    }
  }

  func testPreferredFrequencyMatchesCanonicalFixtures() throws {
    let fixture: FMDXSessionCoreFixtureSet = try FixtureLoader.load("fmdx-session-core-cases.json")

    for entry in fixture.preferredFrequencyCases {
      let memory = try FMDXBandMemory(fixture: entry.memory)

      if let mode = entry.mode {
        XCTAssertEqual(
          FMDXSessionCore.preferredQuickBand(for: try DemodulationMode(fixtureValue: mode), memory: memory),
          try FMDXQuickBand(fixtureValue: entry.expectedQuickBand ?? ""),
          entry.label
        )
        XCTAssertEqual(
          FMDXSessionCore.preferredFrequency(for: try DemodulationMode(fixtureValue: mode), memory: memory),
          entry.expectedFrequencyHz,
          entry.label
        )
      }

      if let band = entry.band {
        XCTAssertEqual(
          FMDXSessionCore.preferredFrequency(for: try FMDXQuickBand(fixtureValue: band), memory: memory),
          entry.expectedFrequencyHz,
          entry.label
        )
      }
    }
  }

  func testRememberCasesMatchCanonicalFixtures() throws {
    let fixture: FMDXSessionCoreFixtureSet = try FixtureLoader.load("fmdx-session-core-cases.json")

    for entry in fixture.rememberCases {
      XCTAssertEqual(
        FMDXSessionCore.rememberedFrequency(
          entry.frequencyHz,
          mode: try DemodulationMode(fixtureValue: entry.mode),
          memory: try FMDXBandMemory(fixture: entry.initialMemory)
        ),
        try FMDXBandMemory(fixture: entry.expectedMemory),
        entry.label
      )
    }
  }

  func testSeedCasesMatchCanonicalFixtures() throws {
    let fixture: FMDXSessionCoreFixtureSet = try FixtureLoader.load("fmdx-session-core-cases.json")

    for entry in fixture.seedCases {
      XCTAssertEqual(
        FMDXSessionCore.seededMemory(
          from: entry.frequencyHz,
          memory: try FMDXBandMemory(fixture: entry.initialMemory)
        ),
        try FMDXBandMemory(fixture: entry.expectedMemory),
        entry.label
      )
    }
  }

  func testReportedFrequencyNormalizationMatchesCanonicalFixtures() throws {
    let fixture: FMDXSessionCoreFixtureSet = try FixtureLoader.load("fmdx-session-core-cases.json")

    for entry in fixture.normalizedReportedFrequencyCases {
      XCTAssertEqual(
        FMDXSessionCore.normalizedReportedFrequencyHz(fromMHz: entry.inputMHz),
        entry.expectedFrequencyHz,
        entry.label
      )
    }
  }
}
