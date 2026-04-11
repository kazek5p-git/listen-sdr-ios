import SwiftUI
import UIKit

struct CustomThemeEditorView: View {
  @AppStorage(AppTheme.selectionKey) private var selectedThemeID = AppThemeOption.classic.rawValue
  @AppStorage(AppTheme.customBackgroundTopKey) private var backgroundTopHex = AppTheme.defaultCustomBackgroundTopHex
  @AppStorage(AppTheme.customBackgroundBottomKey) private var backgroundBottomHex = AppTheme.defaultCustomBackgroundBottomHex
  @AppStorage(AppTheme.customCardFillKey) private var cardFillHex = AppTheme.defaultCustomCardFillHex
  @AppStorage(AppTheme.customCardStrokeKey) private var cardStrokeHex = AppTheme.defaultCustomCardStrokeHex
  @AppStorage(AppTheme.customPrimaryTextKey) private var primaryTextHex = AppTheme.defaultCustomPrimaryTextHex
  @AppStorage(AppTheme.customSecondaryTextKey) private var secondaryTextHex = AppTheme.defaultCustomSecondaryTextHex
  @AppStorage(AppTheme.customTintKey) private var tintHex = AppTheme.defaultCustomTintHex
  @AppStorage(AppTheme.customAccentKey) private var accentHex = AppTheme.defaultCustomAccentHex

  var body: some View {
    SwiftUI.Form {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            L10n.text(
              "settings.appearance.custom.description",
              fallback: "Build your own skin by choosing background, card, text and accent colors. Any color change switches the app to the custom skin immediately."
            )
          )
          .font(.footnote)
          .foregroundStyle(AppTheme.secondaryText)

          if selectedThemeID != AppThemeOption.custom.rawValue,
             let selectedTheme = AppThemeOption(rawValue: selectedThemeID) {
            FocusRetainingButton {
              AppTheme.applyThemeAsCustomBase(selectedTheme)
              selectedThemeID = AppThemeOption.custom.rawValue
            } label: {
              Text(
                L10n.text(
                  "settings.appearance.custom.use_current_base",
                  fallback: "Use the currently selected skin as the starting point"
                )
              )
            }
          }

          FocusRetainingButton {
            selectedThemeID = AppThemeOption.custom.rawValue
          } label: {
            Text(
              L10n.text(
                "settings.appearance.custom.activate",
                fallback: "Switch to the custom skin"
              )
            )
          }
        }
      } header: {
        AppSectionHeader(
          title: L10n.text(
            "settings.appearance.custom.section",
            fallback: "Custom skin"
          )
        )
      }
      .appSectionStyle()

      Section {
        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.background_top", fallback: "Top background"),
          selection: colorBinding(hex: $backgroundTopHex, fallbackHex: AppTheme.defaultCustomBackgroundTopHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.background_bottom", fallback: "Bottom background"),
          selection: colorBinding(hex: $backgroundBottomHex, fallbackHex: AppTheme.defaultCustomBackgroundBottomHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.card_fill", fallback: "Card background"),
          selection: colorBinding(hex: $cardFillHex, fallbackHex: AppTheme.defaultCustomCardFillHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.card_stroke", fallback: "Card border"),
          selection: colorBinding(hex: $cardStrokeHex, fallbackHex: AppTheme.defaultCustomCardStrokeHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.primary_text", fallback: "Main text"),
          selection: colorBinding(hex: $primaryTextHex, fallbackHex: AppTheme.defaultCustomPrimaryTextHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.secondary_text", fallback: "Secondary text"),
          selection: colorBinding(hex: $secondaryTextHex, fallbackHex: AppTheme.defaultCustomSecondaryTextHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.tint", fallback: "Main accent"),
          selection: colorBinding(hex: $tintHex, fallbackHex: AppTheme.defaultCustomTintHex)
        )

        CustomThemeColorPickerRow(
          title: L10n.text("settings.appearance.custom.accent", fallback: "Second accent"),
          selection: colorBinding(hex: $accentHex, fallbackHex: AppTheme.defaultCustomAccentHex)
        )
      } header: {
        AppSectionHeader(
          title: L10n.text(
            "settings.appearance.custom.colors",
            fallback: "Custom colors"
          )
        )
      }
      .appSectionStyle()

      Section {
        FocusRetainingButton(role: .destructive) {
          AppTheme.resetCustomTheme()
          selectedThemeID = AppThemeOption.custom.rawValue
        } label: {
          Text(
            L10n.text(
              "settings.appearance.custom.reset",
              fallback: "Reset custom skin to defaults"
            )
          )
        }
      }
      .appSectionStyle()
    }
    .voiceOverStable()
    .scrollContentBackground(.hidden)
    .navigationTitle(
      L10n.text(
        "settings.appearance.custom.navigation_title",
        fallback: "Customize skin"
      )
    )
    .navigationBarTitleDisplayMode(.inline)
    .appScreenBackground()
    .foregroundStyle(AppTheme.primaryText)
  }

  private func colorBinding(hex: Binding<String>, fallbackHex: String) -> Binding<Color> {
    Binding(
      get: {
        Color(
          uiColor: AppTheme.uiColor(
            fromHex: hex.wrappedValue.isEmpty ? fallbackHex : hex.wrappedValue,
            fallbackHex: fallbackHex
          )
        )
      },
      set: { newValue in
        selectedThemeID = AppThemeOption.custom.rawValue
        hex.wrappedValue = AppTheme.hexString(from: UIColor(newValue))
      }
    )
  }
}

private struct CustomThemeColorPickerRow: View {
  let title: String
  @Binding var selection: Color

  var body: some View {
    ColorPicker(title, selection: $selection, supportsOpacity: true)
      .foregroundStyle(AppTheme.primaryText)
  }
}
