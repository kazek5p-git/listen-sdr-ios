import SwiftUI
import UIKit

struct AppThemePalette {
  let tint: Color
  let accent: Color
  let backgroundTop: Color
  let backgroundBottom: Color
  let glowPrimary: Color
  let glowSecondary: Color
  let cardFillLight: UIColor
  let cardFillDark: UIColor
  let cardStrokeLight: UIColor
  let cardStrokeDark: UIColor
  let chipFillLight: UIColor
  let chipFillDark: UIColor
  let primaryTextLight: UIColor
  let primaryTextDark: UIColor
  let secondaryTextLight: UIColor
  let secondaryTextDark: UIColor
}

enum AppThemeOption: String, CaseIterable, Identifiable {
  case classic
  case mistBlue
  case seaGlass
  case warmLight
  case custom

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .classic:
      return L10n.text("settings.appearance.theme.classic", fallback: "Classic")
    case .mistBlue:
      return L10n.text("settings.appearance.theme.mist_blue", fallback: "Mist Blue")
    case .seaGlass:
      return L10n.text("settings.appearance.theme.sea_glass", fallback: "Sea Glass")
    case .warmLight:
      return L10n.text("settings.appearance.theme.warm_light", fallback: "Warm Light")
    case .custom:
      return L10n.text("settings.appearance.theme.custom", fallback: "Custom")
    }
  }

  var localizedDetail: String {
    switch self {
    case .classic:
      return L10n.text(
        "settings.appearance.theme.classic.detail",
        fallback: "The current soft, bright look with airy blue-green accents."
      )
    case .mistBlue:
      return L10n.text(
        "settings.appearance.theme.mist_blue.detail",
        fallback: "A lightly muted, cool blue theme with a calm and elegant background."
      )
    case .seaGlass:
      return L10n.text(
        "settings.appearance.theme.sea_glass.detail",
        fallback: "A fresh teal and sea-glass palette with clear cards and soft contrast."
      )
    case .warmLight:
      return L10n.text(
        "settings.appearance.theme.warm_light.detail",
        fallback: "A warm bright theme with cream background and gentle amber accents."
      )
    case .custom:
      return L10n.text(
        "settings.appearance.theme.custom.detail",
        fallback: "Choose your own background, card, border, text and accent colors."
      )
    }
  }

  var palette: AppThemePalette {
    switch self {
    case .classic:
      return AppTheme.makePalette(
        tint: UIColor(red: 0.10, green: 0.49, blue: 0.92, alpha: 1),
        accent: UIColor(red: 0.09, green: 0.69, blue: 0.56, alpha: 1),
        backgroundTop: UIColor.systemGroupedBackground,
        backgroundBottom: UIColor.secondarySystemGroupedBackground,
        cardFillLight: UIColor.secondarySystemBackground.withAlphaComponent(0.9),
        cardFillDark: UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.9),
        cardStrokeLight: UIColor.black.withAlphaComponent(0.08),
        cardStrokeDark: UIColor.white.withAlphaComponent(0.16),
        chipFillLight: UIColor.black.withAlphaComponent(0.05),
        chipFillDark: UIColor.white.withAlphaComponent(0.12),
        primaryTextLight: UIColor.label,
        primaryTextDark: UIColor.label,
        secondaryTextLight: UIColor.secondaryLabel,
        secondaryTextDark: UIColor.secondaryLabel
      )
    case .mistBlue:
      return AppTheme.makePalette(
        tint: UIColor(red: 0.24, green: 0.37, blue: 0.57, alpha: 1),
        accent: UIColor(red: 0.49, green: 0.60, blue: 0.75, alpha: 1),
        backgroundTop: UIColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1),
        backgroundBottom: UIColor(red: 0.82, green: 0.86, blue: 0.92, alpha: 1),
        cardFillLight: UIColor(red: 0.975, green: 0.981, blue: 0.989, alpha: 0.95),
        cardFillDark: UIColor(red: 0.13, green: 0.17, blue: 0.24, alpha: 0.93),
        cardStrokeLight: UIColor(red: 0.24, green: 0.31, blue: 0.43, alpha: 0.12),
        cardStrokeDark: UIColor(red: 0.72, green: 0.79, blue: 0.88, alpha: 0.18),
        chipFillLight: UIColor(red: 0.24, green: 0.31, blue: 0.43, alpha: 0.08),
        chipFillDark: UIColor(red: 0.80, green: 0.86, blue: 0.94, alpha: 0.13),
        primaryTextLight: UIColor(red: 0.09, green: 0.14, blue: 0.22, alpha: 1),
        primaryTextDark: UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1),
        secondaryTextLight: UIColor(red: 0.31, green: 0.38, blue: 0.48, alpha: 1),
        secondaryTextDark: UIColor(red: 0.78, green: 0.83, blue: 0.90, alpha: 1)
      )
    case .seaGlass:
      return AppTheme.makePalette(
        tint: UIColor(red: 0.06, green: 0.53, blue: 0.63, alpha: 1),
        accent: UIColor(red: 0.12, green: 0.69, blue: 0.62, alpha: 1),
        backgroundTop: UIColor(red: 0.93, green: 0.98, blue: 0.97, alpha: 1),
        backgroundBottom: UIColor(red: 0.86, green: 0.95, blue: 0.93, alpha: 1),
        cardFillLight: UIColor(red: 0.98, green: 1.00, blue: 0.99, alpha: 0.92),
        cardFillDark: UIColor(red: 0.13, green: 0.23, blue: 0.24, alpha: 0.92),
        cardStrokeLight: UIColor(red: 0.10, green: 0.39, blue: 0.38, alpha: 0.10),
        cardStrokeDark: UIColor(red: 0.72, green: 0.90, blue: 0.87, alpha: 0.20),
        chipFillLight: UIColor(red: 0.08, green: 0.44, blue: 0.42, alpha: 0.07),
        chipFillDark: UIColor(red: 0.76, green: 0.92, blue: 0.88, alpha: 0.14),
        primaryTextLight: UIColor(red: 0.06, green: 0.19, blue: 0.20, alpha: 1),
        primaryTextDark: UIColor(red: 0.93, green: 0.98, blue: 0.97, alpha: 1),
        secondaryTextLight: UIColor(red: 0.28, green: 0.40, blue: 0.41, alpha: 1),
        secondaryTextDark: UIColor(red: 0.77, green: 0.90, blue: 0.88, alpha: 1)
      )
    case .warmLight:
      return AppTheme.makePalette(
        tint: UIColor(red: 0.66, green: 0.43, blue: 0.14, alpha: 1),
        accent: UIColor(red: 0.89, green: 0.60, blue: 0.23, alpha: 1),
        backgroundTop: UIColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1),
        backgroundBottom: UIColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1),
        cardFillLight: UIColor(red: 1.00, green: 0.99, blue: 0.97, alpha: 0.93),
        cardFillDark: UIColor(red: 0.24, green: 0.20, blue: 0.16, alpha: 0.92),
        cardStrokeLight: UIColor(red: 0.46, green: 0.32, blue: 0.15, alpha: 0.10),
        cardStrokeDark: UIColor(red: 0.94, green: 0.85, blue: 0.74, alpha: 0.18),
        chipFillLight: UIColor(red: 0.52, green: 0.35, blue: 0.14, alpha: 0.07),
        chipFillDark: UIColor(red: 0.98, green: 0.89, blue: 0.78, alpha: 0.13),
        primaryTextLight: UIColor(red: 0.21, green: 0.14, blue: 0.08, alpha: 1),
        primaryTextDark: UIColor(red: 0.99, green: 0.95, blue: 0.89, alpha: 1),
        secondaryTextLight: UIColor(red: 0.44, green: 0.33, blue: 0.21, alpha: 1),
        secondaryTextDark: UIColor(red: 0.92, green: 0.84, blue: 0.74, alpha: 1)
      )
    case .custom:
      return AppTheme.customPalette
    }
  }
}

enum AppTheme {
  static let selectionKey = "ListenSDR.appTheme.v1"

  static let customBackgroundTopKey = "ListenSDR.appTheme.custom.backgroundTop.v1"
  static let customBackgroundBottomKey = "ListenSDR.appTheme.custom.backgroundBottom.v1"
  static let customCardFillKey = "ListenSDR.appTheme.custom.cardFill.v1"
  static let customCardStrokeKey = "ListenSDR.appTheme.custom.cardStroke.v1"
  static let customPrimaryTextKey = "ListenSDR.appTheme.custom.primaryText.v1"
  static let customSecondaryTextKey = "ListenSDR.appTheme.custom.secondaryText.v1"
  static let customTintKey = "ListenSDR.appTheme.custom.tint.v1"
  static let customAccentKey = "ListenSDR.appTheme.custom.accent.v1"

  static let defaultCustomBackgroundTopHex = "#E6ECF4"
  static let defaultCustomBackgroundBottomHex = "#D1DBE8"
  static let defaultCustomCardFillHex = "#F9FBFD"
  static let defaultCustomCardStrokeHex = "#BCC8D7"
  static let defaultCustomPrimaryTextHex = "#162337"
  static let defaultCustomSecondaryTextHex = "#516277"
  static let defaultCustomTintHex = "#3D5F8C"
  static let defaultCustomAccentHex = "#7B8FAE"

  static var selectedTheme: AppThemeOption {
    guard
      let rawValue = UserDefaults.standard.string(forKey: selectionKey),
      let theme = AppThemeOption(rawValue: rawValue)
    else {
      return .classic
    }
    return theme
  }

  static var palette: AppThemePalette {
    selectedTheme.palette
  }

  static var tint: Color { palette.tint }
  static var accent: Color { palette.accent }

  static var cardFill: Color {
    dynamicColor(light: palette.cardFillLight, dark: palette.cardFillDark)
  }

  static var cardStroke: Color {
    dynamicColor(light: palette.cardStrokeLight, dark: palette.cardStrokeDark)
  }

  static var chipFill: Color {
    dynamicColor(light: palette.chipFillLight, dark: palette.chipFillDark)
  }

  static var primaryText: Color {
    dynamicColor(light: palette.primaryTextLight, dark: palette.primaryTextDark)
  }

  static var secondaryText: Color {
    dynamicColor(light: palette.secondaryTextLight, dark: palette.secondaryTextDark)
  }

  static func applyThemeAsCustomBase(_ option: AppThemeOption) {
    let sourceTheme = option == .custom ? AppThemeOption.mistBlue : option
    let sourcePalette = sourceTheme.palette
    let defaults = UserDefaults.standard

    defaults.set(hexString(from: sourcePalette.backgroundTop.uiColor), forKey: customBackgroundTopKey)
    defaults.set(hexString(from: sourcePalette.backgroundBottom.uiColor), forKey: customBackgroundBottomKey)
    defaults.set(hexString(from: sourcePalette.cardFillLight), forKey: customCardFillKey)
    defaults.set(hexString(from: sourcePalette.cardStrokeLight), forKey: customCardStrokeKey)
    defaults.set(hexString(from: sourcePalette.primaryTextLight), forKey: customPrimaryTextKey)
    defaults.set(hexString(from: sourcePalette.secondaryTextLight), forKey: customSecondaryTextKey)
    defaults.set(hexString(from: sourcePalette.tint.uiColor), forKey: customTintKey)
    defaults.set(hexString(from: sourcePalette.accent.uiColor), forKey: customAccentKey)
    defaults.set(AppThemeOption.custom.rawValue, forKey: selectionKey)
  }

  static func resetCustomTheme() {
    let defaults = UserDefaults.standard
    defaults.set(defaultCustomBackgroundTopHex, forKey: customBackgroundTopKey)
    defaults.set(defaultCustomBackgroundBottomHex, forKey: customBackgroundBottomKey)
    defaults.set(defaultCustomCardFillHex, forKey: customCardFillKey)
    defaults.set(defaultCustomCardStrokeHex, forKey: customCardStrokeKey)
    defaults.set(defaultCustomPrimaryTextHex, forKey: customPrimaryTextKey)
    defaults.set(defaultCustomSecondaryTextHex, forKey: customSecondaryTextKey)
    defaults.set(defaultCustomTintHex, forKey: customTintKey)
    defaults.set(defaultCustomAccentHex, forKey: customAccentKey)
  }

  static func customUIColor(forKey key: String, fallbackHex: String) -> UIColor {
    let rawValue = UserDefaults.standard.string(forKey: key) ?? fallbackHex
    return uiColor(fromHex: rawValue, fallbackHex: fallbackHex)
  }

  static func uiColor(fromHex rawValue: String, fallbackHex: String) -> UIColor {
    UIColor(hex: rawValue) ?? UIColor(hex: fallbackHex) ?? .systemBlue
  }

  static func hexString(from color: UIColor) -> String {
    color.rgbaHexString
  }

  static func makePalette(
    tint: UIColor,
    accent: UIColor,
    backgroundTop: UIColor,
    backgroundBottom: UIColor,
    cardFillLight: UIColor,
    cardFillDark: UIColor,
    cardStrokeLight: UIColor,
    cardStrokeDark: UIColor,
    chipFillLight: UIColor,
    chipFillDark: UIColor,
    primaryTextLight: UIColor,
    primaryTextDark: UIColor,
    secondaryTextLight: UIColor,
    secondaryTextDark: UIColor
  ) -> AppThemePalette {
    AppThemePalette(
      tint: Color(uiColor: tint),
      accent: Color(uiColor: accent),
      backgroundTop: Color(uiColor: backgroundTop),
      backgroundBottom: Color(uiColor: backgroundBottom),
      glowPrimary: Color(uiColor: tint.withAlphaComponent(0.18)),
      glowSecondary: Color(uiColor: accent.withAlphaComponent(0.12)),
      cardFillLight: cardFillLight,
      cardFillDark: cardFillDark,
      cardStrokeLight: cardStrokeLight,
      cardStrokeDark: cardStrokeDark,
      chipFillLight: chipFillLight,
      chipFillDark: chipFillDark,
      primaryTextLight: primaryTextLight,
      primaryTextDark: primaryTextDark,
      secondaryTextLight: secondaryTextLight,
      secondaryTextDark: secondaryTextDark
    )
  }

  private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
    Color(
      uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
      }
    )
  }

  private static var customPalette: AppThemePalette {
    let backgroundTop = customUIColor(
      forKey: customBackgroundTopKey,
      fallbackHex: defaultCustomBackgroundTopHex
    )
    let backgroundBottom = customUIColor(
      forKey: customBackgroundBottomKey,
      fallbackHex: defaultCustomBackgroundBottomHex
    )
    let cardFill = customUIColor(
      forKey: customCardFillKey,
      fallbackHex: defaultCustomCardFillHex
    )
    let cardStroke = customUIColor(
      forKey: customCardStrokeKey,
      fallbackHex: defaultCustomCardStrokeHex
    )
    let primaryText = customUIColor(
      forKey: customPrimaryTextKey,
      fallbackHex: defaultCustomPrimaryTextHex
    )
    let secondaryText = customUIColor(
      forKey: customSecondaryTextKey,
      fallbackHex: defaultCustomSecondaryTextHex
    )
    let tint = customUIColor(
      forKey: customTintKey,
      fallbackHex: defaultCustomTintHex
    )
    let accent = customUIColor(
      forKey: customAccentKey,
      fallbackHex: defaultCustomAccentHex
    )

    return makePalette(
      tint: tint,
      accent: accent,
      backgroundTop: backgroundTop,
      backgroundBottom: backgroundBottom,
      cardFillLight: cardFill,
      cardFillDark: cardFill,
      cardStrokeLight: cardStroke,
      cardStrokeDark: cardStroke,
      chipFillLight: tint.withAlphaComponent(0.10),
      chipFillDark: tint.withAlphaComponent(0.10),
      primaryTextLight: primaryText,
      primaryTextDark: primaryText,
      secondaryTextLight: secondaryText,
      secondaryTextDark: secondaryText
    )
  }
}

struct AppScreenBackground: View {
  @AppStorage(AppTheme.selectionKey) private var selectedThemeID = AppThemeOption.classic.rawValue

  var body: some View {
    let palette = AppTheme.palette

    ZStack {
      LinearGradient(
        colors: [
          palette.backgroundTop,
          palette.backgroundBottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(palette.glowPrimary)
        .frame(width: 320, height: 320)
        .blur(radius: 70)
        .offset(x: -130, y: -260)

      Circle()
        .fill(palette.glowSecondary)
        .frame(width: 360, height: 360)
        .blur(radius: 80)
        .offset(x: 180, y: 280)
    }
    .ignoresSafeArea()
    .id(selectedThemeID)
  }
}

private struct AppScreenBackgroundModifier: ViewModifier {
  @AppStorage(AppTheme.selectionKey) private var selectedThemeID = AppThemeOption.classic.rawValue

  func body(content: Content) -> some View {
    ZStack {
      AppScreenBackground()
      content
    }
    .id(selectedThemeID)
  }
}

private struct AppCardContainerModifier: ViewModifier {
  @AppStorage(AppTheme.selectionKey) private var selectedThemeID = AppThemeOption.classic.rawValue
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
      .id(selectedThemeID)
  }
}

private struct AppSectionStyleModifier: ViewModifier {
  @AppStorage(AppTheme.selectionKey) private var selectedThemeID = AppThemeOption.classic.rawValue

  func body(content: Content) -> some View {
    content
      .listRowBackground(AppTheme.cardFill)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
      .id(selectedThemeID)
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
    modifier(AppSectionStyleModifier())
  }
}

private extension UIColor {
  convenience init?(hex: String) {
    let cleaned = hex
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")

    let validString: String
    switch cleaned.count {
    case 6:
      validString = cleaned + "FF"
    case 8:
      validString = cleaned
    default:
      return nil
    }

    var value: UInt64 = 0
    guard Scanner(string: validString).scanHexInt64(&value) else {
      return nil
    }

    let red = CGFloat((value & 0xFF00_0000) >> 24) / 255
    let green = CGFloat((value & 0x00FF_0000) >> 16) / 255
    let blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
    let alpha = CGFloat(value & 0x0000_00FF) / 255

    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }

  var rgbaHexString: String {
    let resolved = resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    guard let components = resolved.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components else {
      return "#000000FF"
    }

    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    switch components.count {
    case 2:
      red = components[0]
      green = components[0]
      blue = components[0]
      alpha = components[1]
    default:
      red = components[0]
      green = components[1]
      blue = components[2]
      alpha = components.count >= 4 ? components[3] : 1
    }

    return String(
      format: "#%02X%02X%02X%02X",
      Int(round(red * 255)),
      Int(round(green * 255)),
      Int(round(blue * 255)),
      Int(round(alpha * 255))
    )
  }
}

private extension Color {
  var uiColor: UIColor {
    UIColor(self)
  }
}
