import Foundation

struct RadioSessionAudioMutePolicy {
  let settingsAudioMuted: Bool
  let communicationInterruptionActive: Bool
  let allowAudioDuringCommunicationInterruption: Bool

  var effectiveMuted: Bool {
    settingsAudioMuted || (communicationInterruptionActive && !allowAudioDuringCommunicationInterruption)
  }

  static func allowAudioDuringInterruption(
    whenUserRequestsMuted requestedMuted: Bool,
    communicationInterruptionActive: Bool
  ) -> Bool {
    communicationInterruptionActive && !requestedMuted
  }
}

extension RadioSessionSettings {
  func updatingAudioMuted(_ muted: Bool) -> RadioSessionSettings {
    var copy = self
    copy.audioMuted = muted
    return copy
  }
}
