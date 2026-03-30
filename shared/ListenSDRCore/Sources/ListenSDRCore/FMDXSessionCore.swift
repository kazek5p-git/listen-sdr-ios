import Foundation

public enum FMDXQuickBand: String, Codable, CaseIterable, Identifiable, Sendable {
  case lw
  case mw
  case sw
  case oirt
  case fm
  case noaa

  public var id: String { rawValue }

  public var mode: DemodulationMode {
    switch self {
    case .lw, .mw, .sw:
      return .am
    case .oirt, .fm, .noaa:
      return .fm
    }
  }

  public var rangeHz: ClosedRange<Int> {
    switch self {
    case .lw:
      return 100_000...519_000
    case .mw:
      return 520_000...1_709_000
    case .sw:
      return 1_710_000...29_600_000
    case .oirt:
      return 65_900_000...73_999_000
    case .fm:
      return 64_000_000...110_000_000
    case .noaa:
      return 162_400_000...162_550_000
    }
  }

  public var defaultFrequencyHz: Int {
    switch self {
    case .lw:
      return 225_000
    case .mw:
      return 999_000
    case .sw:
      return 7_050_000
    case .oirt:
      return 70_300_000
    case .fm:
      return 87_500_000
    case .noaa:
      return 162_400_000
    }
  }

  public var isAM: Bool {
    mode == .am
  }
}

public struct FMDXBandMemory: Codable, Equatable, Sendable {
  public var lastBroadcastFMFrequencyHz: Int
  public var lastNOAAFrequencyHz: Int
  public var lastOIRTFrequencyHz: Int
  public var lastLWFrequencyHz: Int
  public var lastMWFrequencyHz: Int
  public var lastSWFrequencyHz: Int
  public var lastSelectedFMQuickBand: FMDXQuickBand
  public var lastSelectedAMQuickBand: FMDXQuickBand

  public init(
    lastBroadcastFMFrequencyHz: Int = FMDXQuickBand.fm.defaultFrequencyHz,
    lastNOAAFrequencyHz: Int = FMDXQuickBand.noaa.defaultFrequencyHz,
    lastOIRTFrequencyHz: Int = FMDXQuickBand.oirt.defaultFrequencyHz,
    lastLWFrequencyHz: Int = FMDXQuickBand.lw.defaultFrequencyHz,
    lastMWFrequencyHz: Int = FMDXQuickBand.mw.defaultFrequencyHz,
    lastSWFrequencyHz: Int = FMDXQuickBand.sw.defaultFrequencyHz,
    lastSelectedFMQuickBand: FMDXQuickBand = .fm,
    lastSelectedAMQuickBand: FMDXQuickBand = .mw
  ) {
    self.lastBroadcastFMFrequencyHz = lastBroadcastFMFrequencyHz
    self.lastNOAAFrequencyHz = lastNOAAFrequencyHz
    self.lastOIRTFrequencyHz = lastOIRTFrequencyHz
    self.lastLWFrequencyHz = lastLWFrequencyHz
    self.lastMWFrequencyHz = lastMWFrequencyHz
    self.lastSWFrequencyHz = lastSWFrequencyHz
    self.lastSelectedFMQuickBand = lastSelectedFMQuickBand
    self.lastSelectedAMQuickBand = lastSelectedAMQuickBand
  }

  private enum CodingKeys: String, CodingKey {
    case lastBroadcastFMFrequencyHz
    case lastNOAAFrequencyHz
    case lastOIRTFrequencyHz
    case lastLWFrequencyHz
    case lastMWFrequencyHz
    case lastSWFrequencyHz
    case lastSelectedFMQuickBand
    case lastSelectedAMQuickBand
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      lastBroadcastFMFrequencyHz: try container.decodeIfPresent(Int.self, forKey: .lastBroadcastFMFrequencyHz) ?? FMDXQuickBand.fm.defaultFrequencyHz,
      lastNOAAFrequencyHz: try container.decodeIfPresent(Int.self, forKey: .lastNOAAFrequencyHz) ?? FMDXQuickBand.noaa.defaultFrequencyHz,
      lastOIRTFrequencyHz: try container.decodeIfPresent(Int.self, forKey: .lastOIRTFrequencyHz) ?? FMDXQuickBand.oirt.defaultFrequencyHz,
      lastLWFrequencyHz: try container.decodeIfPresent(Int.self, forKey: .lastLWFrequencyHz) ?? FMDXQuickBand.lw.defaultFrequencyHz,
      lastMWFrequencyHz: try container.decodeIfPresent(Int.self, forKey: .lastMWFrequencyHz) ?? FMDXQuickBand.mw.defaultFrequencyHz,
      lastSWFrequencyHz: try container.decodeIfPresent(Int.self, forKey: .lastSWFrequencyHz) ?? FMDXQuickBand.sw.defaultFrequencyHz,
      lastSelectedFMQuickBand: try container.decodeIfPresent(FMDXQuickBand.self, forKey: .lastSelectedFMQuickBand) ?? .fm,
      lastSelectedAMQuickBand: try container.decodeIfPresent(FMDXQuickBand.self, forKey: .lastSelectedAMQuickBand) ?? .mw
    )
  }
}

public enum FMDXSessionCore {
  public static let overallFrequencyRangeHz = 100_000...162_550_000

  public static func quickBand(for frequencyHz: Int, mode: DemodulationMode) -> FMDXQuickBand {
    if mode == .am {
      if FMDXQuickBand.lw.rangeHz.contains(frequencyHz) {
        return .lw
      }
      if FMDXQuickBand.mw.rangeHz.contains(frequencyHz) {
        return .mw
      }
      return .sw
    }

    if FMDXQuickBand.oirt.rangeHz.contains(frequencyHz) {
      return .oirt
    }
    if FMDXQuickBand.noaa.rangeHz.contains(frequencyHz) {
      return .noaa
    }
    return .fm
  }

  public static func inferredMode(for frequencyHz: Int) -> DemodulationMode {
    SessionFrequencyCore.fmdxFrequencyRange(for: .am).contains(frequencyHz) ? .am : .fm
  }

  public static func preferredQuickBand(
    for mode: DemodulationMode,
    memory: FMDXBandMemory
  ) -> FMDXQuickBand {
    switch mode {
    case .am:
      return memory.lastSelectedAMQuickBand.isAM ? memory.lastSelectedAMQuickBand : .mw
    default:
      return memory.lastSelectedFMQuickBand.isAM ? .fm : memory.lastSelectedFMQuickBand
    }
  }

  public static func preferredFrequency(
    for mode: DemodulationMode,
    memory: FMDXBandMemory
  ) -> Int {
    preferredFrequency(for: preferredQuickBand(for: mode, memory: memory), memory: memory)
  }

  public static func preferredFrequency(
    for band: FMDXQuickBand,
    memory: FMDXBandMemory
  ) -> Int {
    let preferred: Int
    switch band {
    case .lw:
      preferred = memory.lastLWFrequencyHz
    case .mw:
      preferred = memory.lastMWFrequencyHz
    case .sw:
      preferred = memory.lastSWFrequencyHz
    case .oirt:
      preferred = memory.lastOIRTFrequencyHz
    case .fm:
      preferred = memory.lastBroadcastFMFrequencyHz
    case .noaa:
      preferred = memory.lastNOAAFrequencyHz
    }

    return band.rangeHz.contains(preferred) ? preferred : band.defaultFrequencyHz
  }

  public static func notedSelectedQuickBand(
    _ band: FMDXQuickBand,
    memory: FMDXBandMemory
  ) -> FMDXBandMemory {
    var updated = memory
    switch band.mode {
    case .am:
      updated.lastSelectedAMQuickBand = band
    default:
      updated.lastSelectedFMQuickBand = band
    }
    return updated
  }

  public static func rememberedFrequency(
    _ frequencyHz: Int,
    mode: DemodulationMode,
    memory: FMDXBandMemory
  ) -> FMDXBandMemory {
    guard SessionFrequencyCore.fmdxFrequencyRange(for: mode).contains(frequencyHz) else {
      return memory
    }

    let band = quickBand(for: frequencyHz, mode: mode)
    var updated = memory

    switch band {
    case .lw:
      updated.lastLWFrequencyHz = frequencyHz
    case .mw:
      updated.lastMWFrequencyHz = frequencyHz
    case .sw:
      updated.lastSWFrequencyHz = frequencyHz
    case .oirt:
      updated.lastOIRTFrequencyHz = frequencyHz
    case .fm:
      updated.lastBroadcastFMFrequencyHz = frequencyHz
    case .noaa:
      updated.lastNOAAFrequencyHz = frequencyHz
    }

    return notedSelectedQuickBand(band, memory: updated)
  }

  public static func seededMemory(
    from frequencyHz: Int,
    memory: FMDXBandMemory
  ) -> FMDXBandMemory {
    if SessionFrequencyCore.fmdxFrequencyRange(for: .am).contains(frequencyHz) {
      return rememberedFrequency(
        frequencyHz,
        mode: .am,
        memory: memory
      )
    }
    if SessionFrequencyCore.fmdxFrequencyRange(for: .fm).contains(frequencyHz) {
      return rememberedFrequency(
        frequencyHz,
        mode: .fm,
        memory: memory
      )
    }
    return memory
  }

  public static func normalizedSessionFrequencyHz(
    _ value: Int,
    mode: DemodulationMode,
    memory: FMDXBandMemory
  ) -> Int {
    let targetRange = SessionFrequencyCore.fmdxFrequencyRange(for: mode)
    guard targetRange.contains(value) else {
      return preferredFrequency(for: mode, memory: memory)
    }

    let roundedToKHz = Int((Double(value) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, targetRange.lowerBound), targetRange.upperBound)
  }

  public static func normalizedReportedFrequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    let roundedToKHz = Int((Double(hz) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, overallFrequencyRangeHz.lowerBound), overallFrequencyRangeHz.upperBound)
  }
}
