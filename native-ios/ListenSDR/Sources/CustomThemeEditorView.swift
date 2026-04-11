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
  @State private var importPayload = ""
  @State private var isImportSheetPresented = false
  @State private var statusAlert: CustomThemeStatusAlert?

  var body: some View {
    List {
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
        FocusRetainingButton {
          copyCustomThemeToClipboard()
        } label: {
          Text(
            L10n.text(
              "settings.appearance.custom.export.copy",
              fallback: "Copy custom skin JSON"
            )
          )
        }

        if let exportPayload = try? AppTheme.exportCustomThemeJSONString() {
          ShareLink(
            item: exportPayload,
            preview: SharePreview(
              L10n.text(
                "settings.appearance.custom.export.share_title",
                fallback: "Listen SDR custom skin"
              )
            )
          ) {
            Text(
              L10n.text(
                "settings.appearance.custom.export.share",
                fallback: "Share custom skin JSON"
              )
            )
          }
        }

        FocusRetainingButton {
          importCustomThemeFromClipboard()
        } label: {
          Text(
            L10n.text(
              "settings.appearance.custom.import.clipboard",
              fallback: "Import custom skin from clipboard"
            )
          )
        }

        FocusRetainingButton {
          importPayload = UIPasteboard.general.string ?? ""
          isImportSheetPresented = true
        } label: {
          Text(
            L10n.text(
              "settings.appearance.custom.import.manual",
              fallback: "Paste custom skin JSON"
            )
          )
        }

        FocusRetainingButton({
          AppTheme.resetCustomTheme()
          selectedThemeID = AppThemeOption.custom.rawValue
          syncVisibleHexFields()
        }, role: .destructive) {
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
    .listStyle(.insetGrouped)
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
    .sheet(isPresented: $isImportSheetPresented) {
      NavigationStack {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            L10n.text(
              "settings.appearance.custom.import.description",
              fallback: "Paste a custom skin JSON export here. Importing replaces your current custom colors."
            )
          )
          .font(.footnote)
          .foregroundStyle(AppTheme.secondaryText)

          TextEditor(text: $importPayload)
            .frame(minHeight: 220)
            .padding(8)
            .background(AppTheme.cardFill)
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
            }

          HStack(spacing: 12) {
            FocusRetainingButton {
              importPayload = UIPasteboard.general.string ?? ""
            } label: {
              Text(
                L10n.text(
                  "settings.appearance.custom.import.load_clipboard",
                  fallback: "Load clipboard"
                )
              )
            }

            FocusRetainingButton {
              applyImportedPayload(importPayload)
            } label: {
              Text(
                L10n.text(
                  "settings.appearance.custom.import.apply",
                  fallback: "Import custom skin"
                )
              )
            }
          }

          Spacer()
        }
        .padding()
        .navigationTitle(
          L10n.text(
            "settings.appearance.custom.import.sheet_title",
            fallback: "Import custom skin"
          )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(L10n.text("Cancel")) {
              isImportSheetPresented = false
            }
          }
        }
        .appScreenBackground()
      }
    }
    .alert(
      statusAlert?.title ?? "",
      isPresented: Binding(
        get: { statusAlert != nil },
        set: { if !$0 { statusAlert = nil } }
      )
    ) {
      Button(L10n.text("OK")) {
        statusAlert = nil
      }
    } message: {
      Text(statusAlert?.message ?? "")
    }
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

  private func syncVisibleHexFields() {
    backgroundTopHex = AppTheme.customColorsSnapshot.backgroundTop
    backgroundBottomHex = AppTheme.customColorsSnapshot.backgroundBottom
    cardFillHex = AppTheme.customColorsSnapshot.cardFill
    cardStrokeHex = AppTheme.customColorsSnapshot.cardStroke
    primaryTextHex = AppTheme.customColorsSnapshot.primaryText
    secondaryTextHex = AppTheme.customColorsSnapshot.secondaryText
    tintHex = AppTheme.customColorsSnapshot.tint
    accentHex = AppTheme.customColorsSnapshot.accent
  }

  private func copyCustomThemeToClipboard() {
    do {
      UIPasteboard.general.string = try AppTheme.exportCustomThemeJSONString()
      statusAlert = CustomThemeStatusAlert(
        title: L10n.text(
          "settings.appearance.custom.export.success.title",
          fallback: "Custom skin copied"
        ),
        message: L10n.text(
          "settings.appearance.custom.export.success.body",
          fallback: "The custom skin JSON was copied to the clipboard."
        )
      )
    } catch {
      statusAlert = CustomThemeStatusAlert(
        title: L10n.text(
          "settings.appearance.custom.export.failure.title",
          fallback: "Unable to export custom skin"
        ),
        message: error.localizedDescription
      )
    }
  }

  private func importCustomThemeFromClipboard() {
    applyImportedPayload(UIPasteboard.general.string ?? "")
  }

  private func applyImportedPayload(_ rawValue: String) {
    do {
      try AppTheme.importCustomTheme(from: rawValue)
      selectedThemeID = AppThemeOption.custom.rawValue
      syncVisibleHexFields()
      isImportSheetPresented = false
      statusAlert = CustomThemeStatusAlert(
        title: L10n.text(
          "settings.appearance.custom.import.success.title",
          fallback: "Custom skin imported"
        ),
        message: L10n.text(
          "settings.appearance.custom.import.success.body",
          fallback: "The imported custom skin is now active."
        )
      )
    } catch {
      statusAlert = CustomThemeStatusAlert(
        title: L10n.text(
          "settings.appearance.custom.import.failure.title",
          fallback: "Unable to import custom skin"
        ),
        message: error.localizedDescription
      )
    }
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

private struct CustomThemeStatusAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
