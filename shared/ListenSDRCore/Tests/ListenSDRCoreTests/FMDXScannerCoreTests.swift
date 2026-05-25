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

  func testMergedSavedResultsAccumulatesAndRefreshesMatches() {
    let saved = [
      FMDXBandScanResult(
        frequencyHz: 99_900_000,
        mode: .fm,
        signal: 24.0,
        signalTop: 24.0,
        stationName: "Radio Test",
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: "Old city",
        countryName: nil,
        distanceKm: nil,
        erpKW: nil,
        userCount: nil
      ),
    ]
    let scanned = [
      FMDXBandScanResult(
        frequencyHz: 99_950_000,
        mode: .fm,
        signal: 31.0,
        signalTop: 33.0,
        stationName: nil,
        programService: nil,
        radioText0: "Fresh RDS",
        radioText1: nil,
        city: nil,
        countryName: nil,
        distanceKm: nil,
        erpKW: nil,
        userCount: 3
      ),
      FMDXBandScanResult(
        frequencyHz: 101_100_000,
        mode: .fm,
        signal: 28.0,
        signalTop: 28.0,
        stationName: "New Station",
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: "New city",
        countryName: nil,
        distanceKm: nil,
        erpKW: nil,
        userCount: nil
      ),
    ]

    let merged = FMDXSavedScanResultMatcher.mergedSavedResults(saved, with: scanned)

    XCTAssertEqual(merged.count, 2)
    XCTAssertEqual(merged.first?.frequencyHz, 99_950_000)
    XCTAssertEqual(merged.first?.signal ?? -1, 31.0, accuracy: 0.0001)
    XCTAssertEqual(merged.first?.stationName, "Radio Test")
    XCTAssertEqual(merged.first?.radioText0, "Fresh RDS")
    XCTAssertEqual(merged.first?.city, "Old city")
    XCTAssertEqual(merged.first?.userCount, 3)
    XCTAssertEqual(merged.last?.stationName, "New Station")
  }

  func testMergedSavedResultsKeepsSavedResultsWhenScanIsEmpty() {
    let saved = [
      FMDXBandScanResult(
        frequencyHz: 99_900_000,
        mode: .fm,
        signal: 24.0,
        signalTop: 24.0,
        stationName: "Radio Test",
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: nil,
        countryName: nil,
        distanceKm: nil,
        erpKW: nil,
        userCount: nil
      ),
    ]

    XCTAssertEqual(FMDXSavedScanResultMatcher.mergedSavedResults(saved, with: []), saved)
  }

  func testNoaaPresetIsAvailableAndUsesWeatherChannelSteps() {
    XCTAssertTrue(FMDXBandScanRangePreset.availableCases(supportsAM: false).contains(.noaa))

    let definition = FMDXBandScanRangePreset.noaa.definition
    XCTAssertEqual(definition.mode, .fm)
    XCTAssertEqual(definition.rangeHz, 162_400_000...162_550_000)
    XCTAssertEqual(definition.stepOptionsHz, [5_000, 10_000, 12_500, 25_000])
    XCTAssertEqual(definition.defaultStepHz, 25_000)
    XCTAssertEqual(definition.metadataProfileBand, .noaa)
  }
}
