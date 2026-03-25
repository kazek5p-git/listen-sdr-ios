import Foundation

public enum ChannelScannerInterferenceFilterProfile: String, Codable, CaseIterable, Identifiable, Sendable {
  case gentle
  case standard
  case strong

  public var id: String { rawValue }
}

public struct ChannelScannerInterferenceMetrics: Equatable, Sendable {
  public let sampleAgeSeconds: Double?
  public let analysisBufferCount: Int
  public let envelopeVariation: Double?
  public let zeroCrossingRate: Double?
  public let spectralActivity: Double?
  public let levelStdDB: Double?

  public init(
    sampleAgeSeconds: Double?,
    analysisBufferCount: Int,
    envelopeVariation: Double?,
    zeroCrossingRate: Double?,
    spectralActivity: Double?,
    levelStdDB: Double?
  ) {
    self.sampleAgeSeconds = sampleAgeSeconds
    self.analysisBufferCount = analysisBufferCount
    self.envelopeVariation = envelopeVariation
    self.zeroCrossingRate = zeroCrossingRate
    self.spectralActivity = spectralActivity
    self.levelStdDB = levelStdDB
  }
}

public struct ChannelScannerInterferenceFilterThresholds: Equatable, Sendable {
  public let minimumAnalysisBuffers: Int
  public let maximumSampleAgeSeconds: Double
  public let stationaryEnvelopeLevelStdDB: Double
  public let stationaryEnvelopeVariation: Double
  public let lowFrequencyHumLevelStdDB: Double
  public let lowFrequencyHumZeroCrossingRate: Double
  public let lowFrequencyHumSpectralActivity: Double
  public let widebandStaticLevelStdDB: Double
  public let widebandStaticEnvelopeVariation: Double
  public let widebandStaticMinimumZeroCrossingRate: Double
  public let widebandStaticMinimumSpectralActivity: Double

  public init(
    minimumAnalysisBuffers: Int,
    maximumSampleAgeSeconds: Double,
    stationaryEnvelopeLevelStdDB: Double,
    stationaryEnvelopeVariation: Double,
    lowFrequencyHumLevelStdDB: Double,
    lowFrequencyHumZeroCrossingRate: Double,
    lowFrequencyHumSpectralActivity: Double,
    widebandStaticLevelStdDB: Double,
    widebandStaticEnvelopeVariation: Double,
    widebandStaticMinimumZeroCrossingRate: Double,
    widebandStaticMinimumSpectralActivity: Double
  ) {
    self.minimumAnalysisBuffers = minimumAnalysisBuffers
    self.maximumSampleAgeSeconds = maximumSampleAgeSeconds
    self.stationaryEnvelopeLevelStdDB = stationaryEnvelopeLevelStdDB
    self.stationaryEnvelopeVariation = stationaryEnvelopeVariation
    self.lowFrequencyHumLevelStdDB = lowFrequencyHumLevelStdDB
    self.lowFrequencyHumZeroCrossingRate = lowFrequencyHumZeroCrossingRate
    self.lowFrequencyHumSpectralActivity = lowFrequencyHumSpectralActivity
    self.widebandStaticLevelStdDB = widebandStaticLevelStdDB
    self.widebandStaticEnvelopeVariation = widebandStaticEnvelopeVariation
    self.widebandStaticMinimumZeroCrossingRate = widebandStaticMinimumZeroCrossingRate
    self.widebandStaticMinimumSpectralActivity = widebandStaticMinimumSpectralActivity
  }
}

public enum ChannelScannerSignalCore {
  public static func defaultThreshold(for backend: SDRBackend) -> Double {
    switch backend {
    case .fmDxWebserver:
      return 20
    case .kiwiSDR:
      return -95
    case .openWebRX:
      return -42
    }
  }

  public static func signalUnit(for backend: SDRBackend?) -> String {
    switch backend {
    case .fmDxWebserver:
      return "dBf"
    case .kiwiSDR:
      return "dBm"
    case .openWebRX:
      return "dBFS"
    case .none:
      return "dB"
    }
  }

  public static func adaptiveDwellSeconds(
    _ base: Double,
    adaptive: Bool,
    signal: Double?,
    threshold: Double
  ) -> Double {
    guard adaptive else { return base }
    guard let signal else { return max(0.5, base * 0.75) }

    let margin = signal - threshold
    if margin >= 10 {
      return min(6.0, base * 1.45)
    }
    if margin >= 4 {
      return min(6.0, base * 1.15)
    }
    if margin <= -8 {
      return max(0.5, base * 0.58)
    }
    if margin <= -4 {
      return max(0.5, base * 0.72)
    }
    return base
  }

  public static func adaptiveHoldSeconds(
    _ base: Double,
    adaptive: Bool,
    signal: Double?,
    threshold: Double
  ) -> Double {
    guard adaptive else { return base }
    guard let signal else { return max(0.5, base * 0.7) }

    let margin = signal - threshold
    if margin >= 12 {
      return min(20.0, base * 2.6)
    }
    if margin >= 6 {
      return min(16.0, base * 1.8)
    }
    if margin <= 2 {
      return max(0.5, base * 0.78)
    }
    return base
  }

  public static func interferenceFilterThresholds(
    for profile: ChannelScannerInterferenceFilterProfile
  ) -> ChannelScannerInterferenceFilterThresholds {
    switch profile {
    case .gentle:
      return ChannelScannerInterferenceFilterThresholds(
        minimumAnalysisBuffers: 4,
        maximumSampleAgeSeconds: 0.8,
        stationaryEnvelopeLevelStdDB: 0.70,
        stationaryEnvelopeVariation: 0.18,
        lowFrequencyHumLevelStdDB: 0.95,
        lowFrequencyHumZeroCrossingRate: 0.028,
        lowFrequencyHumSpectralActivity: 0.18,
        widebandStaticLevelStdDB: 0.60,
        widebandStaticEnvelopeVariation: 0.30,
        widebandStaticMinimumZeroCrossingRate: 0.23,
        widebandStaticMinimumSpectralActivity: 1.65
      )
    case .standard:
      return ChannelScannerInterferenceFilterThresholds(
        minimumAnalysisBuffers: 3,
        maximumSampleAgeSeconds: 0.8,
        stationaryEnvelopeLevelStdDB: 0.90,
        stationaryEnvelopeVariation: 0.24,
        lowFrequencyHumLevelStdDB: 1.20,
        lowFrequencyHumZeroCrossingRate: 0.035,
        lowFrequencyHumSpectralActivity: 0.25,
        widebandStaticLevelStdDB: 0.75,
        widebandStaticEnvelopeVariation: 0.42,
        widebandStaticMinimumZeroCrossingRate: 0.18,
        widebandStaticMinimumSpectralActivity: 1.35
      )
    case .strong:
      return ChannelScannerInterferenceFilterThresholds(
        minimumAnalysisBuffers: 3,
        maximumSampleAgeSeconds: 0.8,
        stationaryEnvelopeLevelStdDB: 1.10,
        stationaryEnvelopeVariation: 0.30,
        lowFrequencyHumLevelStdDB: 1.45,
        lowFrequencyHumZeroCrossingRate: 0.045,
        lowFrequencyHumSpectralActivity: 0.33,
        widebandStaticLevelStdDB: 0.95,
        widebandStaticEnvelopeVariation: 0.50,
        widebandStaticMinimumZeroCrossingRate: 0.15,
        widebandStaticMinimumSpectralActivity: 1.15
      )
    }
  }

  public static func interferenceFilterState(
    metrics: ChannelScannerInterferenceMetrics?,
    profile: ChannelScannerInterferenceFilterProfile
  ) -> String? {
    guard let metrics else { return nil }

    let thresholds = interferenceFilterThresholds(for: profile)
    guard let sampleAgeSeconds = metrics.sampleAgeSeconds, sampleAgeSeconds <= thresholds.maximumSampleAgeSeconds else {
      return nil
    }
    guard metrics.analysisBufferCount >= thresholds.minimumAnalysisBuffers else {
      return nil
    }
    guard
      let envelopeVariation = metrics.envelopeVariation,
      let zeroCrossingRate = metrics.zeroCrossingRate,
      let spectralActivity = metrics.spectralActivity,
      let levelStdDB = metrics.levelStdDB
    else {
      return nil
    }

    let details =
      "profile=\(profile.rawValue),std=\(formatMetric(levelStdDB)),env=\(formatMetric(envelopeVariation)),zcr=\(formatMetric(zeroCrossingRate)),texture=\(formatMetric(spectralActivity)),buffers=\(metrics.analysisBufferCount)"

    if levelStdDB <= thresholds.stationaryEnvelopeLevelStdDB,
      envelopeVariation <= thresholds.stationaryEnvelopeVariation {
      return "filter=rejected:stationary-envelope,\(details)"
    }

    if levelStdDB <= thresholds.lowFrequencyHumLevelStdDB,
      zeroCrossingRate <= thresholds.lowFrequencyHumZeroCrossingRate,
      spectralActivity <= thresholds.lowFrequencyHumSpectralActivity {
      return "filter=rejected:low-frequency-hum,\(details)"
    }

    if levelStdDB <= thresholds.widebandStaticLevelStdDB,
      envelopeVariation <= thresholds.widebandStaticEnvelopeVariation,
      zeroCrossingRate >= thresholds.widebandStaticMinimumZeroCrossingRate,
      spectralActivity >= thresholds.widebandStaticMinimumSpectralActivity {
      return "filter=rejected:wideband-static,\(details)"
    }

    return nil
  }

  public static func formatMetric(_ value: Double) -> String {
    String(format: "%.2f", value)
  }
}
