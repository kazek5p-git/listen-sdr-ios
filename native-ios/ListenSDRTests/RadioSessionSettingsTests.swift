import XCTest
@testable import ListenSDR

final class RadioSessionSettingsTests: XCTestCase {
  func testKiwiPassbandIsStoredPerNormalizedMode() {
    var settings = RadioSessionSettings.default

    settings.setKiwiPassband(
      ReceiverBandpass(lowCut: 450, highCut: 2_850),
      for: .usb,
      sampleRateHz: 12_000
    )
    settings.setKiwiPassband(
      ReceiverBandpass(lowCut: -2_850, highCut: -450),
      for: .lsb,
      sampleRateHz: 12_000
    )

    XCTAssertEqual(
      settings.kiwiPassband(for: .usb, sampleRateHz: 12_000),
      ReceiverBandpass(lowCut: 450, highCut: 2_850)
    )
    XCTAssertEqual(
      settings.kiwiPassband(for: .lsb, sampleRateHz: 12_000),
      ReceiverBandpass(lowCut: -2_850, highCut: -450)
    )
  }

  func testKiwiPassbandNormalizationClampsToSampleRateLimits() {
    let normalized = RadioSessionSettings.normalizedKiwiBandpass(
      ReceiverBandpass(lowCut: -8_500, highCut: 8_500),
      mode: .amw,
      sampleRateHz: 12_000
    )

    XCTAssertEqual(normalized, ReceiverBandpass(lowCut: -6_000, highCut: 6_000))
  }

  func testResetKiwiPassbandFallsBackToModeDefault() {
    var settings = RadioSessionSettings.default
    settings.setKiwiPassband(
      ReceiverBandpass(lowCut: 500, highCut: 2_900),
      for: .usb,
      sampleRateHz: 12_000
    )

    settings.resetKiwiPassband(for: .usb)

    XCTAssertEqual(
      settings.kiwiPassband(for: .usb, sampleRateHz: 12_000),
      DemodulationMode.usb.kiwiDefaultBandpass
    )
  }

  func testKiwiNoiseBlankerNormalizationClampsAndKeepsOddSampleCount() {
    let settings = RadioSessionSettings(
      frequencyHz: RadioSessionSettings.default.frequencyHz,
      tuneStepHz: RadioSessionSettings.default.tuneStepHz,
      preferredTuneStepHz: RadioSessionSettings.default.preferredTuneStepHz,
      mode: .am,
      rfGain: RadioSessionSettings.default.rfGain,
      audioVolume: RadioSessionSettings.default.audioVolume,
      audioMuted: RadioSessionSettings.default.audioMuted,
      agcEnabled: RadioSessionSettings.default.agcEnabled,
      imsEnabled: RadioSessionSettings.default.imsEnabled,
      noiseReductionEnabled: RadioSessionSettings.default.noiseReductionEnabled,
      squelchEnabled: RadioSessionSettings.default.squelchEnabled,
      openWebRXSquelchLevel: RadioSessionSettings.default.openWebRXSquelchLevel,
      kiwiSquelchThreshold: RadioSessionSettings.default.kiwiSquelchThreshold,
      kiwiNoiseBlankerAlgorithm: .wild,
      kiwiNoiseBlankerGate: 5_555,
      kiwiNoiseBlankerThreshold: 200,
      kiwiNoiseBlankerWildThreshold: 3.4,
      kiwiNoiseBlankerWildTaps: 99,
      kiwiNoiseBlankerWildImpulseSamples: 8,
      kiwiNoiseFilterAlgorithm: .off,
      kiwiDenoiseEnabled: false,
      kiwiAutonotchEnabled: false,
      kiwiPassbandsByMode: [:],
      kiwiWaterfallSpeed: RadioSessionSettings.default.kiwiWaterfallSpeed,
      kiwiWaterfallWindowFunction: RadioSessionSettings.default.kiwiWaterfallWindowFunction,
      kiwiWaterfallInterpolation: RadioSessionSettings.default.kiwiWaterfallInterpolation,
      kiwiWaterfallCICCompensation: RadioSessionSettings.default.kiwiWaterfallCICCompensation,
      kiwiWaterfallZoom: RadioSessionSettings.default.kiwiWaterfallZoom,
      kiwiWaterfallPanOffsetBins: RadioSessionSettings.default.kiwiWaterfallPanOffsetBins,
      kiwiWaterfallMinDB: RadioSessionSettings.default.kiwiWaterfallMinDB,
      kiwiWaterfallMaxDB: RadioSessionSettings.default.kiwiWaterfallMaxDB,
      showRdsErrorCounters: RadioSessionSettings.default.showRdsErrorCounters,
      voiceOverRDSAnnouncementMode: RadioSessionSettings.default.voiceOverRDSAnnouncementMode,
      dxNightModeEnabled: RadioSessionSettings.default.dxNightModeEnabled,
      autoFilterProfileEnabled: RadioSessionSettings.default.autoFilterProfileEnabled,
      adaptiveScannerEnabled: RadioSessionSettings.default.adaptiveScannerEnabled,
      scannerDwellSeconds: RadioSessionSettings.default.scannerDwellSeconds,
      scannerHoldSeconds: RadioSessionSettings.default.scannerHoldSeconds,
      fmdxAudioStartupBufferSeconds: RadioSessionSettings.default.fmdxAudioStartupBufferSeconds,
      fmdxAudioMaxLatencySeconds: RadioSessionSettings.default.fmdxAudioMaxLatencySeconds,
      fmdxAudioPacketHoldSeconds: RadioSessionSettings.default.fmdxAudioPacketHoldSeconds,
      audioSuggestionScope: RadioSessionSettings.default.audioSuggestionScope,
      tuningGestureDirection: RadioSessionSettings.default.tuningGestureDirection,
      openReceiverAfterHistoryRestore: RadioSessionSettings.default.openReceiverAfterHistoryRestore,
      autoConnectSelectedProfileOnLaunch: RadioSessionSettings.default.autoConnectSelectedProfileOnLaunch
    )

    XCTAssertEqual(settings.kiwiNoiseBlankerGate, 5_000)
    XCTAssertEqual(settings.kiwiNoiseBlankerThreshold, 100)
    XCTAssertEqual(settings.kiwiNoiseBlankerWildThreshold, 3.0, accuracy: 0.0001)
    XCTAssertEqual(settings.kiwiNoiseBlankerWildTaps, 40)
    XCTAssertEqual(settings.kiwiNoiseBlankerWildImpulseSamples, 9)
  }

  func testKiwiSpectralNoiseFilterForcesDenoiserAndDisablesAutonotch() {
    let settings = RadioSessionSettings(
      frequencyHz: RadioSessionSettings.default.frequencyHz,
      tuneStepHz: RadioSessionSettings.default.tuneStepHz,
      preferredTuneStepHz: RadioSessionSettings.default.preferredTuneStepHz,
      mode: .am,
      rfGain: RadioSessionSettings.default.rfGain,
      audioVolume: RadioSessionSettings.default.audioVolume,
      audioMuted: RadioSessionSettings.default.audioMuted,
      agcEnabled: RadioSessionSettings.default.agcEnabled,
      imsEnabled: RadioSessionSettings.default.imsEnabled,
      noiseReductionEnabled: RadioSessionSettings.default.noiseReductionEnabled,
      squelchEnabled: RadioSessionSettings.default.squelchEnabled,
      openWebRXSquelchLevel: RadioSessionSettings.default.openWebRXSquelchLevel,
      kiwiSquelchThreshold: RadioSessionSettings.default.kiwiSquelchThreshold,
      kiwiNoiseBlankerAlgorithm: .off,
      kiwiNoiseBlankerGate: RadioSessionSettings.default.kiwiNoiseBlankerGate,
      kiwiNoiseBlankerThreshold: RadioSessionSettings.default.kiwiNoiseBlankerThreshold,
      kiwiNoiseBlankerWildThreshold: RadioSessionSettings.default.kiwiNoiseBlankerWildThreshold,
      kiwiNoiseBlankerWildTaps: RadioSessionSettings.default.kiwiNoiseBlankerWildTaps,
      kiwiNoiseBlankerWildImpulseSamples: RadioSessionSettings.default.kiwiNoiseBlankerWildImpulseSamples,
      kiwiNoiseFilterAlgorithm: .spectral,
      kiwiDenoiseEnabled: false,
      kiwiAutonotchEnabled: true,
      kiwiPassbandsByMode: [:],
      kiwiWaterfallSpeed: RadioSessionSettings.default.kiwiWaterfallSpeed,
      kiwiWaterfallWindowFunction: RadioSessionSettings.default.kiwiWaterfallWindowFunction,
      kiwiWaterfallInterpolation: RadioSessionSettings.default.kiwiWaterfallInterpolation,
      kiwiWaterfallCICCompensation: RadioSessionSettings.default.kiwiWaterfallCICCompensation,
      kiwiWaterfallZoom: RadioSessionSettings.default.kiwiWaterfallZoom,
      kiwiWaterfallPanOffsetBins: RadioSessionSettings.default.kiwiWaterfallPanOffsetBins,
      kiwiWaterfallMinDB: RadioSessionSettings.default.kiwiWaterfallMinDB,
      kiwiWaterfallMaxDB: RadioSessionSettings.default.kiwiWaterfallMaxDB,
      showRdsErrorCounters: RadioSessionSettings.default.showRdsErrorCounters,
      voiceOverRDSAnnouncementMode: RadioSessionSettings.default.voiceOverRDSAnnouncementMode,
      dxNightModeEnabled: RadioSessionSettings.default.dxNightModeEnabled,
      autoFilterProfileEnabled: RadioSessionSettings.default.autoFilterProfileEnabled,
      adaptiveScannerEnabled: RadioSessionSettings.default.adaptiveScannerEnabled,
      scannerDwellSeconds: RadioSessionSettings.default.scannerDwellSeconds,
      scannerHoldSeconds: RadioSessionSettings.default.scannerHoldSeconds,
      fmdxAudioStartupBufferSeconds: RadioSessionSettings.default.fmdxAudioStartupBufferSeconds,
      fmdxAudioMaxLatencySeconds: RadioSessionSettings.default.fmdxAudioMaxLatencySeconds,
      fmdxAudioPacketHoldSeconds: RadioSessionSettings.default.fmdxAudioPacketHoldSeconds,
      audioSuggestionScope: RadioSessionSettings.default.audioSuggestionScope,
      tuningGestureDirection: RadioSessionSettings.default.tuningGestureDirection,
      openReceiverAfterHistoryRestore: RadioSessionSettings.default.openReceiverAfterHistoryRestore,
      autoConnectSelectedProfileOnLaunch: RadioSessionSettings.default.autoConnectSelectedProfileOnLaunch
    )

    XCTAssertTrue(settings.kiwiDenoiseEnabled)
    XCTAssertFalse(settings.kiwiAutonotchEnabled)
  }

  func testKiwiWaterfallSpeedNormalizationSupportsOfficialValuesAndLegacyFastValue() {
    XCTAssertEqual(
      RadioSessionSettings.normalizedKiwiWaterfallSpeed(KiwiWaterfallRate.off.rawValue),
      KiwiWaterfallRate.off.rawValue
    )
    XCTAssertEqual(
      RadioSessionSettings.normalizedKiwiWaterfallSpeed(KiwiWaterfallRate.fast.rawValue),
      KiwiWaterfallRate.fast.rawValue
    )
    XCTAssertEqual(
      RadioSessionSettings.normalizedKiwiWaterfallSpeed(8),
      KiwiWaterfallRate.fast.rawValue
    )
  }

  func testKiwiWaterfallFFTDefaultsMatchOfficialUpstreamDefaults() {
    XCTAssertEqual(
      RadioSessionSettings.default.kiwiWaterfallWindowFunction,
      KiwiWaterfallWindowFunction.blackmanHarris.rawValue
    )
    XCTAssertEqual(
      RadioSessionSettings.default.kiwiWaterfallInterpolation,
      KiwiWaterfallInterpolation.dropSamples.rawValue
    )
    XCTAssertTrue(RadioSessionSettings.default.kiwiWaterfallCICCompensation)
  }

  func testKiwiWaterfallPanOffsetIsClamped() {
    let settings = RadioSessionSettings(
      frequencyHz: RadioSessionSettings.default.frequencyHz,
      tuneStepHz: RadioSessionSettings.default.tuneStepHz,
      preferredTuneStepHz: RadioSessionSettings.default.preferredTuneStepHz,
      mode: .am,
      rfGain: RadioSessionSettings.default.rfGain,
      audioVolume: RadioSessionSettings.default.audioVolume,
      audioMuted: RadioSessionSettings.default.audioMuted,
      agcEnabled: RadioSessionSettings.default.agcEnabled,
      imsEnabled: RadioSessionSettings.default.imsEnabled,
      noiseReductionEnabled: RadioSessionSettings.default.noiseReductionEnabled,
      squelchEnabled: RadioSessionSettings.default.squelchEnabled,
      openWebRXSquelchLevel: RadioSessionSettings.default.openWebRXSquelchLevel,
      kiwiSquelchThreshold: RadioSessionSettings.default.kiwiSquelchThreshold,
      kiwiNoiseBlankerAlgorithm: RadioSessionSettings.default.kiwiNoiseBlankerAlgorithm,
      kiwiNoiseBlankerGate: RadioSessionSettings.default.kiwiNoiseBlankerGate,
      kiwiNoiseBlankerThreshold: RadioSessionSettings.default.kiwiNoiseBlankerThreshold,
      kiwiNoiseBlankerWildThreshold: RadioSessionSettings.default.kiwiNoiseBlankerWildThreshold,
      kiwiNoiseBlankerWildTaps: RadioSessionSettings.default.kiwiNoiseBlankerWildTaps,
      kiwiNoiseBlankerWildImpulseSamples: RadioSessionSettings.default.kiwiNoiseBlankerWildImpulseSamples,
      kiwiNoiseFilterAlgorithm: RadioSessionSettings.default.kiwiNoiseFilterAlgorithm,
      kiwiDenoiseEnabled: RadioSessionSettings.default.kiwiDenoiseEnabled,
      kiwiAutonotchEnabled: RadioSessionSettings.default.kiwiAutonotchEnabled,
      kiwiPassbandsByMode: RadioSessionSettings.default.kiwiPassbandsByMode,
      kiwiWaterfallSpeed: RadioSessionSettings.default.kiwiWaterfallSpeed,
      kiwiWaterfallWindowFunction: RadioSessionSettings.default.kiwiWaterfallWindowFunction,
      kiwiWaterfallInterpolation: RadioSessionSettings.default.kiwiWaterfallInterpolation,
      kiwiWaterfallCICCompensation: RadioSessionSettings.default.kiwiWaterfallCICCompensation,
      kiwiWaterfallZoom: RadioSessionSettings.default.kiwiWaterfallZoom,
      kiwiWaterfallPanOffsetBins: 999_999_999,
      kiwiWaterfallMinDB: RadioSessionSettings.default.kiwiWaterfallMinDB,
      kiwiWaterfallMaxDB: RadioSessionSettings.default.kiwiWaterfallMaxDB,
      showRdsErrorCounters: RadioSessionSettings.default.showRdsErrorCounters,
      voiceOverRDSAnnouncementMode: RadioSessionSettings.default.voiceOverRDSAnnouncementMode,
      dxNightModeEnabled: RadioSessionSettings.default.dxNightModeEnabled,
      autoFilterProfileEnabled: RadioSessionSettings.default.autoFilterProfileEnabled,
      adaptiveScannerEnabled: RadioSessionSettings.default.adaptiveScannerEnabled,
      scannerDwellSeconds: RadioSessionSettings.default.scannerDwellSeconds,
      scannerHoldSeconds: RadioSessionSettings.default.scannerHoldSeconds,
      fmdxAudioStartupBufferSeconds: RadioSessionSettings.default.fmdxAudioStartupBufferSeconds,
      fmdxAudioMaxLatencySeconds: RadioSessionSettings.default.fmdxAudioMaxLatencySeconds,
      fmdxAudioPacketHoldSeconds: RadioSessionSettings.default.fmdxAudioPacketHoldSeconds,
      audioSuggestionScope: RadioSessionSettings.default.audioSuggestionScope,
      tuningGestureDirection: RadioSessionSettings.default.tuningGestureDirection,
      openReceiverAfterHistoryRestore: RadioSessionSettings.default.openReceiverAfterHistoryRestore,
      autoConnectSelectedProfileOnLaunch: RadioSessionSettings.default.autoConnectSelectedProfileOnLaunch
    )

    XCTAssertEqual(settings.kiwiWaterfallPanOffsetBins, 50_000_000)
  }

  func testFMDXTuneConfirmationWarningsDefaultToDisabledAndRoundTrip() throws {
    XCTAssertFalse(RadioSessionSettings.default.fmdxTuneConfirmationWarningsEnabled)

    var settings = RadioSessionSettings.default
    settings.fmdxTuneConfirmationWarningsEnabled = true

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertTrue(decoded.fmdxTuneConfirmationWarningsEnabled)
  }

  func testFMDXCustomScannerSettingsRoundTripAndClamp() throws {
    var settings = RadioSessionSettings.default
    settings.fmdxCustomScanSettleSeconds = RadioSessionSettings.clampedFMDXCustomScanSettleSeconds(0.72)
    settings.fmdxCustomScanMetadataWindowSeconds =
      RadioSessionSettings.clampedFMDXCustomScanMetadataWindowSeconds(2.8)

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertEqual(decoded.fmdxCustomScanSettleSeconds, 0.60, accuracy: 0.0001)
    XCTAssertEqual(decoded.fmdxCustomScanMetadataWindowSeconds, 2.0, accuracy: 0.0001)
  }

  func testTuneStepPreferenceModeDefaultsToManualAndRoundTrips() throws {
    XCTAssertEqual(RadioSessionSettings.default.tuneStepPreferenceMode, .manual)

    var settings = RadioSessionSettings.default
    settings.tuneStepPreferenceMode = .automatic

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertEqual(decoded.tuneStepPreferenceMode, .automatic)
  }

  func testMixWithOtherAudioAppsDefaultsToDisabledAndRoundTrips() throws {
    XCTAssertFalse(RadioSessionSettings.default.mixWithOtherAudioApps)

    var settings = RadioSessionSettings.default
    settings.mixWithOtherAudioApps = true

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertTrue(decoded.mixWithOtherAudioApps)
  }

  func testMagicTapActionDefaultsToToggleMuteAndRoundTrips() throws {
    XCTAssertEqual(RadioSessionSettings.default.magicTapAction, .toggleMute)

    var settings = RadioSessionSettings.default
    settings.magicTapAction = .toggleRecording

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertEqual(decoded.magicTapAction, .toggleRecording)
  }

  func testMagicTapActionDefaultsWhenDecodingLegacySettingsWithoutStoredValue() throws {
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: Data("{}".utf8))

    XCTAssertEqual(decoded.magicTapAction, .toggleMute)
  }

  func testMagicTapActionDecodesLegacyStopRecordingOrMuteValueAsToggleRecording() throws {
    let decoded = try JSONDecoder().decode(
      RadioSessionSettings.self,
      from: Data(#"{"magicTapAction":"stopRecordingIfActiveOtherwiseToggleMute"}"#.utf8)
    )

    XCTAssertEqual(decoded.magicTapAction, .toggleRecording)
  }

  func testAccessibilityInteractionSoundsDefaultToDisabledAndRoundTrip() throws {
    XCTAssertFalse(RadioSessionSettings.default.accessibilityInteractionSoundsEnabled)

    var settings = RadioSessionSettings.default
    settings.accessibilityInteractionSoundsEnabled = true

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertTrue(decoded.accessibilityInteractionSoundsEnabled)
  }

  func testAccessibilityInteractionSoundsVolumeDefaultsToOneAndRoundTrip() throws {
    XCTAssertEqual(RadioSessionSettings.default.accessibilityInteractionSoundsVolume, 1.0, accuracy: 0.0001)

    var settings = RadioSessionSettings.default
    settings.accessibilityInteractionSoundsVolume = 1.85

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertEqual(decoded.accessibilityInteractionSoundsVolume, 1.85, accuracy: 0.0001)
  }

  func testAccessibilityInteractionSoundsVolumeClampsWhenDecodingOutOfRangeValue() throws {
    let decoded = try JSONDecoder().decode(
      RadioSessionSettings.self,
      from: Data(#"{"accessibilityInteractionSoundsVolume":3.1}"#.utf8)
    )

    XCTAssertEqual(decoded.accessibilityInteractionSoundsVolume, 2.5, accuracy: 0.0001)
  }

  func testAccessibilityInteractionSoundsMutedDuringRecordingDefaultsToDisabledAndRoundTrip() throws {
    XCTAssertFalse(RadioSessionSettings.default.accessibilityInteractionSoundsMutedDuringRecording)

    var settings = RadioSessionSettings.default
    settings.accessibilityInteractionSoundsMutedDuringRecording = true

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertTrue(decoded.accessibilityInteractionSoundsMutedDuringRecording)
  }

  func testAccessibilitySelectionAnnouncementsDefaultToDisabledAndRoundTrip() throws {
    XCTAssertFalse(RadioSessionSettings.default.accessibilitySelectionAnnouncementsEnabled)

    var settings = RadioSessionSettings.default
    settings.accessibilitySelectionAnnouncementsEnabled = true

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertTrue(decoded.accessibilitySelectionAnnouncementsEnabled)
  }

  func testShowTutorialOnLaunchDefaultsToEnabledAndRoundTrip() throws {
    XCTAssertTrue(RadioSessionSettings.default.showTutorialOnLaunchEnabled)

    var settings = RadioSessionSettings.default
    settings.showTutorialOnLaunchEnabled = false

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertFalse(decoded.showTutorialOnLaunchEnabled)
  }

  func testAccessibilityConnectionSoundsDefaultToDisabledAndRoundTrip() throws {
    XCTAssertFalse(RadioSessionSettings.default.accessibilityConnectionSoundsEnabled)

    var settings = RadioSessionSettings.default
    settings.accessibilityConnectionSoundsEnabled = true

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertTrue(decoded.accessibilityConnectionSoundsEnabled)
  }

  func testAccessibilityRecordingSoundsDefaultToEnabledAndRoundTrip() throws {
    XCTAssertTrue(RadioSessionSettings.default.accessibilityRecordingSoundsEnabled)

    var settings = RadioSessionSettings.default
    settings.accessibilityRecordingSoundsEnabled = false

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertFalse(decoded.accessibilityRecordingSoundsEnabled)
  }

  func testRememberSquelchOnConnectDefaultsToEnabledAndRoundTrip() throws {
    XCTAssertTrue(RadioSessionSettings.default.rememberSquelchOnConnectEnabled)

    var settings = RadioSessionSettings.default
    settings.rememberSquelchOnConnectEnabled = false

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertFalse(decoded.rememberSquelchOnConnectEnabled)
  }

  func testRadiosSearchFiltersVisibilityDefaultsToAlwaysVisibleAndRoundTrips() throws {
    XCTAssertEqual(RadioSessionSettings.default.radiosSearchFiltersVisibility, .alwaysVisible)

    var settings = RadioSessionSettings.default
    settings.radiosSearchFiltersVisibility = .whileSearchFieldActive

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertEqual(decoded.radiosSearchFiltersVisibility, .whileSearchFieldActive)
  }

  func testRecentFrequenciesSettingsHaveExpectedDefaultsAndRoundTrip() throws {
    XCTAssertTrue(RadioSessionSettings.default.showRecentFrequencies)
    XCTAssertFalse(RadioSessionSettings.default.includeRecentFrequenciesFromOtherReceivers)
    XCTAssertTrue(RadioSessionSettings.default.playDetectedChannelScannerSignalsEnabled)
    XCTAssertFalse(RadioSessionSettings.default.saveChannelScannerResultsEnabled)
    XCTAssertFalse(RadioSessionSettings.default.stopChannelScannerOnSignal)
    XCTAssertFalse(RadioSessionSettings.default.filterChannelScannerInterferenceEnabled)
    XCTAssertEqual(RadioSessionSettings.default.channelScannerInterferenceFilterProfile, .standard)

    var settings = RadioSessionSettings.default
    settings.showRecentFrequencies = false
    settings.includeRecentFrequenciesFromOtherReceivers = true
    settings.playDetectedChannelScannerSignalsEnabled = false
    settings.saveChannelScannerResultsEnabled = true
    settings.stopChannelScannerOnSignal = true
    settings.filterChannelScannerInterferenceEnabled = true
    settings.channelScannerInterferenceFilterProfile = .strong

    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RadioSessionSettings.self, from: encoded)

    XCTAssertFalse(decoded.showRecentFrequencies)
    XCTAssertTrue(decoded.includeRecentFrequenciesFromOtherReceivers)
    XCTAssertFalse(decoded.playDetectedChannelScannerSignalsEnabled)
    XCTAssertTrue(decoded.saveChannelScannerResultsEnabled)
    XCTAssertTrue(decoded.stopChannelScannerOnSignal)
    XCTAssertTrue(decoded.filterChannelScannerInterferenceEnabled)
    XCTAssertEqual(decoded.channelScannerInterferenceFilterProfile, .strong)
  }

  func testSharedNormalizationFixturesMatchCurrentIOSBehavior() throws {
    let fixture = try SharedRadioSessionSettingsNormalizationFixtureLoader.load()

    for testCase in fixture.cases {
      let decoded = try JSONDecoder().decode(
        RadioSessionSettings.self,
        from: Data(testCase.inputJSON.utf8)
      )

      assertExpectedSettings(
        decoded,
        expected: testCase.expected,
        label: testCase.label
      )
    }
  }

  func testCachedReceiverDataRoundTripsLastOpenWebRXBookmark() throws {
    let bookmark = SDRServerBookmark(
      id: "bookmark-1",
      name: "Test Bookmark",
      frequencyHz: 102_700_000,
      modulation: .fm,
      source: "test"
    )
    let cached = CachedReceiverData(
      openWebRXProfiles: [],
      selectedOpenWebRXProfileID: "profile-1",
      lastOpenWebRXBookmark: bookmark,
      serverBookmarks: [bookmark],
      openWebRXBandPlan: [],
      savedChannelScannerResults: [
        ChannelScannerResult(
          id: "102700000|fm",
          name: "Test Bookmark",
          frequencyHz: 102_700_000,
          mode: .fm,
          signal: -23,
          signalUnit: "dBFS",
          detectedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
      ],
      fmdxServerPresets: [],
      fmdxCapabilities: nil,
      fmdxSavedScanResults: [],
      savedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let encoded = try JSONEncoder().encode(cached)
    let decoded = try JSONDecoder().decode(CachedReceiverData.self, from: encoded)

    XCTAssertEqual(decoded.lastOpenWebRXBookmark, bookmark)
    XCTAssertEqual(decoded.savedChannelScannerResults.count, 1)
    XCTAssertEqual(decoded.savedChannelScannerResults.first?.signalUnit, "dBFS")
  }

  private func assertExpectedSettings(
    _ settings: RadioSessionSettings,
    expected: SharedRadioSessionSettingsNormalizationExpected,
    label: String
  ) {
    if let tuneStepHz = expected.tuneStepHz {
      XCTAssertEqual(settings.tuneStepHz, tuneStepHz, label)
    }
    if let preferredTuneStepHz = expected.preferredTuneStepHz {
      XCTAssertEqual(settings.preferredTuneStepHz, preferredTuneStepHz, label)
    }
    if let openWebRXSquelchLevel = expected.openWebRXSquelchLevel {
      XCTAssertEqual(settings.openWebRXSquelchLevel, openWebRXSquelchLevel, label)
    }
    if let kiwiSquelchThreshold = expected.kiwiSquelchThreshold {
      XCTAssertEqual(settings.kiwiSquelchThreshold, kiwiSquelchThreshold, label)
    }
    if let kiwiNoiseBlankerGate = expected.kiwiNoiseBlankerGate {
      XCTAssertEqual(settings.kiwiNoiseBlankerGate, kiwiNoiseBlankerGate, label)
    }
    if let kiwiNoiseBlankerThreshold = expected.kiwiNoiseBlankerThreshold {
      XCTAssertEqual(settings.kiwiNoiseBlankerThreshold, kiwiNoiseBlankerThreshold, label)
    }
    if let kiwiNoiseBlankerWildThreshold = expected.kiwiNoiseBlankerWildThreshold {
      XCTAssertEqual(settings.kiwiNoiseBlankerWildThreshold, kiwiNoiseBlankerWildThreshold, accuracy: 0.0001, label)
    }
    if let kiwiNoiseBlankerWildTaps = expected.kiwiNoiseBlankerWildTaps {
      XCTAssertEqual(settings.kiwiNoiseBlankerWildTaps, kiwiNoiseBlankerWildTaps, label)
    }
    if let kiwiNoiseBlankerWildImpulseSamples = expected.kiwiNoiseBlankerWildImpulseSamples {
      XCTAssertEqual(settings.kiwiNoiseBlankerWildImpulseSamples, kiwiNoiseBlankerWildImpulseSamples, label)
    }
    if let kiwiDenoiseEnabled = expected.kiwiDenoiseEnabled {
      XCTAssertEqual(settings.kiwiDenoiseEnabled, kiwiDenoiseEnabled, label)
    }
    if let kiwiAutonotchEnabled = expected.kiwiAutonotchEnabled {
      XCTAssertEqual(settings.kiwiAutonotchEnabled, kiwiAutonotchEnabled, label)
    }
    if let kiwiPassbandsByMode = expected.kiwiPassbandsByMode {
      XCTAssertEqual(settings.kiwiPassbandsByMode, kiwiPassbandsByMode, label)
    }
    if let kiwiWaterfallSpeed = expected.kiwiWaterfallSpeed {
      XCTAssertEqual(settings.kiwiWaterfallSpeed, kiwiWaterfallSpeed, label)
    }
    if let kiwiWaterfallWindowFunction = expected.kiwiWaterfallWindowFunction {
      XCTAssertEqual(settings.kiwiWaterfallWindowFunction, kiwiWaterfallWindowFunction, label)
    }
    if let kiwiWaterfallInterpolation = expected.kiwiWaterfallInterpolation {
      XCTAssertEqual(settings.kiwiWaterfallInterpolation, kiwiWaterfallInterpolation, label)
    }
    if let kiwiWaterfallZoom = expected.kiwiWaterfallZoom {
      XCTAssertEqual(settings.kiwiWaterfallZoom, kiwiWaterfallZoom, label)
    }
    if let kiwiWaterfallPanOffsetBins = expected.kiwiWaterfallPanOffsetBins {
      XCTAssertEqual(settings.kiwiWaterfallPanOffsetBins, kiwiWaterfallPanOffsetBins, label)
    }
    if let kiwiWaterfallMinDB = expected.kiwiWaterfallMinDB {
      XCTAssertEqual(settings.kiwiWaterfallMinDB, kiwiWaterfallMinDB, label)
    }
    if let kiwiWaterfallMaxDB = expected.kiwiWaterfallMaxDB {
      XCTAssertEqual(settings.kiwiWaterfallMaxDB, kiwiWaterfallMaxDB, label)
    }
    if let accessibilityInteractionSoundsVolume = expected.accessibilityInteractionSoundsVolume {
      XCTAssertEqual(
        settings.accessibilityInteractionSoundsVolume,
        accessibilityInteractionSoundsVolume,
        accuracy: 0.0001,
        label
      )
    }
    if let scannerDwellSeconds = expected.scannerDwellSeconds {
      XCTAssertEqual(settings.scannerDwellSeconds, scannerDwellSeconds, accuracy: 0.0001, label)
    }
    if let scannerHoldSeconds = expected.scannerHoldSeconds {
      XCTAssertEqual(settings.scannerHoldSeconds, scannerHoldSeconds, accuracy: 0.0001, label)
    }
    if let fmdxAudioStartupBufferSeconds = expected.fmdxAudioStartupBufferSeconds {
      XCTAssertEqual(settings.fmdxAudioStartupBufferSeconds, fmdxAudioStartupBufferSeconds, accuracy: 0.0001, label)
    }
    if let fmdxAudioMaxLatencySeconds = expected.fmdxAudioMaxLatencySeconds {
      XCTAssertEqual(settings.fmdxAudioMaxLatencySeconds, fmdxAudioMaxLatencySeconds, accuracy: 0.0001, label)
    }
    if let fmdxAudioPacketHoldSeconds = expected.fmdxAudioPacketHoldSeconds {
      XCTAssertEqual(settings.fmdxAudioPacketHoldSeconds, fmdxAudioPacketHoldSeconds, accuracy: 0.0001, label)
    }
    if let fmdxCustomScanSettleSeconds = expected.fmdxCustomScanSettleSeconds {
      XCTAssertEqual(settings.fmdxCustomScanSettleSeconds, fmdxCustomScanSettleSeconds, accuracy: 0.0001, label)
    }
    if let fmdxCustomScanMetadataWindowSeconds = expected.fmdxCustomScanMetadataWindowSeconds {
      XCTAssertEqual(
        settings.fmdxCustomScanMetadataWindowSeconds,
        fmdxCustomScanMetadataWindowSeconds,
        accuracy: 0.0001,
        label
      )
    }
  }
}

private struct SharedRadioSessionSettingsNormalizationFixtureSet: Decodable {
  let cases: [Case]

  struct Case: Decodable {
    let label: String
    let inputJSON: String
    let expected: SharedRadioSessionSettingsNormalizationExpected
  }
}

private struct SharedRadioSessionSettingsNormalizationExpected: Decodable {
  let tuneStepHz: Int?
  let preferredTuneStepHz: Int?
  let openWebRXSquelchLevel: Int?
  let kiwiSquelchThreshold: Int?
  let kiwiNoiseBlankerGate: Int?
  let kiwiNoiseBlankerThreshold: Int?
  let kiwiNoiseBlankerWildThreshold: Double?
  let kiwiNoiseBlankerWildTaps: Int?
  let kiwiNoiseBlankerWildImpulseSamples: Int?
  let kiwiDenoiseEnabled: Bool?
  let kiwiAutonotchEnabled: Bool?
  let kiwiPassbandsByMode: [String: ReceiverBandpass]?
  let kiwiWaterfallSpeed: Int?
  let kiwiWaterfallWindowFunction: Int?
  let kiwiWaterfallInterpolation: Int?
  let kiwiWaterfallZoom: Int?
  let kiwiWaterfallPanOffsetBins: Int?
  let kiwiWaterfallMinDB: Int?
  let kiwiWaterfallMaxDB: Int?
  let accessibilityInteractionSoundsVolume: Double?
  let scannerDwellSeconds: Double?
  let scannerHoldSeconds: Double?
  let fmdxAudioStartupBufferSeconds: Double?
  let fmdxAudioMaxLatencySeconds: Double?
  let fmdxAudioPacketHoldSeconds: Double?
  let fmdxCustomScanSettleSeconds: Double?
  let fmdxCustomScanMetadataWindowSeconds: Double?
}

private enum SharedRadioSessionSettingsNormalizationFixtureLoader {
  static func load() throws -> SharedRadioSessionSettingsNormalizationFixtureSet {
    let fixtureURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("shared/ListenSDRCore/Tests/ListenSDRCoreTests/Fixtures/ios-radio-session-settings-normalization-cases.json")

    let data = try Data(contentsOf: fixtureURL)
    return try JSONDecoder().decode(SharedRadioSessionSettingsNormalizationFixtureSet.self, from: data)
  }
}
