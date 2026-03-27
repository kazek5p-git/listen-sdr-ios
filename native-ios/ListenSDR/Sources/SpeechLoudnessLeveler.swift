import Foundation

final class SpeechLoudnessLeveler {
  private let targetRMS: Float
  private let peakLimit: Float
  private let minimumGain: Float
  private let maximumGain: Float
  private let gainIncreaseStep: Float
  private let gainDecreaseStep: Float
  private var currentGain: Float = 1.0

  init(
    targetRMS: Float = 0.16,
    peakLimit: Float = 0.92,
    minimumGain: Float = 0.20,
    maximumGain: Float = 8.0,
    gainIncreaseStep: Float = 0.08,
    gainDecreaseStep: Float = 0.35
  ) {
    self.targetRMS = targetRMS
    self.peakLimit = peakLimit
    self.minimumGain = minimumGain
    self.maximumGain = maximumGain
    self.gainIncreaseStep = gainIncreaseStep
    self.gainDecreaseStep = gainDecreaseStep
  }

  func reset() {
    currentGain = 1.0
  }

  func process(_ samples: [Float]) -> [Float] {
    guard !samples.isEmpty else { return samples }

    var peak: Float = 0
    var sumSquares = 0.0
    for sample in samples {
      let absoluteValue = Swift.abs(sample)
      if absoluteValue > peak {
        peak = absoluteValue
      }
      let value = Double(sample)
      sumSquares += value * value
    }

    let rms = Float(sqrt(sumSquares / Double(samples.count)))
    let desiredGain: Float
    if rms > 0.0005 {
      desiredGain = min(max(targetRMS / rms, minimumGain), maximumGain)
    } else {
      desiredGain = maximumGain
    }

    let smoothing = desiredGain > currentGain ? gainIncreaseStep : gainDecreaseStep
    currentGain += (desiredGain - currentGain) * smoothing
    currentGain = min(max(currentGain, minimumGain), maximumGain)

    var appliedGain = currentGain
    if peak > 0, peak * appliedGain > peakLimit {
      appliedGain = peakLimit / peak
      currentGain = min(currentGain, appliedGain)
    }

    return samples.map { sample in
      min(max(sample * appliedGain, -peakLimit), peakLimit)
    }
  }
}
