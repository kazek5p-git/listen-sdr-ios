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
}

enum InteractionFeedbackTone {
  case disabled
  case enabled
  case recordingStarted
  case recordingStopped
}

@MainActor
private final class InteractionFeedbackPlayer {
  static let shared = InteractionFeedbackPlayer()
  private static let baseOutputGain: Double = 0.16

  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var isConfigured = false

  private init() {}

  func play(_ tone: InteractionFeedbackTone, volumeMultiplier: Double) {
    guard let profile = Self.profile(for: tone) else { return }
    let clampedVolumeMultiplier = RadioSessionSettings.clampedAccessibilityInteractionSoundsVolume(
      volumeMultiplier
    )
    let buffer = Self.makeBuffer(
      primaryFrequencyHz: profile.primaryFrequencyHz,
      secondaryFrequencyHz: profile.secondaryFrequencyHz,
      durationSeconds: profile.durationSeconds,
      outputGain: Self.baseOutputGain * clampedVolumeMultiplier
    )
    guard let buffer else { return }
    configureIfNeeded()
    guard ensureEngineIsRunning() else { return }

    playerNode.stop()
    playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
    playerNode.play()
  }

  private func configureIfNeeded() {
    guard !isConfigured else { return }
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    engine.prepare()
    isConfigured = true
  }

  private func ensureEngineIsRunning() -> Bool {
    if engine.isRunning {
      return true
    }

    do {
      try engine.start()
      return true
    } catch {
      return false
    }
  }

  private static func profile(for tone: InteractionFeedbackTone) -> (
    primaryFrequencyHz: Double,
    secondaryFrequencyHz: Double,
    durationSeconds: Double
  )? {
    switch tone {
    case .disabled:
      return (440, 880, 0.14)
    case .enabled:
      return (660, 1_320, 0.14)
    case .recordingStarted:
      return (740, 920, 0.18)
    case .recordingStopped:
      return (410, 320, 0.20)
    }
  }

  private static func makeBuffer(
    frequencyHz: Double,
    sampleRate: Double = 44_100,
    durationSeconds: Double = 0.14,
    outputGain: Double? = nil
  ) -> AVAudioPCMBuffer? {
    makeBuffer(
      primaryFrequencyHz: frequencyHz,
      secondaryFrequencyHz: frequencyHz * 2,
      sampleRate: sampleRate,
      durationSeconds: durationSeconds,
      outputGain: outputGain
    )
  }

  private static func makeBuffer(
    primaryFrequencyHz: Double,
    secondaryFrequencyHz: Double,
    sampleRate: Double = 44_100,
    durationSeconds: Double = 0.14,
    outputGain: Double? = nil
  ) -> AVAudioPCMBuffer? {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
      return nil
    }

    let frameCount = AVAudioFrameCount(durationSeconds * sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      return nil
    }

    buffer.frameLength = frameCount
    guard let channel = buffer.floatChannelData?.pointee else {
      return nil
    }

    let totalFrames = Int(frameCount)
    let attackFrames = max(1, Int(sampleRate * 0.012))
    let releaseFrames = max(1, Int(sampleRate * 0.055))
    let resolvedOutputGain = outputGain ?? baseOutputGain

    for frame in 0..<totalFrames {
      let time = Double(frame) / sampleRate
      let attackEnvelope = min(1, Double(frame) / Double(attackFrames))
      let releaseEnvelope = min(1, Double(totalFrames - frame) / Double(releaseFrames))
      let envelope = min(attackEnvelope, releaseEnvelope)
      let softenedEnvelope = envelope * envelope * (3 - 2 * envelope)
      let primary = sin(2 * Double.pi * primaryFrequencyHz * time)
      let accent = 0.28 * sin(2 * Double.pi * secondaryFrequencyHz * time + (Double.pi / 9))
      let subharmonic = 0.09 * sin(Double.pi * primaryFrequencyHz * time)
      channel[frame] = Float((primary + accent + subharmonic) * resolvedOutputGain * softenedEnvelope)
    }

    return buffer
  }
}

enum AppInteractionFeedbackCenter {
  private static let settingsKey = "ListenSDR.sessionSettings.v1"

  static func playIfEnabled(_ tone: InteractionFeedbackTone) {
    let configuration = interactionSoundConfiguration()
    guard configuration.isEnabled else { return }
    if configuration.muteWhileRecording, AudioRecordingController.shared.currentSnapshot().isRecording {
      return
    }
    play(tone, volumeMultiplier: configuration.volumeMultiplier)
  }

  static func playInteractionSoundsToggleTransition(to enabled: Bool) {
    let configuration = interactionSoundConfiguration()
    if enabled {
      play(.enabled, volumeMultiplier: configuration.volumeMultiplier)
    } else if configuration.isEnabled {
      play(.disabled, volumeMultiplier: configuration.volumeMultiplier)
    }
  }

  static func playInteractionSoundPreviewIfEnabled() {
    let configuration = interactionSoundConfiguration()
    guard configuration.isEnabled else { return }
    play(.enabled, volumeMultiplier: configuration.volumeMultiplier)
  }

  static func playRecordingTransitionIfEnabled(isRecording: Bool) {
    let configuration = interactionSoundConfiguration()
    guard configuration.isEnabled else { return }
    play(
      isRecording ? .recordingStarted : .recordingStopped,
      volumeMultiplier: configuration.volumeMultiplier
    )
  }

  private static func play(_ tone: InteractionFeedbackTone, volumeMultiplier: Double) {
    Task { @MainActor in
      InteractionFeedbackPlayer.shared.play(tone, volumeMultiplier: volumeMultiplier)
    }
  }

  private static func interactionSoundConfiguration() -> (
    isEnabled: Bool,
    muteWhileRecording: Bool,
    volumeMultiplier: Double
  ) {
    guard
      let raw = UserDefaults.standard.data(forKey: settingsKey),
      let decoded = try? JSONDecoder().decode(RadioSessionSettings.self, from: raw)
    else {
      let defaults = RadioSessionSettings.default
      return (
        defaults.accessibilityInteractionSoundsEnabled,
        defaults.accessibilityInteractionSoundsMutedDuringRecording,
        defaults.accessibilityInteractionSoundsVolume
      )
    }

    return (
      decoded.accessibilityInteractionSoundsEnabled,
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
