import Foundation
import ListenSDRCore

typealias FMDXTelemetrySyncCore = ListenSDRCore.FMDXTelemetrySyncCore

extension ListenSDRCore.FMDXTelemetrySyncCore.SettingsSnapshot {
  init(_ settings: RadioSessionSettings) {
    self.init(
      frequencyHz: settings.frequencyHz,
      tuneStepHz: settings.tuneStepHz,
      preferredTuneStepHz: settings.preferredTuneStepHz,
      tuneStepPreferenceMode: settings.tuneStepPreferenceMode,
      mode: settings.mode,
      agcEnabled: settings.agcEnabled,
      noiseReductionEnabled: settings.noiseReductionEnabled,
      imsEnabled: settings.imsEnabled
    )
  }

  func apply(to settings: inout RadioSessionSettings) {
    settings.frequencyHz = frequencyHz
    settings.tuneStepHz = tuneStepHz
    settings.preferredTuneStepHz = preferredTuneStepHz
    settings.tuneStepPreferenceMode = tuneStepPreferenceMode
    settings.mode = mode
    settings.agcEnabled = agcEnabled
    settings.noiseReductionEnabled = noiseReductionEnabled
    settings.imsEnabled = imsEnabled
  }
}

extension ListenSDRCore.FMDXTelemetrySyncCore.AudioMode {
  init(_ audioMode: FMDXAudioMode) {
    self = audioMode.isStereo ? .stereo : .mono
  }
}

extension FMDXAudioMode {
  init(_ audioMode: ListenSDRCore.FMDXTelemetrySyncCore.AudioMode) {
    self = audioMode.isStereo ? .stereo : .mono
  }
}

extension ListenSDRCore.FMDXTelemetrySyncCore.BandwidthOption {
  init(_ option: FMDXControlOption) {
    self.init(
      id: option.id,
      legacyValue: option.legacyValue
    )
  }
}

extension ListenSDRCore.FMDXTelemetrySyncCore.Capabilities {
  init(_ capabilities: FMDXCapabilities) {
    self.init(
      bandwidths: capabilities.bandwidths.map(ListenSDRCore.FMDXTelemetrySyncCore.BandwidthOption.init),
      supportsAM: capabilities.supportsAM
    )
  }
}

extension ListenSDRCore.FMDXTelemetrySyncCore.Telemetry {
  init(_ telemetry: FMDXTelemetry) {
    self.init(
      frequencyMHz: telemetry.frequencyMHz,
      audioMode: telemetry.audioMode.map(ListenSDRCore.FMDXTelemetrySyncCore.AudioMode.init),
      antenna: telemetry.antenna,
      bandwidth: telemetry.bandwidth,
      agc: telemetry.agc,
      eq: telemetry.eq,
      ims: telemetry.ims
    )
  }
}
