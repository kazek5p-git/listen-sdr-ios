import Foundation

struct FMDXBandScanRangeDefinition: Equatable {
  let mode: DemodulationMode
  let rangeHz: ClosedRange<Int>
  let stepOptionsHz: [Int]
  let defaultStepHz: Int
  let metadataProfileBand: FMDXQuickBand
  let mergeSpacingProfileBand: FMDXQuickBand
}

enum FMDXBandScanRangePreset: String, CaseIterable, Identifiable {
  case lowerUKF
  case upperUKF
  case fullUKF
  case lw
  case mw
  case sw

  var id: String { rawValue }

  var localizedTitle: String {
    L10n.text("fmdx.scanner.range.\(rawValue)")
  }

  static func availableCases(supportsAM: Bool) -> [FMDXBandScanRangePreset] {
    var presets: [FMDXBandScanRangePreset] = [.lowerUKF, .upperUKF, .fullUKF]
    if supportsAM {
      presets.append(contentsOf: [.sw, .mw, .lw])
    }
    return presets
  }

  var definition: FMDXBandScanRangeDefinition {
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

enum FMDXBandScanSequenceBuilder {
  static func buildFrequencies(
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

enum FMDXBandScanMode: String, CaseIterable, Identifiable {
  case standard
  case quickNewSignals
  case veryFast
  case custom

  var id: String { rawValue }

  var localizedTitle: String {
    L10n.text("fmdx.scanner.mode.\(rawValue)")
  }

  static func selectableCases(saveResultsEnabled: Bool) -> [FMDXBandScanMode] {
    saveResultsEnabled
      ? [.standard, .quickNewSignals, .veryFast, .custom]
      : [.standard, .veryFast, .custom]
  }
}

struct FMDXBandScanTimingProfile: Equatable {
  let tuneAttemptCount: Int
  let settleSeconds: Double
  let minimumDeadlineSeconds: Double
  let confirmationGraceSeconds: Double
  let minimumPostLockSettleSeconds: Double
  let metadataWindowSeconds: Double
  let minimumMetadataWindowSeconds: Double
  let metadataPollSeconds: Double
}

extension FMDXBandScanMode {
  func timingProfile(
    for band: FMDXQuickBand,
    settings: RadioSessionSettings
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
      let metadataWindowSeconds = settings.fmdxCustomScanMetadataWindowSeconds
      let minimumMetadataWindowSeconds: Double
      if metadataWindowSeconds > 0 {
        minimumMetadataWindowSeconds = min(metadataWindowSeconds, band.customScannerMinimumMetadataWindowSeconds)
      } else {
        minimumMetadataWindowSeconds = 0
      }

      return FMDXBandScanTimingProfile(
        tuneAttemptCount: 1,
        settleSeconds: settings.fmdxCustomScanSettleSeconds,
        minimumDeadlineSeconds: max(
          band.quickScannerMinimumDeadlineSeconds,
          settings.fmdxCustomScanSettleSeconds + band.customScannerConfirmationGraceSeconds
        ),
        confirmationGraceSeconds: band.customScannerConfirmationGraceSeconds,
        minimumPostLockSettleSeconds: max(
          band.quickScannerMinimumPostLockSettleSeconds,
          min(settings.fmdxCustomScanSettleSeconds, 0.20)
        ),
        metadataWindowSeconds: metadataWindowSeconds,
        minimumMetadataWindowSeconds: minimumMetadataWindowSeconds,
        metadataPollSeconds: band.scannerMetadataPollSeconds
      )
    }
  }
}

extension FMDXQuickBand {
  var scanStepOptionsHz: [Int] {
    switch self {
    case .lw, .mw:
      return [9_000, 10_000]
    case .sw:
      return [5_000, 10_000]
    case .oirt:
      return [10_000, 25_000, 30_000, 50_000, 100_000]
    case .fm:
      return [25_000, 50_000, 100_000, 200_000]
    }
  }

  var defaultScanStepHz: Int {
    switch self {
    case .lw, .mw:
      return 9_000
    case .sw:
      return 5_000
    case .oirt:
      return 50_000
    case .fm:
      return 100_000
    }
  }

  func peakMergeSpacingHz(stepHz: Int) -> Int {
    switch self {
    case .lw, .mw:
      return max(stepHz * 2, 18_000)
    case .sw:
      return max(stepHz * 2, 10_000)
    case .oirt, .fm:
      return max(stepHz * 3, 150_000)
    }
  }

  var scannerSettleSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.16
    case .sw:
      return 0.18
    case .oirt:
      return 0.22
    case .fm:
      return 0.24
    }
  }

  var quickScannerSettleSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.10
    case .sw:
      return 0.10
    case .oirt, .fm:
      return 0.14
    }
  }

  var quickScannerMinimumDeadlineSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.26
    case .sw:
      return 0.28
    case .oirt, .fm:
      return 0.32
    }
  }

  var quickScannerConfirmationGraceSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.18
    case .sw:
      return 0.20
    case .oirt:
      return 0.24
    case .fm:
      return 0.26
    }
  }

  var quickScannerMinimumPostLockSettleSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.05
    case .oirt, .fm:
      return 0.06
    }
  }

  var veryFastScannerSettleSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.06
    case .sw:
      return 0.07
    case .oirt, .fm:
      return 0.09
    }
  }

  var veryFastScannerMinimumDeadlineSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.18
    case .sw:
      return 0.20
    case .oirt, .fm:
      return 0.22
    }
  }

  var veryFastScannerConfirmationGraceSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.10
    case .sw:
      return 0.11
    case .oirt:
      return 0.12
    case .fm:
      return 0.14
    }
  }

  var veryFastScannerMinimumPostLockSettleSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.03
    case .oirt, .fm:
      return 0.04
    }
  }

  var customScannerConfirmationGraceSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.16
    case .sw:
      return 0.18
    case .oirt:
      return 0.20
    case .fm:
      return 0.22
    }
  }

  var customScannerMinimumMetadataWindowSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.0
    case .oirt, .fm:
      return 0.20
    }
  }

  var scannerMetadataWindowSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.0
    case .oirt, .fm:
      return 1.05
    }
  }

  var scannerMinimumMetadataWindowSeconds: Double {
    switch self {
    case .lw, .mw, .sw:
      return 0.0
    case .oirt, .fm:
      return 0.25
    }
  }

  var scannerMetadataPollSeconds: Double {
    switch self {
    case .lw, .mw:
      return 0.12
    case .sw:
      return 0.15
    case .oirt, .fm:
      return 0.10
    }
  }

  var savedResultMatchToleranceHz: Int {
    switch self {
    case .lw, .mw:
      return 5_000
    case .sw:
      return 2_500
    case .oirt, .fm:
      return 50_000
    }
  }
}

struct FMDXBandScanSample: Equatable {
  let frequencyHz: Int
  let mode: DemodulationMode
  let signal: Double
  let signalTop: Double?
  let stationName: String?
  let programService: String?
  let radioText0: String?
  let radioText1: String?
  let city: String?
  let countryName: String?
  let distanceKm: String?
  let erpKW: String?
  let userCount: Int?

  init(
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

struct FMDXBandScanResult: Identifiable, Equatable, Codable {
  let frequencyHz: Int
  let mode: DemodulationMode
  let signal: Double
  let signalTop: Double?
  let stationName: String?
  let programService: String?
  let radioText0: String?
  let radioText1: String?
  let city: String?
  let countryName: String?
  let distanceKm: String?
  let erpKW: String?
  let userCount: Int?

  init(
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

  var id: String {
    "\(mode.rawValue)|\(frequencyHz)"
  }
}

enum FMDXBandScanReducer {
  static func reduce(
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

enum FMDXSavedScanResultMatcher {
  static func filterNewResults(
    _ results: [FMDXBandScanResult],
    comparedTo savedResults: [FMDXBandScanResult]
  ) -> [FMDXBandScanResult] {
    results.filter { candidate in
      !savedResults.contains(where: { saved in
        isSameResult(candidate, saved)
      })
    }
  }

  static func isSameResult(
    _ lhs: FMDXBandScanResult,
    _ rhs: FMDXBandScanResult
  ) -> Bool {
    guard lhs.mode == rhs.mode else { return false }

    let quickBand = FMDXQuickBand.resolve(frequencyHz: lhs.frequencyHz, mode: lhs.mode)
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

  static func normalizedIdentity(_ result: FMDXBandScanResult) -> String? {
    let identity = result.stationName ?? result.programService
    let normalized = identity?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .lowercased()

    guard let normalized, !normalized.isEmpty else { return nil }
    return normalized
  }
}
