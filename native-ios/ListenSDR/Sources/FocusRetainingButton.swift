import SwiftUI
import UIKit

struct FocusRetainingButton<Label: View>: View {
  let role: ButtonRole?
  let restoreDelayNanoseconds: UInt64
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  @AccessibilityFocusState private var isAccessibilityFocused: Bool

  init(
    _ action: @escaping () -> Void,
    role: ButtonRole? = nil,
    restoreDelayNanoseconds: UInt64 = 120_000_000,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.role = role
    self.restoreDelayNanoseconds = restoreDelayNanoseconds
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
    guard UIAccessibility.isVoiceOverRunning else { return }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: restoreDelayNanoseconds)
      isAccessibilityFocused = true
    }
  }
}
