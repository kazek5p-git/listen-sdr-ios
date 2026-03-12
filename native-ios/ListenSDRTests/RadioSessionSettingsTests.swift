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
}
