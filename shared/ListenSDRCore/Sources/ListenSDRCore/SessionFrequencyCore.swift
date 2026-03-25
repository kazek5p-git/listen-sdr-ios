public enum SessionFrequencyCore {
  public static let kiwiFrequencyRangeHz: ClosedRange<Int> = 10_000...32_000_000
  public static let openWebRXFrequencyRangeHz: ClosedRange<Int> = 100_000...3_000_000_000

  public static func fmdxFrequencyRange(for mode: DemodulationMode) -> ClosedRange<Int> {
    switch mode {
    case .am:
      return 100_000...29_600_000
    default:
      return 64_000_000...110_000_000
    }
  }

  public static func frequencyRange(
    for backend: SDRBackend?,
    mode: DemodulationMode
  ) -> ClosedRange<Int> {
    switch backend {
    case .fmDxWebserver:
      return fmdxFrequencyRange(for: mode)
    case .kiwiSDR:
      return kiwiFrequencyRangeHz
    case .openWebRX, .none:
      return openWebRXFrequencyRangeHz
    }
  }

  public static func normalizedFrequencyHz(
    _ value: Int,
    backend: SDRBackend?,
    mode: DemodulationMode
  ) -> Int {
    let range = frequencyRange(for: backend, mode: mode)
    let normalizedValue: Int
    if backend == .fmDxWebserver {
      normalizedValue = Int((Double(value) / 1_000.0).rounded()) * 1_000
    } else {
      normalizedValue = value
    }
    return min(max(normalizedValue, range.lowerBound), range.upperBound)
  }

  public static func tunedFrequencyHz(
    currentFrequencyHz: Int,
    stepCount: Int,
    tuneStepHz: Int,
    backend: SDRBackend?,
    mode: DemodulationMode
  ) -> Int {
    let rawTarget = Int64(currentFrequencyHz) + (Int64(stepCount) * Int64(tuneStepHz))
    let saturatedTarget = Int(max(Int64(Int.min), min(Int64(Int.max), rawTarget)))
    return normalizedFrequencyHz(
      saturatedTarget,
      backend: backend,
      mode: mode
    )
  }
}
