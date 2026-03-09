import SwiftUI
import UIKit

struct GlobalVoiceOverRotorBridge: UIViewRepresentable {
  let isEnabled: Bool
  let frequencyRotorName: String
  let tuneStepRotorName: String
  let onTuneIncrement: () -> Void
  let onTuneDecrement: () -> Void
  let onStepIncrement: () -> Void
  let onStepDecrement: () -> Void

  func makeUIView(context: Context) -> GlobalVoiceOverRotorInstallerView {
    GlobalVoiceOverRotorInstallerView()
  }

  func updateUIView(_ uiView: GlobalVoiceOverRotorInstallerView, context: Context) {
    uiView.configure(
      isEnabled: isEnabled,
      frequencyRotorName: frequencyRotorName,
      tuneStepRotorName: tuneStepRotorName,
      onTuneIncrement: onTuneIncrement,
      onTuneDecrement: onTuneDecrement,
      onStepIncrement: onStepIncrement,
      onStepDecrement: onStepDecrement
    )
  }
}

final class GlobalVoiceOverRotorInstallerView: UIView {
  private weak var installedWindow: UIWindow?
  private weak var installedRootView: UIView?
  private var isEnabled = false
  private var frequencyRotorName = ""
  private var tuneStepRotorName = ""
  private var onTuneIncrement: (() -> Void)?
  private var onTuneDecrement: (() -> Void)?
  private var onStepIncrement: (() -> Void)?
  private var onStepDecrement: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    clearInstalledRotors()
  }

  func configure(
    isEnabled: Bool,
    frequencyRotorName: String,
    tuneStepRotorName: String,
    onTuneIncrement: @escaping () -> Void,
    onTuneDecrement: @escaping () -> Void,
    onStepIncrement: @escaping () -> Void,
    onStepDecrement: @escaping () -> Void
  ) {
    self.isEnabled = isEnabled
    self.frequencyRotorName = frequencyRotorName
    self.tuneStepRotorName = tuneStepRotorName
    self.onTuneIncrement = onTuneIncrement
    self.onTuneDecrement = onTuneDecrement
    self.onStepIncrement = onStepIncrement
    self.onStepDecrement = onStepDecrement
    applyRotorsIfPossible()
  }

  private func setup() {
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    isHidden = true
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    applyRotorsIfPossible()
  }

  private func applyRotorsIfPossible() {
    DispatchQueue.main.async { [weak self] in
      self?.applyRotorsNow()
    }
  }

  private func applyRotorsNow() {
    guard let window else { return }
    let rootView = window.rootViewController?.view

    if installedWindow !== window || installedRootView !== rootView {
      clearInstalledRotors()
      installedWindow = window
      installedRootView = rootView
    }

    let rotors = isEnabled
      ? [
        makeRotor(name: frequencyRotorName, forward: onTuneIncrement, backward: onTuneDecrement),
        makeRotor(name: tuneStepRotorName, forward: onStepIncrement, backward: onStepDecrement)
      ]
      : []

    installedWindow?.accessibilityCustomRotors = rotors
    installedRootView?.accessibilityCustomRotors = rotors
  }

  private func clearInstalledRotors() {
    installedWindow?.accessibilityCustomRotors = nil
    installedRootView?.accessibilityCustomRotors = nil
    installedWindow = nil
    installedRootView = nil
  }

  private func makeRotor(
    name: String,
    forward: (() -> Void)?,
    backward: (() -> Void)?
  ) -> UIAccessibilityCustomRotor {
    UIAccessibilityCustomRotor(name: name) { [weak self] predicate in
      guard let self else { return nil }

      DispatchQueue.main.async {
        switch predicate.searchDirection {
        case .next:
          forward?()
        case .previous:
          backward?()
        @unknown default:
          break
        }
      }

      let targetElement = self.installedRootView ?? self.installedWindow ?? self
      return UIAccessibilityCustomRotorItemResult(targetElement: targetElement, targetRange: nil)
    }
  }
}
