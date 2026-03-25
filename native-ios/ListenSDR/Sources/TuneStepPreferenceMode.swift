import ListenSDRCore

typealias TuneStepPreferenceMode = ListenSDRCore.TuneStepPreferenceMode

extension TuneStepPreferenceMode {
  var localizedTitle: String {
    switch self {
    case .manual:
      return L10n.text("settings.tuning.global_step.manual")
    case .automatic:
      return L10n.text("settings.tuning.global_step.automatic")
    }
  }

  var localizedDetail: String {
    switch self {
    case .manual:
      return L10n.text("settings.tuning.global_step.manual.detail")
    case .automatic:
      return L10n.text("settings.tuning.global_step.automatic.detail")
    }
  }
}
