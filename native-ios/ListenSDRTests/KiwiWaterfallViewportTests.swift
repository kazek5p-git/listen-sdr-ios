import XCTest
@testable import ListenSDR

final class KiwiWaterfallViewportTests: XCTestCase {
  func testComputesCenteredStartBinFromFrequencyAndZoom() {
    let context = KiwiWaterfallViewportContext(
      bandwidthHz: 30_000_000,
      fftSize: 1_024,
      zoomMax: 14
    )

    let startBin = context.centeredStartBin(
      frequencyHz: 15_000_000,
      zoom: 4
    )

    XCTAssertEqual(startBin, 7_864_320)
  }

  func testAppliesPanOffsetAndClampsToBounds() {
    let context = KiwiWaterfallViewportContext(
      bandwidthHz: 30_000_000,
      fftSize: 1_024,
      zoomMax: 14
    )

    let lowEdge = context.startBin(
      frequencyHz: 100_000,
      zoom: 4,
      panOffsetBins: -10_000_000
    )
    let highEdge = context.startBin(
      frequencyHz: 29_900_000,
      zoom: 4,
      panOffsetBins: 10_000_000
    )

    XCTAssertEqual(lowEdge, 0)
    XCTAssertEqual(highEdge, (1_024 << 14) - (1_024 << 10))
  }

  func testRecommendedPanStepUsesQuarterOfVisibleBins() {
    let context = KiwiWaterfallViewportContext(
      bandwidthHz: 30_000_000,
      fftSize: 1_024,
      zoomMax: 14
    )

    XCTAssertEqual(context.recommendedPanStepBins(at: 0), 4_194_304)
    XCTAssertEqual(context.recommendedPanStepBins(at: 4), 262_144)
  }
}
