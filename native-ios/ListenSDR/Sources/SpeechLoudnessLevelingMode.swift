import Foundation

enum SpeechLoudnessLevelingMode: String, Codable, CaseIterable {
  case off
  case gentle
  case strong
  case veryStrong
  case custom

  var localizedTitle: String {
    switch self {
    case .off:
      return L10n.text("settings.audio.speech_loudness_leveling.off")
    case .gentle:
      return L10n.text("settings.audio.speech_loudness_leveling.gentle")
    case .strong:
      return L10n.text("settings.audio.speech_loudness_leveling.strong")
    case .veryStrong:
      return L10n.text("settings.audio.speech_loudness_leveling.very_strong")
    case .custom:
      return L10n.text("settings.audio.speech_loudness_leveling.custom")
    }
  }

  var localizedDetail: String {
    switch self {
    case .off:
      return L10n.text("settings.audio.speech_loudness_leveling.off.detail")
    case .gentle:
      return L10n.text("settings.audio.speech_loudness_leveling.gentle.detail")
    case .strong:
      return L10n.text("settings.audio.speech_loudness_leveling.strong.detail")
    case .veryStrong:
      return L10n.text("settings.audio.speech_loudness_leveling.very_strong.detail")
    case .custom:
      return L10n.text("settings.audio.speech_loudness_leveling.custom.detail")
    }
  }
}
