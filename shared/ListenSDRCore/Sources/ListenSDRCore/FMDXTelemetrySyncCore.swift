import Foundation

public enum FMDXTelemetrySyncCore {
  public struct SettingsSnapshot: Equatable, Sendable {
    public var frequencyHz: Int
    public var tuneStepHz: Int
    public var preferredTuneStepHz: Int
    public var tuneStepPreferenceMode: TuneStepPreferenceMode
    public var mode: DemodulationMode
    public var agcEnabled: Bool
    public var noiseReductionEnabled: Bool
    public var imsEnabled: Bool

    public init(
      frequencyHz: Int,
      tuneStepHz: Int,
      preferredTuneStepHz: Int,
      tuneStepPreferenceMode: TuneStepPreferenceMode,
      mode: DemodulationMode,
      agcEnabled: Bool,
      noiseReductionEnabled: Bool,
      imsEnabled: Bool
    ) {
      self.frequencyHz = frequencyHz
      self.tuneStepHz = tuneStepHz
      self.preferredTuneStepHz = preferredTuneStepHz
      self.tuneStepPreferenceMode = tuneStepPreferenceMode
      self.mode = mode
      self.agcEnabled = agcEnabled
      self.noiseReductionEnabled = noiseReductionEnabled
      self.imsEnabled = imsEnabled
    }
  }

  public enum AudioMode: String, Codable, CaseIterable, Sendable {
    case mono
    case stereo

    public var isStereo: Bool {
      self == .stereo
    }
  }

  public struct BandwidthOption: Equatable, Codable, Sendable {
    public let id: String
    public let legacyValue: String?

    public init(id: String, legacyValue: String?) {
      self.id = id
      self.legacyValue = legacyValue
    }
  }

  public struct Capabilities: Equatable, Codable, Sendable {
    public let bandwidths: [BandwidthOption]
    public let supportsAM: Bool

    public init(
      bandwidths: [BandwidthOption] = [],
      supportsAM: Bool = false
    ) {
      self.bandwidths = bandwidths
      self.supportsAM = supportsAM
    }
  }

  public struct Telemetry: Equatable, Codable, Sendable {
    public let frequencyMHz: Double?
    public let audioMode: AudioMode?
    public let antenna: String?
    public let bandwidth: String?
    public let agc: String?
    public let eq: String?
    public let ims: String?

    public init(
      frequencyMHz: Double? = nil,
      audioMode: AudioMode? = nil,
      antenna: String? = nil,
      bandwidth: String? = nil,
      agc: String? = nil,
      eq: String? = nil,
      ims: String? = nil
    ) {
      self.frequencyMHz = frequencyMHz
      self.audioMode = audioMode
      self.antenna = antenna
      self.bandwidth = bandwidth
      self.agc = agc
      self.eq = eq
      self.ims = ims
    }
  }

  public struct Result: Equatable, Sendable {
    public let settings: SettingsSnapshot
    public let bandMemory: FMDXBandMemory
    public let resolvedAudioMode: AudioMode?
    public let resolvedAntennaID: String?
    public let resolvedBandwidthID: String?
    public let changedSettings: Bool
    public let shouldClearPendingTuneConfirmation: Bool
    public let reportedFrequencyHz: Int?
    public let reportedMode: DemodulationMode?

    public init(
      settings: SettingsSnapshot,
      bandMemory: FMDXBandMemory,
      resolvedAudioMode: AudioMode?,
      resolvedAntennaID: String?,
      resolvedBandwidthID: String?,
      changedSettings: Bool,
      shouldClearPendingTuneConfirmation: Bool,
      reportedFrequencyHz: Int?,
      reportedMode: DemodulationMode?
    ) {
      self.settings = settings
      self.bandMemory = bandMemory
      self.resolvedAudioMode = resolvedAudioMode
      self.resolvedAntennaID = resolvedAntennaID
      self.resolvedBandwidthID = resolvedBandwidthID
      self.changedSettings = changedSettings
      self.shouldClearPendingTuneConfirmation = shouldClearPendingTuneConfirmation
      self.reportedFrequencyHz = reportedFrequencyHz
      self.reportedMode = reportedMode
    }
  }

  public static func synchronizedState(
    settings: SettingsSnapshot,
    telemetry: Telemetry,
    capabilities: Capabilities,
    bandMemory: FMDXBandMemory,
    pendingTuneFrequencyHz: Int? = nil
  ) -> Result {
    var updatedSettings = settings
    var updatedBandMemory = bandMemory
    var changedSettings = false
    var shouldClearPendingTuneConfirmation = false
    var reportedFrequencyHz: Int?
    var reportedMode: DemodulationMode?

    if let agcEnabled = parseToggleState(telemetry.agc),
      updatedSettings.agcEnabled != agcEnabled {
      updatedSettings.agcEnabled = agcEnabled
      changedSettings = true
    }
    if let eqEnabled = parseToggleState(telemetry.eq),
      updatedSettings.noiseReductionEnabled != eqEnabled {
      updatedSettings.noiseReductionEnabled = eqEnabled
      changedSettings = true
    }
    if let imsEnabled = parseToggleState(telemetry.ims),
      updatedSettings.imsEnabled != imsEnabled {
      updatedSettings.imsEnabled = imsEnabled
      changedSettings = true
    }

    if let frequencyMHz = telemetry.frequencyMHz {
      let backendFrequencyHz = FMDXSessionCore.normalizedReportedFrequencyHz(fromMHz: frequencyMHz)
      let backendMode = FMDXSessionCore.inferredMode(for: backendFrequencyHz)
      reportedFrequencyHz = backendFrequencyHz
      reportedMode = backendMode

      if let pendingTuneFrequencyHz,
        abs(backendFrequencyHz - pendingTuneFrequencyHz) < 1_000 {
        shouldClearPendingTuneConfirmation = true
      }

      if updatedSettings.mode != backendMode {
        updatedSettings.mode = backendMode
        updatedSettings.tuneStepHz = normalizedTuneStepHz(
          preferredTuneStepHz: updatedSettings.preferredTuneStepHz,
          preferenceMode: updatedSettings.tuneStepPreferenceMode,
          currentFrequencyHz: updatedSettings.frequencyHz,
          mode: backendMode
        )
        changedSettings = true
      }

      if abs(backendFrequencyHz - updatedSettings.frequencyHz) >= 1_000 {
        updatedSettings.frequencyHz = backendFrequencyHz
        changedSettings = true
      }

      updatedBandMemory = FMDXSessionCore.rememberedFrequency(
        backendFrequencyHz,
        mode: backendMode,
        memory: updatedBandMemory
      )
    }

    return Result(
      settings: updatedSettings,
      bandMemory: updatedBandMemory,
      resolvedAudioMode: telemetry.audioMode,
      resolvedAntennaID: telemetry.antenna.flatMap { $0.isEmpty ? nil : $0 },
      resolvedBandwidthID: telemetry.bandwidth.flatMap {
        $0.isEmpty ? nil : resolveBandwidthSelectionID(from: $0, capabilities: capabilities)
      },
      changedSettings: changedSettings,
      shouldClearPendingTuneConfirmation: shouldClearPendingTuneConfirmation,
      reportedFrequencyHz: reportedFrequencyHz,
      reportedMode: reportedMode
    )
  }

  public static func resolveBandwidthSelectionID(
    from rawValue: String,
    capabilities: Capabilities
  ) -> String {
    if capabilities.bandwidths.contains(where: { $0.id == rawValue }) {
      return rawValue
    }
    if let match = capabilities.bandwidths.first(where: { $0.legacyValue == rawValue }) {
      return match.id
    }
    return rawValue
  }

  public static func parseToggleState(_ rawValue: String?) -> Bool? {
    guard let rawValue else { return nil }

    let normalized = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if ["1", "on", "true", "enabled", "yes", "auto", "agc"].contains(normalized) {
      return true
    }
    if ["0", "off", "false", "disabled", "no", "manual", "man"].contains(normalized) {
      return false
    }
    return nil
  }

  private static func normalizedTuneStepHz(
    preferredTuneStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    currentFrequencyHz: Int,
    mode: DemodulationMode
  ) -> Int {
    SessionTuningCore.tuneStepState(
      preferredStepHz: preferredTuneStepHz,
      preferenceMode: preferenceMode,
      context: BandTuningContext(
        backend: .fmDxWebserver,
        frequencyHz: currentFrequencyHz,
        mode: mode,
        bandName: nil,
        bandTags: []
      )
    ).tuneStepHz
  }
}
