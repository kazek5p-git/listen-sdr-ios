import Foundation

struct SpeechLoudnessLevelingProfile: Equatable {
  let targetRMS: Float
  let peakLimit: Float
  let minimumGain: Float
  let maximumGain: Float
  let gainIncreaseStep: Float
  let gainDecreaseStep: Float

  static let gentle = SpeechLoudnessLevelingProfile(
    targetRMS: 0.16,
    peakLimit: 0.92,
    minimumGain: 0.20,
    maximumGain: 8.0,
    gainIncreaseStep: 0.08,
    gainDecreaseStep: 0.35
  )

  static let strong = SpeechLoudnessLevelingProfile(
    targetRMS: 0.22,
    peakLimit: 0.92,
    minimumGain: 0.20,
    maximumGain: 12.0,
    gainIncreaseStep: 0.12,
    gainDecreaseStep: 0.30
  )

  static let veryStrong = SpeechLoudnessLevelingProfile(
    targetRMS: 0.28,
    peakLimit: 0.90,
    minimumGain: 0.20,
    maximumGain: 18.0,
    gainIncreaseStep: 0.18,
    gainDecreaseStep: 0.26
  )
}

final class SpeechLoudnessLeveler {
  private var profile: SpeechLoudnessLevelingProfile
  private var currentGain: Float = 1.0

  init(profile: SpeechLoudnessLevelingProfile = .gentle) {
    self.profile = profile
  }

  func reset() {
    currentGain = 1.0
  }

  func updateProfile(_ value: SpeechLoudnessLevelingProfile) {
    guard profile != value else { return }
    profile = value
    reset()
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
      desiredGain = min(max(profile.targetRMS / rms, profile.minimumGain), profile.maximumGain)
    } else {
      desiredGain = profile.maximumGain
    }

    let smoothing = desiredGain > currentGain ? profile.gainIncreaseStep : profile.gainDecreaseStep
    currentGain += (desiredGain - currentGain) * smoothing
    currentGain = min(max(currentGain, profile.minimumGain), profile.maximumGain)

    var appliedGain = currentGain
    if peak > 0, peak * appliedGain > profile.peakLimit {
      appliedGain = profile.peakLimit / peak
      currentGain = min(currentGain, appliedGain)
    }

    return samples.map { sample in
      min(max(sample * appliedGain, -profile.peakLimit), profile.peakLimit)
    }
  }
}
