import Foundation

public struct FMDXCustomScanSettings: Equatable, Sendable {
  public let settleSeconds: Double
  public let metadataWindowSeconds: Double

  public init(
    settleSeconds: Double,
    metadataWindowSeconds: Double
  ) {
    self.settleSeconds = settleSeconds
    self.metadataWindowSeconds = metadataWindowSeconds
  }
}

public enum FMDXBandScanStartBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
  case fromBeginning
  case fromCurrentFrequency

  public var id: String { rawValue }
}

public struct FMDXBandScanRangeDefinition: Equatable, Sendable {
  public let mode: DemodulationMode
  public let rangeHz: ClosedRange<Int>
  public let stepOptionsHz: [Int]
  public let defaultStepHz: Int
  public let metadataProfileBand: FMDXQuickBand
  public let mergeSpacingProfileBand: FMDXQuickBand

  public init(
    mode: DemodulationMode,
    rangeHz: ClosedRange<Int>,
    stepOptionsHz: [Int],
    defaultStepHz: Int,
    metadataProfileBand: FMDXQuickBand,
    mergeSpacingProfileBand: FMDXQuickBand
  ) {
    self.mode = mode
    self.rangeHz = rangeHz
    self.stepOptionsHz = stepOptionsHz
    self.defaultStepHz = defaultStepHz
    self.metadataProfileBand = metadataProfileBand
    self.mergeSpacingProfileBand = mergeSpacingProfileBand
  }
}

public enum FMDXBandScanRangePreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case lowerUKF
  case upperUKF
  case fullUKF
  case noaa
  case lw
  case mw
  case sw

  public var id: String { rawValue }

  public static func availableCases(supportsAM: Bool) -> [FMDXBandScanRangePreset] {
    var presets: [FMDXBandScanRangePreset] = [.lowerUKF, .upperUKF, .fullUKF, .noaa]
    if supportsAM {
      presets.append(contentsOf: [.sw, .mw, .lw])
    }
    return presets
  }

  public var definition: FMDXBandScanRangeDefinition {
    switch self {
    case .lowerUKF:
      return FMDXBandScanRangeDefinition(
        mode: .fm,
        rangeHz: 65_900_000...73_999_000,
        stepOptionsHz: [10_000, 25_000, 30_000, 50_000, 100_000],
        defaultStepHz: 50_000,
        metadataProfileBand: .oirt,
        mergeSpacingProfileBand: .oirt
      )
    case .upperUKF:
      return FMDXBandScanRangeDefinition(
        mode: .fm,
        rangeHz: 87_500_000...108_000_000,
        stepOptionsHz: [10_000, 25_000, 50_000, 100_000, 200_000],
        defaultStepHz: 100_000,
        metadataProfileBand: .fm,
        mergeSpacingProfileBand: .fm
      )
    case .fullUKF:
      return FMDXBandScanRangeDefinition(
        mode: .fm,
        rangeHz: FMDXQuickBand.fm.rangeHz,
        stepOptionsHz: [10_000, 25_000, 50_000, 100_000, 200_000],
        defaultStepHz: 100_000,
        metadataProfileBand: .fm,
        mergeSpacingProfileBand: .fm
      )
    case .noaa:
      return FMDXBandScanRangeDefinition(
        mode: .fm,
        rangeHz: FMDXQuickBand.noaa.rangeHz,
        stepOptionsHz: [5_000, 10_000, 12_500, 25_000],
        defaultStepHz: 25_000,
        metadataProfileBand: .noaa,
        mergeSpacingProfileBand: .noaa
      )
    case .lw:
      return FMDXBandScanRangeDefinition(
        mode: .am,
        rangeHz: FMDXQuickBand.lw.rangeHz,
        stepOptionsHz: FMDXQuickBand.lw.scanStepOptionsHz,
        defaultStepHz: FMDXQuickBand.lw.defaultScanStepHz,
        metadataProfileBand: .lw,
        mergeSpacingProfileBand: .lw
      )
    case .mw:
      return FMDXBandScanRangeDefinition(
        mode: .am,
        rangeHz: FMDXQuickBand.mw.rangeHz,
        stepOptionsHz: FMDXQuickBand.mw.scanStepOptionsHz,
        defaultStepHz: FMDXQuickBand.mw.defaultScanStepHz,
        metadataProfileBand: .mw,
        mergeSpacingProfileBand: .mw
      )
    case .sw:
      return FMDXBandScanRangeDefinition(
        mode: .am,
        rangeHz: FMDXQuickBand.sw.rangeHz,
        stepOptionsHz: FMDXQuickBand.sw.scanStepOptionsHz,
        defaultStepHz: FMDXQuickBand.sw.defaultScanStepHz,
        metadataProfileBand: .sw,
        mergeSpacingProfileBand: .sw
      )
    }
  }
}

public enum FMDXBandScanSequenceBuilder {
  public static func buildFrequencies(
    in rangeHz: ClosedRange<Int>,
    stepHz: Int,
    startBehavior: FMDXBandScanStartBehavior,
    currentFrequencyHz: Int?
  ) -> [Int] {
    guard stepHz > 0 else { return [] }

    var frequencies: [Int] = []
    frequencies.reserveCapacity(max(1, (rangeHz.upperBound - rangeHz.lowerBound) / stepHz + 1))

    var current = rangeHz.lowerBound
    while current <= rangeHz.upperBound {
      frequencies.append(current)
      current += stepHz
    }

    if frequencies.last != rangeHz.upperBound {
      frequencies.append(rangeHz.upperBound)
    }

    guard
      startBehavior == .fromCurrentFrequency,
      let currentFrequencyHz,
      rangeHz.contains(currentFrequencyHz),
      let startIndex = frequencies.firstIndex(where: { $0 >= currentFrequencyHz })
    else {
      return frequencies
    }

    guard startIndex > 0 else { return frequencies }
    return Array(frequencies[startIndex...]) + frequencies[..<startIndex]
  }
}

public enum FMDXBandScanMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case standard
  case quickNewSignals
  case veryFast
  case custom

  public var id: String { rawValue }

  public static func selectableCases(saveResultsEnabled: Bool) -> [FMDXBandScanMode] {
    saveResultsEnabled
      ? [.standard, .quickNewSignals, .veryFast, .custom]
      : [.standard, .veryFast, .custom]
  }
}

public struct FMDXBandScanTimingProfile: Equatable, Sendable {
  public let tuneAttemptCount: Int
  public let settleSeconds: Double
  public let minimumDeadlineSeconds: Double
  public let confirmationGraceSeconds: Double
  public let minimumPostLockSettleSeconds: Double
  public let metadataWindowSeconds: Double
  public let minimumMetadataWindowSeconds: Double
  public let metadataPollSeconds: Double

  public init(
    tuneAttemptCount: Int,
    settleSeconds: Double,
    minimumDeadlineSeconds: Double,
    confirmationGraceSeconds: Double,
    minimumPostLockSettleSeconds: Double,
    metadataWindowSeconds: Double,
    minimumMetadataWindowSeconds: Double,
    metadataPollSeconds: Double
  ) {
    self.tuneAttemptCount = tuneAttemptCount
    self.settleSeconds = settleSeconds
    self.minimumDeadlineSeconds = minimumDeadlineSeconds
    self.confirmationGraceSeconds = confirmationGraceSeconds
    self.minimumPostLockSettleSeconds = minimumPostLockSettleSeconds
    self.metadataWindowSeconds = metadataWindowSeconds
    self.minimumMetadataWindowSeconds = minimumMetadataWindowSeconds
    self.metadataPollSeconds = metadataPollSeconds
  }
}

extension FMDXBandScanMode {
  public func timingProfile(
    for band: FMDXQuickBand,
    customSettings: FMDXCustomScanSettings
  ) -> FMDXBandScanTimingProfile {
    switch self {
    case .standard:
      return FMDXBandScanTimingProfile(
        tuneAttemptCount: 2,
        settleSeconds: band.scannerSettleSeconds,
        minimumDeadlineSeconds: 0.45,
        confirmationGraceSeconds: 0.45,
        minimumPostLockSettleSeconds: 0.08,
        metadataWindowSeconds: band.scannerMetadataWindowSeconds,
        minimumMetadataWindowSeconds: band.scannerMinimumMetadataWindowSeconds,
        metadataPollSeconds: band.scannerMetadataPollSeconds
      )
    case .quickNewSignals:
      return FMDXBandScanTimingProfile(
        tuneAttemptCount: 1,
        settleSeconds: band.quickScannerSettleSeconds,
        minimumDeadlineSeconds: band.quickScannerMinimumDeadlineSeconds,
        confirmationGraceSeconds: band.quickScannerConfirmationGraceSeconds,
        minimumPostLockSettleSeconds: band.quickScannerMinimumPostLockSettleSeconds,
        metadataWindowSeconds: 0,
        minimumMetadataWindowSeconds: 0,
        metadataPollSeconds: band.scannerMetadataPollSeconds
      )
    case .veryFast:
      return FMDXBandScanTimingProfile(
        tuneAttemptCount: 1,
        settleSeconds: band.veryFastScannerSettleSeconds,
        minimumDeadlineSeconds: band.veryFastScannerMinimumDeadlineSeconds,
        confirmationGraceSeconds: band.veryFastScannerConfirmationGraceSeconds,
        minimumPostLockSettleSeconds: band.veryFastScannerMinimumPostLockSettleSeconds,
        metadataWindowSeconds: 0,
        minimumMetadataWindowSeconds: 0,
        metadataPollSeconds: band.scannerMetadataPollSeconds
      )
    case .custom:
      let metadataWindowSeconds = customSettings.metadataWindowSeconds
      let minimumMetadataWindowSeconds: Double
      if metadataWindowSeconds > 0 {
        minimumMetadataWindowSeconds = min(
          metadataWindowSeconds,
          band.customScannerMinimumMetadataWindowSeconds
        )
      } else {
        minimumMetadataWindowSeconds = 0
      }

      return FMDXBandScanTimingProfile(
        tuneAttemptCount: 1,
        settleSeconds: customSettings.settleSeconds,
        minimumDeadlineSeconds: max(
          band.quickScannerMinimumDeadlineSeconds,
          customSettings.settleSeconds + band.customScannerConfirmationGraceSeconds
        ),
        confirmationGraceSeconds: band.customScannerConfirmationGraceSeconds,
        minimumPostLockSettleSeconds: max(
          band.quickScannerMinimumPostLockSettleSeconds,
          min(customSettings.settleSeconds, 0.20)
        ),
        metadataWindowSeconds: metadataWindowSeconds,
        minimumMetadataWindowSeconds: minimumMetadataWindowSeconds,
        metadataPollSeconds: band.scannerMetadataPollSeconds
      )
    }
  }
}

extension FMDXQuickBand {
  public var scanStepOptionsHz: [Int] {
    switch self {
    case .lw, .mw:
      return [9_000, 10_000]
    case .sw:
      return [5_000, 10_000]
    case .oirt:
      return [10_000, 25_000, 30_000, 50_000, 100_000]
    case .fm:
      return [25_000, 50_000, 100_000, 200_000]
    case .noaa:
      return [5_000, 10_000, 12_500, 25_000]
    }
  }

  public var defaultScanStepHz: Int {
    switch self {
    case .lw, .mw:
      return 9_000
    case .sw:
      return 5_000
    case .oirt:
      return 50_000
    case .fm:
      return 100_000
    case .noaa:
      return 25_000
    }
  }

  public func peakMergeSpacingHz(stepHz: Int) -> Int {
    switch self {
    case .lw, .mw:
      return max(stepHz * 2, 18_000)
    case .sw:
      return max(stepHz * 2, 10_000)
    case .oirt, .fm:
      return max(stepHz * 3, 150_000)
    case .noaa:
      return max(stepHz * 2, 25_000)
    }
  }

  public var scannerSettleSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.16
    case .sw:
      return 0.18
    case .oirt:
      return 0.22
    case .fm:
      return 0.24
    case .noaa:
      return 0.20
    }
  }

  public var quickScannerSettleSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.10
    case .oirt, .fm:
      return 0.14
    case .noaa:
      return 0.12
    }
  }

  public var quickScannerMinimumDeadlineSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.26
    case .sw:
      return 0.28
    case .oirt, .fm:
      return 0.32
    case .noaa:
      return 0.28
    }
  }

  public var quickScannerConfirmationGraceSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.18
    case .sw:
      return 0.20
    case .oirt:
      return 0.24
    case .fm:
      return 0.26
    case .noaa:
      return 0.22
    }
  }

  public var quickScannerMinimumPostLockSettleSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.05
    case .oirt, .fm:
      return 0.06
    case .noaa:
      return 0.05
    }
  }

  public var veryFastScannerSettleSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.06
    case .sw:
      return 0.07
    case .oirt, .fm:
      return 0.09
    case .noaa:
      return 0.08
    }
  }

  public var veryFastScannerMinimumDeadlineSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.18
    case .sw:
      return 0.20
    case .oirt, .fm:
      return 0.22
    case .noaa:
      return 0.20
    }
  }

  public var veryFastScannerConfirmationGraceSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.10
    case .sw:
      return 0.11
    case .oirt:
      return 0.12
    case .fm:
      return 0.14
    case .noaa:
      return 0.12
    }
  }

  public var veryFastScannerMinimumPostLockSettleSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.03
    case .oirt, .fm:
      return 0.04
    case .noaa:
      return 0.03
    }
  }

  public var customScannerConfirmationGraceSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.16
    case .sw:
      return 0.18
    case .oirt:
      return 0.20
    case .fm:
      return 0.22
    case .noaa:
      return 0.18
    }
  }

  public var customScannerMinimumMetadataWindowSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.0
    case .oirt, .fm:
      return 0.20
    case .noaa:
      return 0.0
    }
  }

  public var scannerMetadataWindowSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.0
    case .oirt, .fm:
      return 1.05
    case .noaa:
      return 0.0
    }
  }

  public var scannerMinimumMetadataWindowSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.0
    case .oirt, .fm:
      return 0.25
    case .noaa:
      return 0.0
    }
  }

  public var scannerMetadataPollSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.12
    case .sw:
      return 0.15
    case .oirt, .fm:
      return 0.10
    case .noaa:
      return 0.10
    }
  }

  public var savedResultMatchToleranceHz: Int {
    switch self {
    case .lw, .mw:
      return 5_000
    case .sw:
      return 2_500
    case .oirt, .fm:
      return 50_000
    case .noaa:
      return 12_500
    }
  }
}

public struct FMDXBandScanSample: Equatable, Sendable {
  public let frequencyHz: Int
  public let mode: DemodulationMode
  public let signal: Double
  public let signalTop: Double?
  public let stationName: String?
  public let programService: String?
  public let radioText0: String?
  public let radioText1: String?
  public let city: String?
  public let countryName: String?
  public let distanceKm: String?
  public let erpKW: String?
  public let userCount: Int?

  public init(
    frequencyHz: Int,
    mode: DemodulationMode,
    signal: Double,
    signalTop: Double?,
    stationName: String?,
    programService: String?,
    radioText0: String?,
    radioText1: String?,
    city: String?,
    countryName: String?,
    distanceKm: String? = nil,
    erpKW: String? = nil,
    userCount: Int?
  ) {
    self.frequencyHz = frequencyHz
    self.mode = mode
    self.signal = signal
    self.signalTop = signalTop
    self.stationName = stationName
    self.programService = programService
    self.radioText0 = radioText0
    self.radioText1 = radioText1
    self.city = city
    self.countryName = countryName
    self.distanceKm = distanceKm
    self.erpKW = erpKW
    self.userCount = userCount
  }
}

public struct FMDXBandScanResult: Identifiable, Equatable, Codable, Sendable {
  public let frequencyHz: Int
  public let mode: DemodulationMode
  public let signal: Double
  public let signalTop: Double?
  public let stationName: String?
  public let programService: String?
  public let radioText0: String?
  public let radioText1: String?
  public let city: String?
  public let countryName: String?
  public let distanceKm: String?
  public let erpKW: String?
  public let userCount: Int?

  public init(
    frequencyHz: Int,
    mode: DemodulationMode,
    signal: Double,
    signalTop: Double?,
    stationName: String?,
    programService: String?,
    radioText0: String?,
    radioText1: String?,
    city: String?,
    countryName: String?,
    distanceKm: String? = nil,
    erpKW: String? = nil,
    userCount: Int?
  ) {
    self.frequencyHz = frequencyHz
    self.mode = mode
    self.signal = signal
    self.signalTop = signalTop
    self.stationName = stationName
    self.programService = programService
    self.radioText0 = radioText0
    self.radioText1 = radioText1
    self.city = city
    self.countryName = countryName
    self.distanceKm = distanceKm
    self.erpKW = erpKW
    self.userCount = userCount
  }

  public var id: String {
    "\(mode.rawValue)|\(frequencyHz)"
  }
}

public enum FMDXBandScanReducer {
  public static func reduce(
    samples: [FMDXBandScanSample],
    mergeSpacingHz: Int
  ) -> [FMDXBandScanResult] {
    guard !samples.isEmpty else { return [] }

    let sortedSamples = samples.sorted { lhs, rhs in
      if lhs.frequencyHz != rhs.frequencyHz {
        return lhs.frequencyHz < rhs.frequencyHz
      }
      return lhs.signal > rhs.signal
    }

    var clusters: [[FMDXBandScanSample]] = []
    var currentCluster: [FMDXBandScanSample] = []

    for sample in sortedSamples {
      if let previous = currentCluster.last,
        sample.frequencyHz - previous.frequencyHz > mergeSpacingHz {
        clusters.append(currentCluster)
        currentCluster = [sample]
      } else {
        currentCluster.append(sample)
      }
    }

    if !currentCluster.isEmpty {
      clusters.append(currentCluster)
    }

    return clusters.compactMap(makeResult(from:))
  }

  private static func makeResult(from cluster: [FMDXBandScanSample]) -> FMDXBandScanResult? {
    guard
      let strongest = cluster.max(by: { lhs, rhs in
        if lhs.signal != rhs.signal {
          return lhs.signal < rhs.signal
        }
        return lhs.frequencyHz > rhs.frequencyHz
      })
    else {
      return nil
    }

    let metadataByStrength = cluster.sorted { lhs, rhs in
      if lhs.signal != rhs.signal {
        return lhs.signal > rhs.signal
      }
      return lhs.frequencyHz < rhs.frequencyHz
    }

    func firstNonEmpty(_ values: [String?]) -> String? {
      values
        .compactMap {
          $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first(where: { !$0.isEmpty })
    }

    return FMDXBandScanResult(
      frequencyHz: strongest.frequencyHz,
      mode: strongest.mode,
      signal: strongest.signal,
      signalTop: strongest.signalTop,
      stationName: firstNonEmpty(metadataByStrength.map(\.stationName)),
      programService: firstNonEmpty(metadataByStrength.map(\.programService)),
      radioText0: firstNonEmpty(metadataByStrength.map(\.radioText0)),
      radioText1: firstNonEmpty(metadataByStrength.map(\.radioText1)),
      city: firstNonEmpty(metadataByStrength.map(\.city)),
      countryName: firstNonEmpty(metadataByStrength.map(\.countryName)),
      distanceKm: firstNonEmpty(metadataByStrength.map(\.distanceKm)),
      erpKW: firstNonEmpty(metadataByStrength.map(\.erpKW)),
      userCount: metadataByStrength.compactMap(\.userCount).max()
    )
  }
}

public enum FMDXSavedScanResultMatcher {
  public static func filterNewResults(
    _ results: [FMDXBandScanResult],
    comparedTo savedResults: [FMDXBandScanResult]
  ) -> [FMDXBandScanResult] {
    results.filter { candidate in
      !savedResults.contains(where: { saved in
        isSameResult(candidate, saved)
      })
    }
  }

  public static func isSameResult(
    _ lhs: FMDXBandScanResult,
    _ rhs: FMDXBandScanResult
  ) -> Bool {
    guard lhs.mode == rhs.mode else { return false }

    let quickBand = FMDXSessionCore.quickBand(for: lhs.frequencyHz, mode: lhs.mode)
    guard abs(lhs.frequencyHz - rhs.frequencyHz) <= quickBand.savedResultMatchToleranceHz else {
      return false
    }

    let lhsIdentity = normalizedIdentity(lhs)
    let rhsIdentity = normalizedIdentity(rhs)
    if let lhsIdentity, let rhsIdentity {
      return lhsIdentity == rhsIdentity
    }

    return true
  }

  public static func normalizedIdentity(_ result: FMDXBandScanResult) -> String? {
    let identity = result.stationName ?? result.programService
    let normalized = identity?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .lowercased()

    guard let normalized, !normalized.isEmpty else { return nil }
    return normalized
  }
}
