import Dispatch
import MediaPlayer
import UIKit

final class SystemRemoteCommandController {
  static let shared = SystemRemoteCommandController()

  private var isConfigured = false
  private weak var radioSession: RadioSessionViewModel?
  private weak var recordingStore: RecordingStore?

  private init() {}

  func bind(radioSession: RadioSessionViewModel, recordingStore: RecordingStore) {
    self.radioSession = radioSession
    self.recordingStore = recordingStore

    guard !isConfigured else { return }
    configureCommandCenter()
    isConfigured = true
  }

  private func configureCommandCenter() {
    UIApplication.shared.beginReceivingRemoteControlEvents()

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.playCommand.isEnabled = true

    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.handleTune(stepCount: -1) ?? .commandFailed
    }
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.handleTune(stepCount: 1) ?? .commandFailed
    }
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.handleMagicTapAction() ?? .commandFailed
    }
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.handleSetMuted(true) ?? .commandFailed
    }
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.handleSetMuted(false) ?? .commandFailed
    }
  }

  private func handleTune(stepCount: Int) -> MPRemoteCommandHandlerStatus {
    onMainActor {
      guard let radioSession, radioSession.state == .connected else {
        return .commandFailed
      }
      radioSession.tune(byStepCount: stepCount)
      return .success
    }
  }

  private func handleMagicTapAction() -> MPRemoteCommandHandlerStatus {
    onMainActor {
      guard let radioSession else { return .commandFailed }
      return radioSession.performMagicTapAction(recordingStore: recordingStore) ? .success : .commandFailed
    }
  }

  private func handleSetMuted(_ muted: Bool) -> MPRemoteCommandHandlerStatus {
    onMainActor {
      guard let radioSession, radioSession.state == .connected else {
        return .commandFailed
      }
      if radioSession.settings.audioMuted != muted {
        radioSession.setAudioMuted(muted)
      }
      return .success
    }
  }

  private func onMainActor<Result>(_ action: @MainActor () -> Result) -> Result {
    if Thread.isMainThread {
      return MainActor.assumeIsolated { action() }
    }

    var result: Result?
    DispatchQueue.main.sync {
      result = MainActor.assumeIsolated { action() }
    }
    return result!
  }
}
