import Foundation

struct BandTuningContext {
  let backend: SDRBackend
  let frequencyHz: Int
  let mode: DemodulationMode
  let bandName: String?
  let bandTags: [String]
}

struct BandTuningProfile: Equatable {
  let id: String
  let stepOptionsHz: [Int]
  let defaultStepHz: Int
}

enum BandTuningProfiles {
  static func resolve(for context: BandTuningContext) -> BandTuningProfile {
    switch context.backend {
    case .fmDxWebserver:
      return resolveFMDXProfile(for: context)

    case .openWebRX, .kiwiSDR:
      return resolveWidebandProfile(for: context)
    }
  }

  private static func resolveFMDXProfile(for context: BandTuningContext) -> BandTuningProfile {
    let frequencyHz = context.frequencyHz

    if frequencyHz < 520_000 {
      return BandTuningProfile(
        id: "fmdx-lw",
        stepOptionsHz: [9_000],
        defaultStepHz: 9_000
      )
    }

    if frequencyHz < 1_710_000 {
      return BandTuningProfile(
        id: "fmdx-mw",
        stepOptionsHz: [9_000, 10_000],
        defaultStepHz: 9_000
      )
    }

    if frequencyHz < 29_600_000 {
      return BandTuningProfile(
        id: "fmdx-sw",
        stepOptionsHz: [5_000, 10_000],
        defaultStepHz: 5_000
      )
    }

    if (65_900_000..<74_000_000).contains(frequencyHz) {
      return BandTuningProfile(
        id: "fmdx-oirt-fm",
        stepOptionsHz: [10_000, 25_000, 30_000, 50_000, 100_000],
        defaultStepHz: 30_000
      )
    }

    if context.mode == .am {
      return BandTuningProfile(
        id: "fmdx-am-wide",
        stepOptionsHz: [9_000, 10_000],
        defaultStepHz: 9_000
      )
    }

    return BandTuningProfile(
      id: "fmdx-fm",
      stepOptionsHz: [10_000, 25_000, 50_000, 100_000, 200_000],
      defaultStepHz: 100_000
    )
  }

  private static func resolveWidebandProfile(for context: BandTuningContext) -> BandTuningProfile {
    let normalizedBandName = normalizeBandName(context.bandName)
    let tags = Set(context.bandTags.map { $0.lowercased() })
    let frequencyHz = context.frequencyHz
    let fineTuningMode = isFineTuningMode(context.mode)

    if isOIRTFMBand(name: normalizedBandName, frequencyHz: frequencyHz) {
      return BandTuningProfile(
        id: "fm-broadcast-oirt",
        stepOptionsHz: [10_000, 30_000, 50_000, 100_000],
        defaultStepHz: 30_000
      )
    }

    if isFMBroadcastBand(name: normalizedBandName, tags: tags, frequencyHz: frequencyHz) {
      return BandTuningProfile(
        id: "fm-broadcast",
        stepOptionsHz: [50_000, 100_000, 200_000],
        defaultStepHz: 100_000
      )
    }

    if isAirband(name: normalizedBandName, frequencyHz: frequencyHz) {
      return BandTuningProfile(
        id: "airband",
        stepOptionsHz: [8_330, 25_000],
        defaultStepHz: 8_330
      )
    }

    if isMarineBand(name: normalizedBandName) {
      return BandTuningProfile(
        id: "marine",
        stepOptionsHz: [12_500, 25_000],
        defaultStepHz: 25_000
      )
    }

    if isPMRBand(name: normalizedBandName) {
      return BandTuningProfile(
        id: "pmr446",
        stepOptionsHz: [6_250, 12_500],
        defaultStepHz: 12_500
      )
    }

    if isCBBand(name: normalizedBandName, frequencyHz: frequencyHz) {
      return BandTuningProfile(
        id: "cb",
        stepOptionsHz: [1_000, 5_000, 10_000],
        defaultStepHz: 10_000
      )
    }

    if isLongMediumWaveBroadcast(name: normalizedBandName, tags: tags, frequencyHz: frequencyHz) {
      return BandTuningProfile(
        id: "lw-mw-broadcast",
        stepOptionsHz: [1_000, 5_000, 9_000, 10_000],
        defaultStepHz: 9_000
      )
    }

    if isShortwaveBroadcast(name: normalizedBandName, tags: tags, frequencyHz: frequencyHz) {
      return BandTuningProfile(
        id: "sw-broadcast",
        stepOptionsHz: [1_000, 5_000],
        defaultStepHz: 5_000
      )
    }

    if isHamVHFUHF(name: normalizedBandName, tags: tags, frequencyHz: frequencyHz) {
      if fineTuningMode {
        return BandTuningProfile(
          id: "ham-vhf-uhf-fine",
          stepOptionsHz: [100, 500, 1_000],
          defaultStepHz: 500
        )
      }
      return BandTuningProfile(
        id: "ham-vhf-uhf-channel",
        stepOptionsHz: [6_250, 10_000, 12_500, 25_000],
        defaultStepHz: 12_500
      )
    }

    if isHamHF(name: normalizedBandName, tags: tags, frequencyHz: frequencyHz) {
      if context.mode == .am {
        return BandTuningProfile(
          id: "ham-hf-am",
          stepOptionsHz: [100, 500, 1_000, 5_000],
          defaultStepHz: 1_000
        )
      }
      return BandTuningProfile(
        id: "ham-hf-fine",
        stepOptionsHz: [10, 50, 100, 500, 1_000],
        defaultStepHz: 100
      )
    }

    if frequencyHz < 30_000_000 {
      if context.mode == .am {
        return BandTuningProfile(
          id: "hf-am-generic",
          stepOptionsHz: [100, 500, 1_000, 5_000],
          defaultStepHz: 1_000
        )
      }
      return BandTuningProfile(
        id: "hf-generic",
        stepOptionsHz: [10, 50, 100, 500, 1_000],
        defaultStepHz: 100
      )
    }

    if fineTuningMode {
      return BandTuningProfile(
        id: "wideband-fine",
        stepOptionsHz: [100, 500, 1_000, 5_000],
        defaultStepHz: 1_000
      )
    }

    return BandTuningProfile(
      id: "wideband-channel",
      stepOptionsHz: [6_250, 8_330, 10_000, 12_500, 25_000],
      defaultStepHz: 12_500
    )
  }

  private static func normalizeBandName(_ value: String?) -> String {
    guard let value else { return "" }
    return value
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "-", with: "")
  }

  private static func isFineTuningMode(_ mode: DemodulationMode) -> Bool {
    mode.isFineTuningMode
  }

  private static func isFMBroadcastBand(name: String, tags: Set<String>, frequencyHz: Int) -> Bool {
    if tags.contains("broadcast"), (64_000_000...110_000_000).contains(frequencyHz) {
      return true
    }
    return name.contains("fmbroadcast")
      || name == "fm"
      || name.contains("broadcastfm")
  }

  private static func isOIRTFMBand(name: String, frequencyHz: Int) -> Bool {
    if name.contains("oirt") {
      return true
    }
    return (65_900_000..<74_000_000).contains(frequencyHz)
  }

  private static func isAirband(name: String, frequencyHz: Int) -> Bool {
    if name.contains("air") || name.contains("aero") {
      return true
    }
    return (118_000_000...136_991_000).contains(frequencyHz)
  }

  private static func isMarineBand(name: String) -> Bool {
    name.contains("marine")
  }

  private static func isPMRBand(name: String) -> Bool {
    name.contains("pmr446") || name.contains("pmr")
  }

  private static func isCBBand(name: String, frequencyHz: Int) -> Bool {
    if name.contains("cb") || name.contains("11m") {
      return true
    }
    return (26_965_000...27_405_000).contains(frequencyHz)
  }

  private static func isLongMediumWaveBroadcast(name: String, tags: Set<String>, frequencyHz: Int) -> Bool {
    if name == "lw" || name == "mw" || name.contains("longwave") || name.contains("mediumwave") {
      return true
    }
    if tags.contains("broadcast"), frequencyHz < 3_000_000 {
      return true
    }
    return false
  }

  private static func isShortwaveBroadcast(name: String, tags: Set<String>, frequencyHz: Int) -> Bool {
    if name.contains("broadcast") {
      return true
    }
    if tags.contains("broadcast"), (3_000_000..<30_000_000).contains(frequencyHz) {
      return true
    }
    return false
  }

  private static func isHamHF(name: String, tags: Set<String>, frequencyHz: Int) -> Bool {
    if tags.contains("hamradio"), frequencyHz < 30_000_000 {
      return true
    }
    return name.hasSuffix("m")
      && !name.contains("cm")
      && !name.contains("fm")
      && !name.contains("broadcast")
      && !name.contains("cb")
      && frequencyHz < 30_000_000
  }

  private static func isHamVHFUHF(name: String, tags: Set<String>, frequencyHz: Int) -> Bool {
    if tags.contains("hamradio"), frequencyHz >= 30_000_000 {
      return true
    }
    return name.contains("2m")
      || name.contains("4m")
      || name.contains("6m")
      || name.contains("70cm")
      || name.contains("23cm")
  }
}
