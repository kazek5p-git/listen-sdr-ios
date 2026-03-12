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
      openReceiverAfterHistoryRestore: RadioSessionSettings.default.openReceiverAfterHistoryRestore
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
      openReceiverAfterHistoryRestore: RadioSessionSettings.default.openReceiverAfterHistoryRestore
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
}
