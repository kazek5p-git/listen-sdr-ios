import XCTest
@testable import ListenSDR

final class AppAccessibilityTests: XCTestCase {
  private let settingsKey = "ListenSDR.sessionSettings.v1"
  private var originalSettingsData: Data?

  override func setUp() {
    super.setUp()
    originalSettingsData = UserDefaults.standard.data(forKey: settingsKey)
  }

  override func tearDown() {
    if let originalSettingsData {
      UserDefaults.standard.set(originalSettingsData, forKey: settingsKey)
    } else {
      UserDefaults.standard.removeObject(forKey: settingsKey)
    }
    super.tearDown()
  }

  func testInteractionSoundPreviewDoesNotCrashWhenEnabled() {
    persistInteractionSoundSettings(
      enabled: true,
      muteWhileRecording: false,
      volumeMultiplier: 1.0
    )

    AppInteractionFeedbackCenter.playInteractionSoundPreviewIfEnabled()

    waitForPlaybackDispatch()
  }

  func testRecordingTransitionDoesNotCrashWhenEnabled() {
    persistInteractionSoundSettings(
      enabled: true,
      muteWhileRecording: true,
      volumeMultiplier: 1.0,
      recordingSoundsEnabled: true
    )

    AppInteractionFeedbackCenter.playRecordingTransitionIfEnabled(isRecording: true)
    AppInteractionFeedbackCenter.playRecordingTransitionIfEnabled(isRecording: false)

    waitForPlaybackDispatch()
  }

  func testToggleInteractionFeedbackDoesNotCrashWhenEnabled() {
    persistInteractionSoundSettings(
      enabled: true,
      muteWhileRecording: false,
      volumeMultiplier: 1.0
    )

    AppInteractionFeedbackCenter.playIfEnabled(.enabled)
    AppInteractionFeedbackCenter.playIfEnabled(.disabled)

    waitForPlaybackDispatch()
  }

  func testConnectionTransitionDoesNotCrashWhenEnabled() {
    persistInteractionSoundSettings(
      enabled: false,
      muteWhileRecording: false,
      volumeMultiplier: 1.0,
      connectionSoundsEnabled: true
    )

    AppInteractionFeedbackCenter.playConnectionTransitionIfEnabled(succeeded: true)
    AppInteractionFeedbackCenter.playConnectionTransitionIfEnabled(succeeded: false)

    waitForPlaybackDispatch()
  }

  private func persistInteractionSoundSettings(
    enabled: Bool,
    muteWhileRecording: Bool,
    volumeMultiplier: Double,
    connectionSoundsEnabled: Bool = false,
    recordingSoundsEnabled: Bool = true
  ) {
    var settings = RadioSessionSettings.default
    settings.accessibilityInteractionSoundsEnabled = enabled
    settings.accessibilityInteractionSoundsMutedDuringRecording = muteWhileRecording
    settings.accessibilityInteractionSoundsVolume = volumeMultiplier
    settings.accessibilityConnectionSoundsEnabled = connectionSoundsEnabled
    settings.accessibilityRecordingSoundsEnabled = recordingSoundsEnabled
    let data = try! JSONEncoder().encode(settings)
    UserDefaults.standard.set(data, forKey: settingsKey)
  }

  private func waitForPlaybackDispatch() {
    let expectation = expectation(description: "interaction feedback task executed")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
  }
}
