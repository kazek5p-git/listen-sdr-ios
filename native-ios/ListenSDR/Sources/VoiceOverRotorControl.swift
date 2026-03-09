import SwiftUI
import UIKit

struct VoiceOverRotorControl: UIViewRepresentable {
  let title: String
  let value: String
  let hint: String
  let frequencyRotorName: String
  let tuneStepRotorName: String
  let onTuneIncrement: () -> Void
  let onTuneDecrement: () -> Void
  let onStepIncrement: () -> Void
  let onStepDecrement: () -> Void

  func makeUIView(context: Context) -> VoiceOverRotorAnchorView {
    VoiceOverRotorAnchorView()
  }

  func updateUIView(_ uiView: VoiceOverRotorAnchorView, context: Context) {
    uiView.configure(
      title: title,
      value: value,
      hint: hint,
      frequencyRotorName: frequencyRotorName,
      tuneStepRotorName: tuneStepRotorName,
      onTuneIncrement: onTuneIncrement,
      onTuneDecrement: onTuneDecrement,
      onStepIncrement: onStepIncrement,
      onStepDecrement: onStepDecrement
    )
  }
}

final class VoiceOverRotorAnchorView: UIControl {
  private let titleLabel = UILabel()
  private let valueLabel = UILabel()

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

  override func accessibilityIncrement() {
    onTuneIncrement?()
  }

  override func accessibilityDecrement() {
    onTuneDecrement?()
  }

  func configure(
    title: String,
    value: String,
    hint: String,
    frequencyRotorName: String,
    tuneStepRotorName: String,
    onTuneIncrement: @escaping () -> Void,
    onTuneDecrement: @escaping () -> Void,
    onStepIncrement: @escaping () -> Void,
    onStepDecrement: @escaping () -> Void
  ) {
    titleLabel.text = title
    valueLabel.text = value

    self.onTuneIncrement = onTuneIncrement
    self.onTuneDecrement = onTuneDecrement
    self.onStepIncrement = onStepIncrement
    self.onStepDecrement = onStepDecrement

    accessibilityLabel = title
    accessibilityValue = value
    accessibilityHint = hint
    accessibilityCustomRotors = [
      makeRotor(name: frequencyRotorName, forward: onTuneIncrement, backward: onTuneDecrement),
      makeRotor(name: tuneStepRotorName, forward: onStepIncrement, backward: onStepDecrement)
    ]
  }

  private func setup() {
    isAccessibilityElement = true
    accessibilityTraits = [.button, .adjustable]
    backgroundColor = .secondarySystemGroupedBackground
    layer.cornerRadius = 12
    clipsToBounds = true

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .preferredFont(forTextStyle: .subheadline)
    titleLabel.textColor = .secondaryLabel
    titleLabel.numberOfLines = 1

    valueLabel.translatesAutoresizingMaskIntoConstraints = false
    valueLabel.font = .preferredFont(forTextStyle: .body)
    valueLabel.textColor = .label
    valueLabel.numberOfLines = 0

    addSubview(titleLabel)
    addSubview(valueLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
    ])
  }

  private func makeRotor(
    name: String,
    forward: @escaping () -> Void,
    backward: @escaping () -> Void
  ) -> UIAccessibilityCustomRotor {
    UIAccessibilityCustomRotor(name: name) { [weak self] predicate in
      guard let self else { return nil }

      DispatchQueue.main.async {
        switch predicate.searchDirection {
        case .next:
          forward()
        case .previous:
          backward()
        @unknown default:
          break
        }
      }

      return UIAccessibilityCustomRotorItemResult(targetElement: self, targetRange: nil)
    }
  }
}
