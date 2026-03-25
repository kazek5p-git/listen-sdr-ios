import Foundation
import ListenSDRCore

typealias FMDXCapabilitiesSyncCore = ListenSDRCore.FMDXCapabilitiesSyncCore

extension ListenSDRCore.FMDXCapabilitiesSyncCore.SettingsSnapshot {
  init(_ settings: RadioSessionSettings) {
    self.init(
      frequencyHz: settings.frequencyHz,
      tuneStepHz: settings.tuneStepHz,
      preferredTuneStepHz: settings.preferredTuneStepHz,
      tuneStepPreferenceMode: settings.tuneStepPreferenceMode,
      mode: settings.mode
    )
  }

  func apply(to settings: inout RadioSessionSettings) {
    settings.frequencyHz = frequencyHz
    settings.tuneStepHz = tuneStepHz
    settings.preferredTuneStepHz = preferredTuneStepHz
    settings.tuneStepPreferenceMode = tuneStepPreferenceMode
    settings.mode = mode
  }
}
