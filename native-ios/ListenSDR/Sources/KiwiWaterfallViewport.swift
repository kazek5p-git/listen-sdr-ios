import Foundation

struct KiwiWaterfallViewportContext: Equatable {
  let bandwidthHz: Int
  let fftSize: Int
  let zoomMax: Int

  var isValid: Bool {
    bandwidthHz > 0 && fftSize > 0 && zoomMax >= 0
  }

  func clampedZoom(_ zoom: Int) -> Int {
    min(max(zoom, 0), zoomMax)
  }

  func totalBins() -> Int? {
    guard isValid else { return nil }
    return fftSize << zoomMax
  }

  func visibleBins(at zoom: Int) -> Int? {
    guard isValid else { return nil }
    let clamped = clampedZoom(zoom)
    return fftSize << (zoomMax - clamped)
  }

  func centeredStartBin(frequencyHz: Int, zoom: Int) -> Int? {
    startBin(frequencyHz: frequencyHz, zoom: zoom, panOffsetBins: 0)
  }

  func startBin(
    frequencyHz: Int,
    zoom: Int,
    panOffsetBins: Int
  ) -> Int? {
    guard
      let totalBins = totalBins(),
      let visibleBins = visibleBins(at: zoom)
    else {
      return nil
    }

    let clampedFrequency = min(max(frequencyHz, 0), bandwidthHz)
    let centerBin = Int(
      (Double(clampedFrequency) / Double(bandwidthHz) * Double(totalBins)).rounded()
    )
    let centeredStart = centerBin - (visibleBins / 2)
    let maxStart = max(totalBins - visibleBins, 0)
    let unclamped = centeredStart + panOffsetBins
    return min(max(unclamped, 0), maxStart)
  }

  func recommendedPanStepBins(at zoom: Int) -> Int? {
    guard let visibleBins = visibleBins(at: zoom) else { return nil }
    return max(visibleBins / 4, 1)
  }
}
