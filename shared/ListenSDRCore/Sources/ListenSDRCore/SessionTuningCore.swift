import Foundation

public struct TuneStepState: Equatable, Sendable {
  public let tuneStepHz: Int
  public let preferredTuneStepHz: Int
  public let preferenceMode: TuneStepPreferenceMode

  public init(
    tuneStepHz: Int,
    preferredTuneStepHz: Int,
    preferenceMode: TuneStepPreferenceMode
  ) {
    self.tuneStepHz = tuneStepHz
    self.preferredTuneStepHz = preferredTuneStepHz
    self.preferenceMode = preferenceMode
  }
}

public enum SessionTuningCore {
  public static let supportedTuneStepsHz = [
    10, 50, 100, 500, 1_000, 5_000, 6_250, 8_330, 9_000, 10_000, 12_500, 25_000,
    50_000, 100_000, 200_000
  ]

  public static func tuningProfile(for context: BandTuningContext) -> BandTuningProfile {
    BandTuningProfiles.resolve(for: context)
  }

  public static func normalizedPreferredTuneStep(_ value: Int) -> Int {
    supportedTuneStepsHz.min(by: { abs($0 - value) < abs($1 - value) }) ?? 100
  }

  public static func availableTuneSteps(for context: BandTuningContext) -> [Int] {
    tuningProfile(for: context).stepOptionsHz
  }

  public static func automaticTuneStep(for context: BandTuningContext) -> Int {
    tuningProfile(for: context).defaultStepHz
  }

  public static func resolvedTuneStep(
    preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    context: BandTuningContext
  ) -> Int {
    resolvedTuneStep(
      preferredStepHz: preferredStepHz,
      preferenceMode: preferenceMode,
      profile: tuningProfile(for: context)
    )
  }

  public static func resolvedTuneStep(
    preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    profile: BandTuningProfile
  ) -> Int {
    switch preferenceMode {
    case .automatic:
      return profile.defaultStepHz
    case .manual:
      return profile.stepOptionsHz.min(by: { abs($0 - preferredStepHz) < abs($1 - preferredStepHz) })
        ?? profile.defaultStepHz
    }
  }

  public static func tuneStepState(
    preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    context: BandTuningContext?
  ) -> TuneStepState {
    let normalizedPreferred = normalizedPreferredTuneStep(preferredStepHz)
    guard let context else {
      return TuneStepState(
        tuneStepHz: normalizedPreferred,
        preferredTuneStepHz: normalizedPreferred,
        preferenceMode: preferenceMode
      )
    }

    return TuneStepState(
      tuneStepHz: resolvedTuneStep(
        preferredStepHz: normalizedPreferred,
        preferenceMode: preferenceMode,
        context: context
      ),
      preferredTuneStepHz: normalizedPreferred,
      preferenceMode: preferenceMode
    )
  }

  public static func manualTuneStepState(
    requestedStepHz: Int,
    context: BandTuningContext?
  ) -> TuneStepState {
    tuneStepState(
      preferredStepHz: requestedStepHz,
      preferenceMode: .manual,
      context: context
    )
  }

  public static func inferredKiwiBandName(for frequencyHz: Int) -> String? {
    switch frequencyHz {
    case 150_000...299_999:
      return "LW"
    case 300_000...2_999_999:
      return "MW"
    case 3_000_000...29_999_999:
      return "SW"
    case 64_000_000...110_000_000:
      return "FM"
    case 30_000_000...299_999_999:
      return "VHF"
    default:
      return nil
    }
  }
}
