import XCTest
@testable import ListenSDR

final class FMDXBandScannerTests: XCTestCase {
  func testAvailablePresetsHideAMRangesWhenUnsupported() {
    XCTAssertEqual(
      FMDXBandScanRangePreset.availableCases(supportsAM: false),
      [.lowerUKF, .upperUKF, .fullUKF, .noaa]
    )
  }

  func testAvailablePresetsExposeAllNamedRangesWhenAMIsSupported() {
    XCTAssertEqual(
      FMDXBandScanRangePreset.availableCases(supportsAM: true),
      [.lowerUKF, .upperUKF, .fullUKF, .noaa, .sw, .mw, .lw]
    )
  }

  func testRangeDefinitionsMatchExpectedFMSpans() {
    XCTAssertEqual(FMDXBandScanRangePreset.lowerUKF.definition.rangeHz, 65_900_000...73_999_000)
    XCTAssertEqual(FMDXBandScanRangePreset.upperUKF.definition.rangeHz, 87_500_000...108_000_000)
    XCTAssertEqual(FMDXBandScanRangePreset.fullUKF.definition.rangeHz, FMDXQuickBand.fm.rangeHz)
  }

  func testSequenceBuilderStartsFromCurrentFrequencyWithWrap() {
    let frequencies = FMDXBandScanSequenceBuilder.buildFrequencies(
      in: 87_500_000...87_900_000,
      stepHz: 100_000,
      startBehavior: .fromCurrentFrequency,
      currentFrequencyHz: 87_700_000
    )

    XCTAssertEqual(
      frequencies,
      [87_700_000, 87_800_000, 87_900_000, 87_500_000, 87_600_000]
    )
  }

  func testSequenceBuilderFallsBackToRangeStartWhenCurrentFrequencyIsOutsideRange() {
    let frequencies = FMDXBandScanSequenceBuilder.buildFrequencies(
      in: 520_000...547_000,
      stepHz: 9_000,
      startBehavior: .fromCurrentFrequency,
      currentFrequencyHz: 999_000
    )

    XCTAssertEqual(frequencies, [520_000, 529_000, 538_000, 547_000])
  }

  func testMetadataWindowIsReservedForFMBands() {
    XCTAssertEqual(FMDXQuickBand.lw.scannerMetadataWindowSeconds, 0)
    XCTAssertEqual(FMDXQuickBand.mw.scannerMetadataWindowSeconds, 0)
    XCTAssertEqual(FMDXQuickBand.sw.scannerMetadataWindowSeconds, 0)
    XCTAssertGreaterThan(FMDXQuickBand.oirt.scannerMetadataWindowSeconds, 0)
    XCTAssertGreaterThan(FMDXQuickBand.fm.scannerMetadataWindowSeconds, 0)
  }

  func testQuickModeUsesShorterTuneLockThanStandard() {
    let standardProfile = FMDXBandScanMode.standard.timingProfile(
      for: .fm,
      settings: .default
    )
    let quickProfile = FMDXBandScanMode.quickNewSignals.timingProfile(
      for: .fm,
      settings: .default
    )

    XCTAssertEqual(standardProfile.tuneAttemptCount, 2)
    XCTAssertEqual(quickProfile.tuneAttemptCount, 1)
    XCTAssertLessThan(
      quickProfile.settleSeconds,
      standardProfile.settleSeconds
    )
    XCTAssertLessThan(
      quickProfile.minimumDeadlineSeconds,
      standardProfile.minimumDeadlineSeconds
    )
    XCTAssertGreaterThan(quickProfile.confirmationGraceSeconds, 0)
  }

  func testSelectableModesKeepRequestedOrderWhenSavedResultsAreEnabled() {
    XCTAssertEqual(
      FMDXBandScanMode.selectableCases(saveResultsEnabled: true),
      [.standard, .quickNewSignals, .veryFast, .custom]
    )
  }

  func testSelectableModesHideQuickNewSignalsWithoutSavedResults() {
    XCTAssertEqual(
      FMDXBandScanMode.selectableCases(saveResultsEnabled: false),
      [.standard, .veryFast, .custom]
    )
  }

  func testVeryFastModeUsesMoreAggressiveTimingThanQuickMode() {
    let quickProfile = FMDXBandScanMode.quickNewSignals.timingProfile(
      for: .fm,
      settings: .default
    )
    let veryFastProfile = FMDXBandScanMode.veryFast.timingProfile(
      for: .fm,
      settings: .default
    )

    XCTAssertLessThan(veryFastProfile.settleSeconds, quickProfile.settleSeconds)
    XCTAssertLessThan(veryFastProfile.minimumDeadlineSeconds, quickProfile.minimumDeadlineSeconds)
    XCTAssertEqual(veryFastProfile.metadataWindowSeconds, 0)
  }

  func testCustomModeUsesSettingsDrivenTiming() {
    var settings = RadioSessionSettings.default
    settings.fmdxCustomScanSettleSeconds = 0.27
    settings.fmdxCustomScanMetadataWindowSeconds = 1.35

    let profile = FMDXBandScanMode.custom.timingProfile(
      for: .fm,
      settings: settings
    )

    XCTAssertEqual(profile.tuneAttemptCount, 1)
    XCTAssertEqual(profile.settleSeconds, 0.27, accuracy: 0.0001)
    XCTAssertEqual(profile.metadataWindowSeconds, 1.35, accuracy: 0.0001)
    XCTAssertGreaterThan(profile.minimumDeadlineSeconds, profile.settleSeconds)
  }

  func testReducerMergesNearbyFMPeaksIntoSingleResult() {
    let samples = [
      FMDXBandScanSample(
        frequencyHz: 98_300_000,
        mode: .fm,
        signal: 18,
        signalTop: nil,
        stationName: nil,
        programService: "RAVE FM",
        radioText0: nil,
        radioText1: nil,
        city: nil,
        countryName: nil,
        userCount: nil
      ),
      FMDXBandScanSample(
        frequencyHz: 98_400_000,
        mode: .fm,
        signal: 27,
        signalTop: nil,
        stationName: "Rave FM",
        programService: "RAVE FM",
        radioText0: nil,
        radioText1: nil,
        city: "Bytom",
        countryName: "Poland",
        distanceKm: "105",
        erpKW: "120",
        userCount: 2
      ),
      FMDXBandScanSample(
        frequencyHz: 98_500_000,
        mode: .fm,
        signal: 21,
        signalTop: nil,
        stationName: nil,
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: nil,
        countryName: nil,
        userCount: nil
      )
    ]

    let results = FMDXBandScanReducer.reduce(
      samples: samples,
      mergeSpacingHz: 150_000
    )

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.frequencyHz, 98_400_000)
    XCTAssertEqual(results.first?.stationName, "Rave FM")
    XCTAssertEqual(results.first?.city, "Bytom")
    XCTAssertEqual(results.first?.countryName, "Poland")
    XCTAssertEqual(results.first?.distanceKm, "105")
    XCTAssertEqual(results.first?.erpKW, "120")
  }

  func testReducerKeepsSeparateResultsForDistantPeaks() {
    let samples = [
      FMDXBandScanSample(
        frequencyHz: 89_100_000,
        mode: .fm,
        signal: 23,
        signalTop: nil,
        stationName: "Relax",
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: nil,
        countryName: nil,
        userCount: nil
      ),
      FMDXBandScanSample(
        frequencyHz: 94_200_000,
        mode: .fm,
        signal: 26,
        signalTop: nil,
        stationName: "Pulsar",
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: nil,
        countryName: nil,
        userCount: nil
      )
    ]

    let results = FMDXBandScanReducer.reduce(
      samples: samples,
      mergeSpacingHz: 150_000
    )

    XCTAssertEqual(results.map(\.frequencyHz), [89_100_000, 94_200_000])
  }

  func testReducerKeepsMetadataFromClusterEvenIfStrongestPointHasNone() {
    let samples = [
      FMDXBandScanSample(
        frequencyHz: 999_000,
        mode: .am,
        signal: 12,
        signalTop: nil,
        stationName: "Test MW",
        programService: nil,
        radioText0: "News",
        radioText1: "Service",
        city: "Krakow",
        countryName: "Poland",
        distanceKm: "12",
        erpKW: "50",
        userCount: 1
      ),
      FMDXBandScanSample(
        frequencyHz: 1_008_000,
        mode: .am,
        signal: 14,
        signalTop: nil,
        stationName: nil,
        programService: nil,
        radioText0: nil,
        radioText1: nil,
        city: nil,
        countryName: nil,
        userCount: nil
      )
    ]

    let results = FMDXBandScanReducer.reduce(
      samples: samples,
      mergeSpacingHz: 18_000
    )

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.frequencyHz, 1_008_000)
    XCTAssertEqual(results.first?.stationName, "Test MW")
    XCTAssertEqual(results.first?.radioText0, "News")
    XCTAssertEqual(results.first?.radioText1, "Service")
    XCTAssertEqual(results.first?.city, "Krakow")
    XCTAssertEqual(results.first?.distanceKm, "12")
    XCTAssertEqual(results.first?.erpKW, "50")
  }

  func testSavedResultMatcherTreatsKnownStationWithinToleranceAsSameSignal() {
    let saved = FMDXBandScanResult(
      frequencyHz: 98_400_000,
      mode: .fm,
      signal: 24,
      signalTop: nil,
      stationName: "Rave FM",
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )
    let rescanned = FMDXBandScanResult(
      frequencyHz: 98_450_000,
      mode: .fm,
      signal: 21,
      signalTop: nil,
      stationName: "  rave   fm ",
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )

    XCTAssertTrue(FMDXSavedScanResultMatcher.isSameResult(saved, rescanned))
  }

  func testSavedResultMatcherKeepsDifferentStationIdentityAsNewSignal() {
    let saved = FMDXBandScanResult(
      frequencyHz: 98_400_000,
      mode: .fm,
      signal: 24,
      signalTop: nil,
      stationName: "Rave FM",
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )
    let newSignal = FMDXBandScanResult(
      frequencyHz: 98_430_000,
      mode: .fm,
      signal: 20,
      signalTop: nil,
      stationName: "Rise FM",
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )

    XCTAssertEqual(
      FMDXSavedScanResultMatcher.filterNewResults([newSignal], comparedTo: [saved]),
      [newSignal]
    )
  }

  func testSavedResultMatcherUsesBandSpecificToleranceForAM() {
    let saved = FMDXBandScanResult(
      frequencyHz: 999_000,
      mode: .am,
      signal: 12,
      signalTop: nil,
      stationName: nil,
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )
    let nearby = FMDXBandScanResult(
      frequencyHz: 1_003_000,
      mode: .am,
      signal: 13,
      signalTop: nil,
      stationName: nil,
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )
    let distant = FMDXBandScanResult(
      frequencyHz: 1_006_000,
      mode: .am,
      signal: 13,
      signalTop: nil,
      stationName: nil,
      programService: nil,
      radioText0: nil,
      radioText1: nil,
      city: nil,
      countryName: nil,
      userCount: nil
    )

    XCTAssertTrue(FMDXSavedScanResultMatcher.isSameResult(saved, nearby))
    XCTAssertFalse(FMDXSavedScanResultMatcher.isSameResult(saved, distant))
  }
}
