import XCTest
@testable import ListenSDR

final class FMDXCapabilitiesTests: XCTestCase {
  @MainActor
  func testFMDXAMRangeCoversLongwaveThroughShortwave() {
    let session = RadioSessionViewModel()

    XCTAssertEqual(session.fmdxFrequencyRange(for: .am).lowerBound, 100_000)
    XCTAssertEqual(session.fmdxFrequencyRange(for: .am).upperBound, 29_600_000)
  }

  @MainActor
  func testNormalizeReportedFMDXFrequencyPreservesAMFrequencies() {
    let session = RadioSessionViewModel()

    XCTAssertEqual(session.normalizeFMDXReportedFrequencyHz(fromMHz: 0.999), 999_000)
    XCTAssertEqual(session.normalizeFMDXReportedFrequencyHz(fromMHz: 7.050), 7_050_000)
  }

  @MainActor
  func testInferFMDXModeRecognizesAMFrequencies() {
    let session = RadioSessionViewModel()

    XCTAssertEqual(session.inferredFMDXMode(for: 999_000), .am)
    XCTAssertEqual(session.inferredFMDXMode(for: 7_050_000), .am)
  }

  @MainActor
  func testInferFMDXModeRecognizesFMFrequencies() {
    let session = RadioSessionViewModel()

    XCTAssertEqual(session.inferredFMDXMode(for: 87_500_000), .fm)
    XCTAssertEqual(session.inferredFMDXMode(for: 94_200_000), .fm)
  }

  @MainActor
  func testFMDXQuickBandResolutionCoversSupportedTEF6686Ranges() {
    let session = RadioSessionViewModel()

    XCTAssertEqual(session.fmdxQuickBand(for: 225_000, mode: .am), .lw)
    XCTAssertEqual(session.fmdxQuickBand(for: 999_000, mode: .am), .mw)
    XCTAssertEqual(session.fmdxQuickBand(for: 7_050_000, mode: .am), .sw)
    XCTAssertEqual(session.fmdxQuickBand(for: 70_300_000, mode: .fm), .oirt)
    XCTAssertEqual(session.fmdxQuickBand(for: 87_500_000, mode: .fm), .fm)
  }

  @MainActor
  func testFMDXQuickBandDefaultsStayInsideTheirRanges() {
    for band in FMDXQuickBand.allCases {
      XCTAssertTrue(band.rangeHz.contains(band.defaultFrequencyHz), "Band \(band.rawValue) default is outside range")
    }
  }

  func testAMSupportUsesAPIScriptWhenStaticDataStillLooksFMOnly() async {
    let client = FMDXWebserverClient()
    let staticData: [String: Any] = [
      "tunerName": "South-east Cracow",
      "tunerDesc": "Limit: 64.0 MHz - 108 MHz",
      "presets": ["89.1", "94.2", "105.8"]
    ]
    let indexHTML = """
    <html>
      <body>
        <div class="info">Limit: 64.0 MHz - 108 MHz</div>
      </body>
    </html>
    """
    let apiScript = """
    function tuneStep(currentFreq) {
      if (currentFreq < 0.52) { return 0.009; }
      else if (currentFreq < 1.71) { return 0.009; }
      else if (currentFreq < 29.6) { return 0.005; }
      return 0.1;
    }
    """

    let supportsAM = await client.parseAMSupport(
      staticData: staticData,
      indexHTML: indexHTML,
      apiScript: apiScript
    )

    XCTAssertTrue(supportsAM)
  }

  func testAMSupportStaysFalseWithoutAMHints() async {
    let client = FMDXWebserverClient()
    let staticData: [String: Any] = [
      "tunerName": "South-east Cracow",
      "tunerDesc": "Limit: 64.0 MHz - 108 MHz",
      "presets": ["89.1", "94.2", "105.8"]
    ]
    let indexHTML = """
    <html>
      <body>
        <div class="info">Limit: 64.0 MHz - 108 MHz</div>
      </body>
    </html>
    """

    let supportsAM = await client.parseAMSupport(
      staticData: staticData,
      indexHTML: indexHTML,
      apiScript: nil
    )

    XCTAssertFalse(supportsAM)
  }
}
