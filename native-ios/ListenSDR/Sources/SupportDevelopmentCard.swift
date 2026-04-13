import SwiftUI
import UIKit

let listenSDRSupportBaseURL = URL(string: "https://paypal.me/KazimierzParzych")!

struct SupportDevelopmentCard: View {
  @Environment(\.openURL) private var openURL

  let descriptionText: String
  let showsCopyLinkButton: Bool

  @State private var customAmountInput = ""
  @State private var localStatusMessage: String?

  private let quickAmounts = [5, 10, 20, 50]
  private let amountColumns = [
    GridItem(.adaptive(minimum: 96), spacing: 12)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(descriptionText)
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryText)

      Text(
        L10n.text(
          "support.amounts.description",
          fallback: "Choose a quick amount or enter your own. PayPal still asks the user to confirm the payment."
        )
      )
      .font(.footnote)
      .foregroundStyle(AppTheme.secondaryText)

      LazyVGrid(columns: amountColumns, alignment: .leading, spacing: 12) {
        ForEach(quickAmounts, id: \.self) { amount in
          FocusRetainingButton {
            openSupportAmount("\(amount)")
          } label: {
            Text(
              String(
                format: L10n.text(
                  "support.amount.button_format",
                  fallback: "%d PLN"
                ),
                amount
              )
            )
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.accent)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text(
          L10n.text(
            "support.amount.custom.title",
            fallback: "Custom amount"
          )
        )
        .font(.subheadline.weight(.semibold))

        TextField(
          L10n.text(
            "support.amount.custom.placeholder",
            fallback: "For example 15"
          ),
          text: $customAmountInput
        )
        .keyboardType(.decimalPad)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardFill)
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppTheme.cardStroke, lineWidth: 1)
        }

        FocusRetainingButton {
          openCustomAmount()
        } label: {
          Text(
            L10n.text(
              "support.amount.custom.button",
              fallback: "Support with a custom amount"
            )
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
      }

      if showsCopyLinkButton {
        FocusRetainingButton {
          UIPasteboard.general.string = listenSDRSupportBaseURL.absoluteString
          localStatusMessage = L10n.text(
            "support.amount.copy_success",
            fallback: "The PayPal support link is now in the clipboard."
          )
        } label: {
          Text(
            L10n.text(
              "support.amount.copy_link",
              fallback: "Copy support link"
            )
          )
        }
      }

      if let localStatusMessage, !localStatusMessage.isEmpty {
        Text(localStatusMessage)
          .font(.footnote)
          .foregroundStyle(AppTheme.secondaryText)
      }
    }
  }

  private func openSupportAmount(_ amount: String) {
    guard let url = supportURL(forNormalizedAmount: amount) else { return }
    localStatusMessage = nil
    openURL(url)
  }

  private func openCustomAmount() {
    guard let normalizedAmount = normalizedCustomAmount() else {
      localStatusMessage = L10n.text(
        "support.amount.custom.invalid",
        fallback: "Enter a valid amount, for example 15 or 15.50."
      )
      return
    }

    openSupportAmount(normalizedAmount)
  }

  private func normalizedCustomAmount() -> String? {
    let trimmed = customAmountInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let replaced = trimmed.replacingOccurrences(of: ",", with: ".")
    let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
    guard replaced.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return nil }
    guard replaced.filter({ $0 == "." }).count <= 1 else { return nil }

    let decimalNumber = NSDecimalNumber(string: replaced, locale: Locale(identifier: "en_US_POSIX"))
    guard decimalNumber != .notANumber, decimalNumber.compare(.zero) == .orderedDescending else {
      return nil
    }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2

    return formatter.string(from: decimalNumber)
  }

  private func supportURL(forNormalizedAmount amount: String) -> URL? {
    URL(string: "\(listenSDRSupportBaseURL.absoluteString)/\(amount)PLN")
  }
}
