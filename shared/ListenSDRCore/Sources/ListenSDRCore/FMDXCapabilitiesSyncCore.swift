import Foundation

public enum FMDXCapabilitiesSyncCore {
  public struct SettingsSnapshot: Equatable, Sendable {
    public var frequencyHz: Int
    public var tuneStepHz: Int
    public var preferredTuneStepHz: Int
    public var tuneStepPreferenceMode: TuneStepPreferenceMode
    public var mode: DemodulationMode

    public init(
      frequencyHz: Int,
      tuneStepHz: Int,
      preferredTuneStepHz: Int,
      tuneStepPreferenceMode: TuneStepPreferenceMode,
      mode: DemodulationMode
    ) {
      self.frequencyHz = frequencyHz
      self.tuneStepHz = tuneStepHz
      self.preferredTuneStepHz = preferredTuneStepHz
      self.tuneStepPreferenceMode = tuneStepPreferenceMode
      self.mode = mode
    }
  }

  public struct Result: Equatable, Sendable {
    public let settings: SettingsSnapshot
    public let resolvedBandwidthID: String?
    public let changedSettings: Bool
    public let forcedFMBandFallback: Bool

    public init(
      settings: SettingsSnapshot,
      resolvedBandwidthID: String?,
      changedSettings: Bool,
      forcedFMBandFallback: Bool
    ) {
      self.settings = settings
      self.resolvedBandwidthID = resolvedBandwidthID
      self.changedSettings = changedSettings
      self.forcedFMBandFallback = forcedFMBandFallback
    }
  }

  public static func synchronizedState(
    settings: SettingsSnapshot,
    selectedBandwidthID: String?,
    capabilities: FMDXTelemetrySyncCore.Capabilities
  ) -> Result {
    var updatedSettings = settings
    var changedSettings = false
    var forcedFMBandFallback = false

    if updatedSettings.mode == .am && !capabilities.supportsAM {
      updatedSettings.mode = .fm
      updatedSettings.tuneStepHz = normalizedTuneStepHz(
        preferredTuneStepHz: updatedSettings.preferredTuneStepHz,
        preferenceMode: updatedSettings.tuneStepPreferenceMode,
        currentFrequencyHz: updatedSettings.frequencyHz,
        mode: .fm
      )
      changedSettings = true
      forcedFMBandFallback = true
    }

    let resolvedBandwidthID = selectedBandwidthID.flatMap { id in
      id.isEmpty ? nil : FMDXTelemetrySyncCore.resolveBandwidthSelectionID(from: id, capabilities: capabilities)
    }

    return Result(
      settings: updatedSettings,
      resolvedBandwidthID: resolvedBandwidthID,
      changedSettings: changedSettings,
      forcedFMBandFallback: forcedFMBandFallback
    )
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
