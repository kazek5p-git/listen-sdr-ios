import SwiftUI
import UIKit

enum AppTheme {
  static let tint = Color(red: 0.10, green: 0.49, blue: 0.92)
  static let accent = Color(red: 0.09, green: 0.69, blue: 0.56)

  static let cardFill = Color(
    uiColor: UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.9)
      }
      return UIColor.secondarySystemBackground.withAlphaComponent(0.9)
    }
  )

  static let cardStroke = Color(
    uiColor: UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor.white.withAlphaComponent(0.16)
      }
      return UIColor.black.withAlphaComponent(0.08)
    }
  )

  static let chipFill = Color(
    uiColor: UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor.white.withAlphaComponent(0.12)
      }
      return UIColor.black.withAlphaComponent(0.05)
    }
  )
}

struct AppScreenBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(uiColor: .systemGroupedBackground),
          Color(uiColor: .secondarySystemGroupedBackground)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(AppTheme.tint.opacity(0.18))
        .frame(width: 320, height: 320)
        .blur(radius: 70)
        .offset(x: -130, y: -260)

      Circle()
        .fill(AppTheme.accent.opacity(0.12))
        .frame(width: 360, height: 360)
        .blur(radius: 80)
        .offset(x: 180, y: 280)
    }
    .ignoresSafeArea()
  }
}

private struct AppScreenBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    ZStack {
      AppScreenBackground()
      content
    }
  }
}

private struct AppCardContainerModifier: ViewModifier {
  let padding: EdgeInsets

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(AppTheme.cardFill)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(AppTheme.cardStroke, lineWidth: 1)
      }
  }
}

extension View {
  func appScreenBackground() -> some View {
    modifier(AppScreenBackgroundModifier())
  }

  func appCardContainer(
    padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
  ) -> some View {
    modifier(AppCardContainerModifier(padding: padding))
  }

  func appSectionStyle() -> some View {
    self
      .listRowBackground(AppTheme.cardFill)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
  }
}
