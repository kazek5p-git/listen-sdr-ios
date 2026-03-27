import AVFoundation
import ListenSDRCore
import SwiftUI
import UIKit

enum ReceiverAccessibilityFocus: Hashable {
  case frequencyControl
  case tuneStepControl
}

@MainActor
final class AppAccessibilityState: ObservableObject {
  @Published var selectedTab: AppTab = .receiver

  var isReceiverTabActive: Bool {
    selectedTab == .receiver
  }
}

enum AppAccessibilityAnnouncementCenter {
  static func post(_ text: String?) {
    guard UIAccessibility.isVoiceOverRunning else { return }
    guard let text, !text.isEmpty else { return }
    UIAccessibility.post(notification: .announcement, argument: text)
  }

  static func postSelectionIfEnabled(_ selectedItemTitle: String?) {
    guard AppAccessibilitySettingsStore.currentSettings().accessibilitySelectionAnnouncementsEnabled else {
      return
    }
    guard let selectedItemTitle, !selectedItemTitle.isEmpty else { return }
    post(
      L10n.text(
        "common.announcement.selected_item",
        fallback: "%@ selected",
        selectedItemTitle
      )
    )
  }
}

enum InteractionFeedbackTone {
  case disabled
  case enabled
  case connectionSucceeded
  case connectionFailed
  case recordingStarted
  case recordingStopped
}

private enum AppAccessibilitySettingsStore {
  static let settingsKey = "ListenSDR.sessionSettings.v1"

  static func currentSettings() -> RadioSessionSettings {
    guard
      let raw = UserDefaults.standard.data(forKey: settingsKey),
      let decoded = try? JSONDecoder().decode(RadioSessionSettings.self, from: raw)
    else {
      return .default
    }

    return decoded
  }
}

private struct InteractionFeedbackToneSegment {
  let primaryFrequencyHz: Double
  let secondaryFrequencyHz: Double
  let durationSeconds: Double
  let gapAfterSeconds: Double
}

@MainActor
private final class InteractionFeedbackPlayer: NSObject, AVAudioPlayerDelegate {
  static let shared = InteractionFeedbackPlayer()
  private static let baseOutputGain: Double = 0.16

  private var activePlayer: AVAudioPlayer?

  private override init() {
    super.init()
  }

  func play(_ tone: InteractionFeedbackTone, volumeMultiplier: Double) {
    let segments = Self.profile(for: tone)
    guard !segments.isEmpty else { return }
    let clampedVolumeMultiplier = RadioSessionSettings.clampedAccessibilityInteractionSoundsVolume(
      volumeMultiplier
    )
    let toneData = Self.makeToneData(
      segments: segments,
      outputGain: Self.baseOutputGain * clampedVolumeMultiplier
    )
    guard let toneData else { return }

    do {
      let player = try AVAudioPlayer(data: toneData, fileTypeHint: AVFileType.wav.rawValue)
      player.delegate = self
      player.prepareToPlay()
      activePlayer?.stop()
      activePlayer = player
      if player.play() == false {
        activePlayer = nil
      }
    } catch {
      activePlayer = nil
    }
  }

  private static func profile(for tone: InteractionFeedbackTone) -> [InteractionFeedbackToneSegment] {
    switch tone {
    case .disabled:
      return [
        .init(primaryFrequencyHz: 440, secondaryFrequencyHz: 880, durationSeconds: 0.14, gapAfterSeconds: 0)
      ]
    case .enabled:
      return [
        .init(primaryFrequencyHz: 660, secondaryFrequencyHz: 1_320, durationSeconds: 0.14, gapAfterSeconds: 0)
      ]
    case .connectionSucceeded:
      return [
        .init(primaryFrequencyHz: 840, secondaryFrequencyHz: 1_260, durationSeconds: 0.12, gapAfterSeconds: 0.03),
        .init(primaryFrequencyHz: 840, secondaryFrequencyHz: 1_260, durationSeconds: 0.05, gapAfterSeconds: 0.03),
        .init(primaryFrequencyHz: 840, secondaryFrequencyHz: 1_260, durationSeconds: 0.12, gapAfterSeconds: 0.03),
        .init(primaryFrequencyHz: 840, secondaryFrequencyHz: 1_260, durationSeconds: 0.05, gapAfterSeconds: 0)
      ]
    case .connectionFailed:
      return [
        .init(primaryFrequencyHz: 360, secondaryFrequencyHz: 240, durationSeconds: 0.09, gapAfterSeconds: 0.04),
        .init(primaryFrequencyHz: 300, secondaryFrequencyHz: 180, durationSeconds: 0.14, gapAfterSeconds: 0)
      ]
    case .recordingStarted:
      return [
        .init(primaryFrequencyHz: 740, secondaryFrequencyHz: 920, durationSeconds: 0.18, gapAfterSeconds: 0)
      ]
    case .recordingStopped:
      return [
        .init(primaryFrequencyHz: 410, secondaryFrequencyHz: 320, durationSeconds: 0.20, gapAfterSeconds: 0)
      ]
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if activePlayer === player {
      activePlayer = nil
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if activePlayer === player {
      activePlayer = nil
    }
  }

  private static func makeToneData(
    segments: [InteractionFeedbackToneSegment],
    sampleRate: Double = 44_100,
    outputGain: Double? = nil
  ) -> Data? {
    let totalFrames = max(
      1,
      segments.reduce(0) { partial, segment in
        partial + max(1, Int(segment.durationSeconds * sampleRate))
          + max(0, Int(segment.gapAfterSeconds * sampleRate))
      }
    )
    let resolvedOutputGain = outputGain ?? baseOutputGain
    var pcmData = Data(capacity: totalFrames * 2)

    for segment in segments {
      let segmentFrames = max(1, Int(segment.durationSeconds * sampleRate))
      let attackFrames = max(1, Int(sampleRate * 0.012))
      let releaseFrames = max(1, Int(sampleRate * 0.055))

      for frame in 0..<segmentFrames {
        let time = Double(frame) / sampleRate
        let attackEnvelope = min(1, Double(frame) / Double(attackFrames))
        let releaseEnvelope = min(1, Double(segmentFrames - frame) / Double(releaseFrames))
        let envelope = min(attackEnvelope, releaseEnvelope)
        let softenedEnvelope = envelope * envelope * (3 - 2 * envelope)
        let primary = sin(2 * Double.pi * segment.primaryFrequencyHz * time)
        let accent = 0.28 * sin(
          2 * Double.pi * segment.secondaryFrequencyHz * time + (Double.pi / 9)
        )
        let subharmonic = 0.09 * sin(Double.pi * segment.primaryFrequencyHz * time)
        let sample = max(
          -1.0,
          min(1.0, (primary + accent + subharmonic) * resolvedOutputGain * softenedEnvelope)
        )
        var littleEndian = Int16((sample * Double(Int16.max)).rounded()).littleEndian
        withUnsafeBytes(of: &littleEndian) { pcmData.append(contentsOf: $0) }
      }

      let gapFrames = max(0, Int(segment.gapAfterSeconds * sampleRate))
      if gapFrames > 0 {
        pcmData.append(Data(repeating: 0, count: gapFrames * 2))
      }
    }

    var waveData = Data()
    waveData.append(
      makeWAVHeader(
        sampleRate: UInt32(max(8_000, min(192_000, Int(sampleRate.rounded())))),
        totalPCMBytes: pcmData.count
      )
    )
    waveData.append(pcmData)
    return waveData
  }

  private static func makeWAVHeader(sampleRate: UInt32, totalPCMBytes: Int) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let chunkSize = UInt32(totalPCMBytes + 36)
    let dataSize = UInt32(totalPCMBytes)

    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.append(littleEndianData(chunkSize))
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    data.append(littleEndianData(UInt32(16)))
    data.append(littleEndianData(UInt16(1)))
    data.append(littleEndianData(channels))
    data.append(littleEndianData(sampleRate))
    data.append(littleEndianData(byteRate))
    data.append(littleEndianData(blockAlign))
    data.append(littleEndianData(bitsPerSample))
    data.append("data".data(using: .ascii)!)
    data.append(littleEndianData(dataSize))
    return data
  }

  private static func littleEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
    var little = value.littleEndian
    return withUnsafeBytes(of: &little) { Data($0) }
  }
}

enum AppInteractionFeedbackCenter {
  static func playIfEnabled(_ tone: InteractionFeedbackTone) {
    let configuration = interactionSoundConfiguration()
    guard configuration.switchSoundsEnabled else { return }
    if configuration.muteSwitchSoundsWhileRecording,
      AudioRecordingController.shared.currentSnapshot().isRecording {
      return
    }
    play(tone, volumeMultiplier: configuration.volumeMultiplier)
  }

  static func playInteractionSoundsToggleTransition(to enabled: Bool) {
    let configuration = interactionSoundConfiguration()
    if enabled {
      play(.enabled, volumeMultiplier: configuration.volumeMultiplier)
    } else if configuration.switchSoundsEnabled {
      play(.disabled, volumeMultiplier: configuration.volumeMultiplier)
    }
  }

  static func playInteractionSoundPreviewIfEnabled() {
    let configuration = interactionSoundConfiguration()
    guard configuration.switchSoundsEnabled else { return }
    play(.enabled, volumeMultiplier: configuration.volumeMultiplier)
  }

  static func playRecordingTransitionIfEnabled(isRecording: Bool) {
    let configuration = interactionSoundConfiguration()
    guard configuration.recordingSoundsEnabled else { return }
    play(
      isRecording ? .recordingStarted : .recordingStopped,
      volumeMultiplier: configuration.volumeMultiplier
    )
  }

  static func playConnectionTransitionIfEnabled(succeeded: Bool) {
    let configuration = interactionSoundConfiguration()
    guard configuration.connectionSoundsEnabled else { return }
    play(
      succeeded ? .connectionSucceeded : .connectionFailed,
      volumeMultiplier: configuration.volumeMultiplier
    )
  }

  private static func play(_ tone: InteractionFeedbackTone, volumeMultiplier: Double) {
    Task { @MainActor in
      InteractionFeedbackPlayer.shared.play(tone, volumeMultiplier: volumeMultiplier)
    }
  }

  private static func interactionSoundConfiguration() -> (
    switchSoundsEnabled: Bool,
    connectionSoundsEnabled: Bool,
    recordingSoundsEnabled: Bool,
    muteSwitchSoundsWhileRecording: Bool,
    volumeMultiplier: Double
  ) {
    let decoded = AppAccessibilitySettingsStore.currentSettings()
    return (
      decoded.accessibilityInteractionSoundsEnabled,
      decoded.accessibilityConnectionSoundsEnabled,
      decoded.accessibilityRecordingSoundsEnabled,
      decoded.accessibilityInteractionSoundsMutedDuringRecording,
      decoded.accessibilityInteractionSoundsVolume
    )
  }
}

private struct VoiceOverStableModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.transaction { transaction in
      if UIAccessibility.isVoiceOverRunning {
        transaction.animation = nil
      }
    }
  }
}

private struct AccessibleControlModifier: ViewModifier {
  let label: String
  let value: String?
  let hint: String?

  func body(content: Content) -> some View {
    let base = content.accessibilityLabel(label)

    if let value, !value.isEmpty, let hint, !hint.isEmpty {
      base
        .accessibilityValue(value)
        .accessibilityHint(hint)
    } else if let value, !value.isEmpty {
      base.accessibilityValue(value)
    } else if let hint, !hint.isEmpty {
      base.accessibilityHint(hint)
    } else {
      base
    }
  }
}

struct AppSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .textCase(nil)
      .accessibilityAddTraits(.isHeader)
  }
}

struct CyclingOptionItem: Identifiable, Equatable {
  let id: String
  let title: String
  let detail: String?

  init(id: String, title: String, detail: String? = nil) {
    self.id = id
    self.title = title
    self.detail = detail
  }
}

struct CyclingOptionCard: View {
  let title: String
  let selectedTitle: String
  let detail: String?
  let canDecrement: Bool
  let canIncrement: Bool
  let accessibilityHint: String?
  let decrementAction: () -> Void
  let incrementAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      HStack(spacing: 12) {
        Button {
          decrementAction()
        } label: {
          Image(systemName: "minus")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!canDecrement)
        .accessibilityHidden(true)

        VStack(spacing: 4) {
          Text(selectedTitle)
            .font(.title3.monospacedDigit().weight(.semibold))
            .multilineTextAlignment(.center)

          if let detail, !detail.isEmpty {
            Text(detail)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .lineLimit(2)
              .minimumScaleFactor(0.75)
          }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)

        Button {
          incrementAction()
        } label: {
          Image(systemName: "plus")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canIncrement)
        .accessibilityHidden(true)
      }
    }
    .appCardContainer()
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .modifier(AccessibleControlModifier(label: title, value: selectedTitle, hint: accessibilityHint))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        guard canIncrement else { return }
        incrementAction()
      case .decrement:
        guard canDecrement else { return }
        decrementAction()
      @unknown default:
        break
      }
    }
  }
}

struct FocusRetainingButton<Label: View>: View {
  let role: ButtonRole?
  let restoreDelayNanoseconds: UInt64
  let retainsAccessibilityFocus: Bool
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  @AccessibilityFocusState private var isAccessibilityFocused: Bool

  init(
    _ action: @escaping () -> Void,
    role: ButtonRole? = nil,
    restoreDelayNanoseconds: UInt64 = 120_000_000,
    retainsAccessibilityFocus: Bool = true,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.role = role
    self.restoreDelayNanoseconds = restoreDelayNanoseconds
    self.retainsAccessibilityFocus = retainsAccessibilityFocus
    self.action = action
    self.label = label
  }

  var body: some View {
    Button(role: role) {
      action()
      restoreFocusIfNeeded()
    } label: {
      label()
    }
    .accessibilityFocused($isAccessibilityFocused)
  }

  private func restoreFocusIfNeeded() {
    guard retainsAccessibilityFocus else { return }
    guard UIAccessibility.isVoiceOverRunning else { return }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: restoreDelayNanoseconds)
      isAccessibilityFocused = true
    }
  }
}

struct AppAccessibilityRotorHost: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel

  var body: some View {
    let backend = profileStore.selectedProfile?.backend
    let isEnabled = backend != nil

    return GlobalVoiceOverRotorBridge(
      isEnabled: isEnabled,
      frequencyRotorName: L10n.text("receiver.voiceover_rotor.frequency"),
      tuneStepRotorName: L10n.text("receiver.voiceover_rotor.tune_step"),
      bookmarkRotorName: bookmarkRotorTitle(for: backend),
      onTuneIncrement: {
        guard let backend else { return }
        radioSession.tune(byStepCount: frequencyAdjustmentStepCount(forIncrement: true))
        announceFrequency(for: backend)
      },
      onTuneDecrement: {
        guard let backend else { return }
        radioSession.tune(byStepCount: frequencyAdjustmentStepCount(forIncrement: false))
        announceFrequency(for: backend)
      },
      onStepIncrement: {
        guard let backend else { return }
        cycleTuneStep(by: 1, backend: backend)
      },
      onStepDecrement: {
        guard let backend else { return }
        cycleTuneStep(by: -1, backend: backend)
      },
      onBookmarkIncrement: {
        guard let backend else { return }
        cycleBookmarkRotor(by: 1, backend: backend)
      },
      onBookmarkDecrement: {
        guard let backend else { return }
        cycleBookmarkRotor(by: -1, backend: backend)
      }
    )
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func frequencyAdjustmentStepCount(forIncrement isIncrement: Bool) -> Int {
    let baseStep = radioSession.settings.tuningGestureDirection.frequencyAdjustmentStepCount
    return isIncrement ? baseStep : -baseStep
  }

  private func cycleTuneStep(by offset: Int, backend: SDRBackend) {
    let steps = radioSession.tuneStepOptions(for: backend)
    guard !steps.isEmpty else { return }

    let currentStep = radioSession.settings.tuneStepHz
    let currentIndex: Int
    if let exactIndex = steps.firstIndex(of: currentStep) {
      currentIndex = exactIndex
    } else {
      currentIndex = steps.enumerated().min(by: {
        abs($0.element - currentStep) < abs($1.element - currentStep)
      })?.offset ?? 0
    }

    let nextIndex = min(max(currentIndex + offset, 0), steps.count - 1)
    guard nextIndex != currentIndex else { return }

    radioSession.setTuneStepHz(steps[nextIndex])
    let stepText = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
    AppAccessibilityAnnouncementCenter.post(
      L10n.text("receiver.tune_step.changed", stepText)
    )
  }

  private func announceFrequency(for backend: SDRBackend) {
    let value = radioSession.settings.frequencyHz
    let announcement: String

    switch backend {
    case .fmDxWebserver:
      announcement = FrequencyFormatter.fmDxMHzText(fromHz: value)
    case .kiwiSDR, .openWebRX:
      if value < 1_000_000 {
        let kilohertz = Int((Double(value) / 1_000.0).rounded())
        announcement = "\(kilohertz) kHz"
      } else {
        announcement = FrequencyFormatter.mhzText(fromHz: value)
      }
    }

    AppAccessibilityAnnouncementCenter.post(announcement)
  }

  private func bookmarkRotorTitle(for backend: SDRBackend?) -> String? {
    guard let backend else { return nil }
    guard !bookmarkRotorItems(for: backend).isEmpty else { return nil }
    return L10n.text(
      "receiver.voiceover_rotor.bookmarks",
      fallback: "Bookmarks and presets"
    )
  }

  private func bookmarkRotorItems(for backend: SDRBackend) -> [SDRServerBookmark] {
    switch backend {
    case .openWebRX:
      return radioSession.serverBookmarks
    case .fmDxWebserver:
      return radioSession.fmdxServerPresets
    case .kiwiSDR:
      return []
    }
  }

  private func cycleBookmarkRotor(by offset: Int, backend: SDRBackend) {
    let items = bookmarkRotorItems(for: backend)
    guard !items.isEmpty else { return }

    let currentIndex = currentBookmarkRotorIndex(in: items, backend: backend)
    let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
    guard nextIndex != currentIndex else { return }

    let bookmark = items[nextIndex]
    applyBookmarkRotorItem(bookmark, backend: backend)
  }

  private func currentBookmarkRotorIndex(
    in items: [SDRServerBookmark],
    backend: SDRBackend
  ) -> Int {
    if backend == .openWebRX, let lastOpenWebRXBookmark = radioSession.lastOpenWebRXBookmark,
      let exactLastIndex = items.firstIndex(of: lastOpenWebRXBookmark) {
      return exactLastIndex
    }

    if let currentIndex = items.firstIndex(where: {
      $0.frequencyHz == radioSession.settings.frequencyHz
        && ($0.modulation == nil || $0.modulation == radioSession.settings.mode)
    }) {
      return currentIndex
    }

    return items.enumerated().min(by: {
      abs($0.element.frequencyHz - radioSession.settings.frequencyHz)
        < abs($1.element.frequencyHz - radioSession.settings.frequencyHz)
    })?.offset ?? 0
  }

  private func applyBookmarkRotorItem(
    _ bookmark: SDRServerBookmark,
    backend: SDRBackend
  ) {
    switch backend {
    case .openWebRX:
      radioSession.applyServerBookmark(bookmark)
    case .fmDxWebserver:
      if let mode = bookmark.modulation {
        radioSession.setMode(mode)
      }
      radioSession.setFrequencyHz(bookmark.frequencyHz)
    case .kiwiSDR:
      return
    }

    if AppAccessibilitySettingsStore.currentSettings().accessibilitySelectionAnnouncementsEnabled {
      AppAccessibilityAnnouncementCenter.postSelectionIfEnabled(bookmark.name)
    } else {
      announceFrequency(for: backend)
    }
  }
}

extension View {
  func voiceOverStable() -> some View {
    modifier(VoiceOverStableModifier())
  }

  func accessibleControl(
    label: String,
    value: String? = nil,
    hint: String? = nil
  ) -> some View {
    modifier(AccessibleControlModifier(label: label, value: value, hint: hint))
  }
}
