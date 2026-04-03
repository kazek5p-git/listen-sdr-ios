import SwiftUI
import UIKit

struct NativeAdjustableChipControl: UIViewRepresentable {
  let accessibilityLabel: String
  let accessibilityValue: String
  let visibleTitle: String
  let visibleValue: String
  let isEnabled: Bool
  let onDecrement: () -> Void
  let onIncrement: () -> Void
  let onTapDecrement: () -> Void
  let onTapIncrement: () -> Void

  func makeUIView(context: Context) -> AdjustableChipControlView {
    let view = AdjustableChipControlView()
    return view
  }

  func updateUIView(_ uiView: AdjustableChipControlView, context: Context) {
    uiView.onDecrement = onDecrement
    uiView.onIncrement = onIncrement
    uiView.onTapDecrement = onTapDecrement
    uiView.onTapIncrement = onTapIncrement
    uiView.configure(
      accessibilityLabel: accessibilityLabel,
      accessibilityValue: accessibilityValue,
      visibleTitle: visibleTitle,
      visibleValue: visibleValue,
      isEnabled: isEnabled
    )
  }
}

final class AdjustableChipControlView: UIView {
  var onDecrement: (() -> Void)?
  var onIncrement: (() -> Void)?
  var onTapDecrement: (() -> Void)?
  var onTapIncrement: (() -> Void)?

  private lazy var accessibilityElementProxy = AdjustableChipAccessibilityElement(accessibilityContainer: self)
  private let minusButton = UIButton(type: .system)
  private let plusButton = UIButton(type: .system)
  private let titleLabel = UILabel()
  private let valueLabel = UILabel()
  private let centerStack = UIStackView()
  private let contentStack = UIStackView()
  fileprivate var controlIsEnabled = true

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize {
    let size = contentStack.systemLayoutSizeFitting(
      CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric),
      withHorizontalFittingPriority: .defaultLow,
      verticalFittingPriority: .fittingSizeLevel
    )
    return CGSize(width: max(108, ceil(size.width) + 10), height: 42)
  }

  func configure(
    accessibilityLabel: String,
    accessibilityValue: String,
    visibleTitle: String,
    visibleValue: String,
    isEnabled: Bool
  ) {
    controlIsEnabled = isEnabled

    titleLabel.text = visibleTitle
    valueLabel.text = visibleValue.isEmpty ? "-" : visibleValue

    minusButton.isEnabled = isEnabled
    plusButton.isEnabled = isEnabled
    alpha = isEnabled ? 1 : 0.5
    accessibilityElementProxy.owner = self
    accessibilityElementProxy.accessibilityLabel = accessibilityLabel
    accessibilityElementProxy.accessibilityValue = accessibilityValue.isEmpty ? "No data" : accessibilityValue
    accessibilityElementProxy.accessibilityTraits = isEnabled
      ? UIAccessibilityTraits.adjustable
      : [UIAccessibilityTraits.adjustable, UIAccessibilityTraits.notEnabled]
    accessibilityElementProxy.accessibilityHint = nil
    accessibilityElementProxy.accessibilityFrameInContainerSpace = bounds
    invalidateIntrinsicContentSize()
  }

  private func setup() {
    isAccessibilityElement = false
    shouldGroupAccessibilityChildren = false
    accessibilityElements = [accessibilityElementProxy]

    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    layer.borderColor = UIColor.separator.cgColor
    backgroundColor = UIColor.secondarySystemBackground

    minusButton.translatesAutoresizingMaskIntoConstraints = false
    plusButton.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    valueLabel.translatesAutoresizingMaskIntoConstraints = false
    centerStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    configureButton(minusButton, symbolName: "minus", action: #selector(handleTapDecrement))
    configureButton(plusButton, symbolName: "plus", action: #selector(handleTapIncrement))

    titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    titleLabel.textColor = .secondaryLabel
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.8
    titleLabel.isAccessibilityElement = false

    valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    valueLabel.textColor = .label
    valueLabel.textAlignment = .center
    valueLabel.adjustsFontSizeToFitWidth = true
    valueLabel.minimumScaleFactor = 0.7
    valueLabel.isAccessibilityElement = false

    centerStack.axis = .vertical
    centerStack.alignment = .center
    centerStack.distribution = .fill
    centerStack.spacing = 0
    centerStack.isAccessibilityElement = false
    centerStack.addArrangedSubview(titleLabel)
    centerStack.addArrangedSubview(valueLabel)

    contentStack.axis = .horizontal
    contentStack.alignment = .center
    contentStack.distribution = .fill
    contentStack.spacing = 2
    contentStack.isAccessibilityElement = false
    contentStack.addArrangedSubview(minusButton)
    contentStack.addArrangedSubview(centerStack)
    contentStack.addArrangedSubview(plusButton)

    addSubview(contentStack)

    NSLayoutConstraint.activate([
      contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
      contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

      minusButton.widthAnchor.constraint(equalToConstant: 24),
      plusButton.widthAnchor.constraint(equalToConstant: 24),
      minusButton.heightAnchor.constraint(equalToConstant: 34),
      plusButton.heightAnchor.constraint(equalToConstant: 34),
      centerStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])

    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .horizontal)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    accessibilityElementProxy.accessibilityFrameInContainerSpace = bounds
  }

  private func configureButton(_ button: UIButton, symbolName: String, action: Selector) {
    button.setImage(UIImage(systemName: symbolName), for: .normal)
    button.tintColor = .label
    button.backgroundColor = .clear
    button.layer.cornerRadius = 10
    button.layer.cornerCurve = .continuous
    button.isAccessibilityElement = false
    button.addTarget(self, action: action, for: .touchUpInside)
  }

  @objc
  private func handleTapDecrement() {
    guard controlIsEnabled else { return }
    onTapDecrement?()
  }

  @objc
  private func handleTapIncrement() {
    guard controlIsEnabled else { return }
    onTapIncrement?()
  }
}

private final class AdjustableChipAccessibilityElement: UIAccessibilityElement {
  weak var owner: AdjustableChipControlView?

  override func accessibilityIncrement() {
    guard owner?.controlIsEnabled == true else { return }
    owner?.onIncrement?()
  }

  override func accessibilityDecrement() {
    guard owner?.controlIsEnabled == true else { return }
    owner?.onDecrement?()
  }

  override func accessibilityActivate() -> Bool {
    guard owner?.controlIsEnabled == true else { return false }
    owner?.onTapIncrement?()
    return true
  }
}
