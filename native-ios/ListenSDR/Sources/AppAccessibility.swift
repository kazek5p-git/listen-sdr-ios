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
    .accessibilityLabel(title)
    .accessibilityValue(selectedTitle)
    .accessibilityHint(accessibilityHint)
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
