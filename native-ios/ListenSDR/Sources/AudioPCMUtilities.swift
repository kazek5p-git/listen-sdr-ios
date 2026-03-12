import Foundation

enum AudioPCMUtilities {
  static let preferredOutputSampleRate: Double = 48_000

  static func sanitizedInputSampleRate(_ sampleRate: Double) -> Double {
    guard sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 192_000 else {
      return preferredOutputSampleRate
    }
    return sampleRate
  }

  static func resampleMono(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
    guard !samples.isEmpty else { return [] }

    let safeInputRate = sanitizedInputSampleRate(inputRate)
    let safeOutputRate = sanitizedInputSampleRate(outputRate)

    if abs(safeInputRate - safeOutputRate) < 0.5 {
      return samples
    }

    let ratio = safeOutputRate / safeInputRate
    let outputCount = max(1, Int((Double(samples.count) * ratio).rounded()))
    if outputCount == samples.count {
      return samples
    }

    var output = Array(repeating: Float.zero, count: outputCount)
    let maxInputIndex = samples.count - 1

    for outputIndex in 0..<outputCount {
      let sourcePosition = Double(outputIndex) / ratio
      let lowerIndex = min(maxInputIndex, Int(sourcePosition.rounded(.down)))
      let upperIndex = min(maxInputIndex, lowerIndex + 1)
      let fraction = Float(sourcePosition - Double(lowerIndex))
      let lowerSample = samples[lowerIndex]
      let upperSample = samples[upperIndex]
      output[outputIndex] = lowerSample + ((upperSample - lowerSample) * fraction)
    }

    return output
  }
}
