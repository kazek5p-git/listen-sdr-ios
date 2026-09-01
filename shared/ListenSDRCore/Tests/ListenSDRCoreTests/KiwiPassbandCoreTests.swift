import XCTest
@testable import ListenSDRCore

final class KiwiPassbandCoreTests: XCTestCase {
  func testNormalizedBandpassMatchesCanonicalFixtures() throws {
    let fixture: KiwiPassbandCoreFixtureSet = try FixtureLoader.load(
      "kiwi-passband-core-cases.json"
    )

    for testCase in fixture.normalizedCases {
      XCTAssertEqual(
        testCase.expectedBandpass,
        KiwiPassbandCore.normalizedBandpass(
          testCase.bandpass,
          mode: testCase.mode,
          sampleRateHz: testCase.sampleRateHz
        ),
        testCase.label
      )
    }
  }

  func testResolvedBandpassMatchesCanonicalFixtures() throws {
    let fixture: KiwiPassbandCoreFixtureSet = try FixtureLoader.load(
      "kiwi-passband-core-cases.json"
    )

    for testCase in fixture.resolvedCases {
      XCTAssertEqual(
        testCase.expectedBandpass,
        KiwiPassbandCore.resolvedBandpass(
          storedBandpass: testCase.storedBandpass,
          mode: testCase.mode,
          sampleRateHz: testCase.sampleRateHz
        ),
        testCase.label
      )
    }
  }

  func testAdjustedBandpassChangesWidthAroundTheSameCenter() {
    let bandpass = ReceiverBandpass(lowCut: -2_000, highCut: 2_000)

    XCTAssertEqual(
      KiwiPassbandCore.adjustedBandpass(
        bandpass,
        deltaHz: 100,
        mode: .am,
        sampleRateHz: 12_000
      ),
      ReceiverBandpass(lowCut: -2_050, highCut: 2_050)
    )
    XCTAssertEqual(
      KiwiPassbandCore.adjustedBandpass(
        bandpass,
        deltaHz: -100,
        mode: .am,
        sampleRateHz: 12_000
      ),
      ReceiverBandpass(lowCut: -1_950, highCut: 1_950)
    )
  }

  func testAdjustedBandpassRespectsMinimumAndSampleRateLimit() {
    XCTAssertEqual(
      KiwiPassbandCore.adjustedBandpass(
        ReceiverBandpass(lowCut: 0, highCut: 50),
        deltaHz: -100,
        mode: .am,
        sampleRateHz: 12_000
      ),
      ReceiverBandpass(lowCut: 23, highCut: 27)
    )
    XCTAssertEqual(
      KiwiPassbandCore.adjustedBandpass(
        ReceiverBandpass(lowCut: -5_990, highCut: 5_990),
        deltaHz: 100,
        mode: .am,
        sampleRateHz: 12_000
      ),
      ReceiverBandpass(lowCut: -6_000, highCut: 6_000)
    )
  }
}

private struct KiwiPassbandCoreFixtureSet: Decodable {
  let normalizedCases: [KiwiPassbandCoreNormalizationFixtureCase]
  let resolvedCases: [KiwiPassbandCoreResolvedFixtureCase]
}

private struct KiwiPassbandCoreNormalizationFixtureCase: Decodable {
  let label: String
  let mode: DemodulationMode
  let bandpass: ReceiverBandpass
  let sampleRateHz: Int?
  let expectedBandpass: ReceiverBandpass
}

private struct KiwiPassbandCoreResolvedFixtureCase: Decodable {
  let label: String
  let mode: DemodulationMode
  let storedBandpass: ReceiverBandpass?
  let sampleRateHz: Int?
  let expectedBandpass: ReceiverBandpass
}
