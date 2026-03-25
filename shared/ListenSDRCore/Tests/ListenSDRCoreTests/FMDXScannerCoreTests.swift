import XCTest
@testable import ListenSDRCore

final class FMDXScannerCoreTests: XCTestCase {
  func testAvailablePresetsMatchCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.availablePresetCases {
      XCTAssertEqual(
        FMDXBandScanRangePreset.availableCases(supportsAM: entry.supportsAM),
        try entry.expectedPresets.map(FMDXBandScanRangePreset.init(fixtureValue:)),
        entry.label
      )
    }
  }

  func testRangeDefinitionsMatchCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.definitionCases {
      let definition = try FMDXBandScanRangePreset(fixtureValue: entry.preset).definition

      XCTAssertEqual(definition.mode, try DemodulationMode(fixtureValue: entry.expected.mode), entry.label)
      XCTAssertEqual(definition.rangeHz.lowerBound, entry.expected.rangeLowerHz, entry.label)
      XCTAssertEqual(definition.rangeHz.upperBound, entry.expected.rangeUpperHz, entry.label)
      XCTAssertEqual(definition.stepOptionsHz, entry.expected.stepOptionsHz, entry.label)
      XCTAssertEqual(definition.defaultStepHz, entry.expected.defaultStepHz, entry.label)
      XCTAssertEqual(
        definition.metadataProfileBand,
        try FMDXQuickBand(fixtureValue: entry.expected.metadataProfileBand),
        entry.label
      )
      XCTAssertEqual(
        definition.mergeSpacingProfileBand,
        try FMDXQuickBand(fixtureValue: entry.expected.mergeSpacingProfileBand),
        entry.label
      )
    }
  }

  func testSelectableModesMatchCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.selectableModeCases {
      XCTAssertEqual(
        FMDXBandScanMode.selectableCases(saveResultsEnabled: entry.saveResultsEnabled),
        try entry.expectedModes.map(FMDXBandScanMode.init(fixtureValue:)),
        entry.label
      )
    }
  }

  func testSequenceBuilderMatchesCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.sequenceCases {
      XCTAssertEqual(
        FMDXBandScanSequenceBuilder.buildFrequencies(
          in: entry.rangeLowerHz...entry.rangeUpperHz,
          stepHz: entry.stepHz,
          startBehavior: try FMDXBandScanStartBehavior(fixtureValue: entry.startBehavior),
          currentFrequencyHz: entry.currentFrequencyHz
        ),
        entry.expectedFrequenciesHz,
        entry.label
      )
    }
  }

  func testTimingProfilesMatchCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.timingCases {
      let profile = try FMDXBandScanMode(fixtureValue: entry.mode).timingProfile(
        for: try FMDXQuickBand(fixtureValue: entry.band),
        customSettings: FMDXCustomScanSettings(
          settleSeconds: entry.settleSeconds,
          metadataWindowSeconds: entry.metadataWindowSeconds
        )
      )

      XCTAssertEqual(profile.tuneAttemptCount, entry.expected.tuneAttemptCount, entry.label)
      XCTAssertEqual(profile.settleSeconds, entry.expected.settleSeconds, accuracy: 0.0001, entry.label)
      XCTAssertEqual(profile.minimumDeadlineSeconds, entry.expected.minimumDeadlineSeconds, accuracy: 0.0001, entry.label)
      XCTAssertEqual(profile.confirmationGraceSeconds, entry.expected.confirmationGraceSeconds, accuracy: 0.0001, entry.label)
      XCTAssertEqual(
        profile.minimumPostLockSettleSeconds,
        entry.expected.minimumPostLockSettleSeconds,
        accuracy: 0.0001,
        entry.label
      )
      XCTAssertEqual(profile.metadataWindowSeconds, entry.expected.metadataWindowSeconds, accuracy: 0.0001, entry.label)
      XCTAssertEqual(
        profile.minimumMetadataWindowSeconds,
        entry.expected.minimumMetadataWindowSeconds,
        accuracy: 0.0001,
        entry.label
      )
      XCTAssertEqual(profile.metadataPollSeconds, entry.expected.metadataPollSeconds, accuracy: 0.0001, entry.label)
    }
  }

  func testReducerMatchesCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.reducerCases {
      XCTAssertEqual(
        FMDXBandScanReducer.reduce(
          samples: try entry.samples.map(FMDXBandScanSample.init(fixture:)),
          mergeSpacingHz: entry.mergeSpacingHz
        ),
        try entry.expectedResults.map(FMDXBandScanResult.init(fixture:)),
        entry.label
      )
    }
  }

  func testMatcherMatchesCanonicalFixtures() throws {
    let fixture: FMDXScannerCoreFixtureSet = try FixtureLoader.load("fmdx-scanner-core-cases.json")

    for entry in fixture.matcherCases {
      let newResults = FMDXSavedScanResultMatcher.filterNewResults(
        try entry.candidateResults.map(FMDXBandScanResult.init(fixture:)),
        comparedTo: try entry.savedResults.map(FMDXBandScanResult.init(fixture:))
      )

      XCTAssertEqual(newResults.map(\.frequencyHz), entry.expectedNewResultFrequenciesHz, entry.label)
    }
  }
}
