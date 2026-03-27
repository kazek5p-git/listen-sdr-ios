import SwiftUI

struct AppTutorialView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var settingsController: SettingsViewController

  let isPresentedOnLaunch: Bool

  var body: some View {
    List {
      introSection
      quickStartSection
      receiverSection
      bookmarksSection
      accessibilitySection
      recordingSection
      launchBehaviorSection
      doneSection
    }
    .voiceOverStable()
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(
      L10n.text("tutorial.navigation_title", fallback: "Tutorial")
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if isPresentedOnLaunch {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("tutorial.close", fallback: "Close")) {
            dismiss()
          }
        }
      }
    }
    .appScreenBackground()
  }

  private var introSection: some View {
    Section {
      Text(
        L10n.text(
          "tutorial.intro.body",
          fallback: "Learn how Listen SDR works before you start tuning."
        )
      )
      .font(.body)
      .foregroundStyle(.secondary)
    } header: {
      AppSectionHeader(
        title: L10n.text("tutorial.intro.title", fallback: "Tutorial")
      )
    }
    .appSectionStyle()
  }

  private var quickStartSection: some View {
    tutorialSection(
      titleKey: "tutorial.quick_start.title",
      titleFallback: "Quick start",
      bodyKey: "tutorial.quick_start.body",
      bodyFallback: "Open Radios, choose a saved receiver or import a link, then connect from Receiver."
    )
  }

  private var receiverSection: some View {
    tutorialSection(
      titleKey: "tutorial.receiver.title",
      titleFallback: "Receiver tab",
      bodyKey: "tutorial.receiver.body",
      bodyFallback: "Use the frequency control, tune-step control, and backend sections to listen and fine-tune the receiver."
    )
  }

  private var bookmarksSection: some View {
    tutorialSection(
      titleKey: "tutorial.bookmarks.title",
      titleFallback: "Bookmarks and presets",
      bodyKey: "tutorial.bookmarks.body",
      bodyFallback: "If a receiver exposes bookmarks or presets, you can tune them from the app. On iPhone, VoiceOver also lets you move through them directly from the rotor."
    )
  }

  private var accessibilitySection: some View {
    tutorialSection(
      titleKey: "tutorial.accessibility.title",
      titleFallback: "Accessibility",
      bodyKey: "tutorial.accessibility.body",
      bodyFallback: "Selection confirmations, feedback sounds, Magic Tap, grouped controls, and VoiceOver-friendly navigation are available in Accessibility settings."
    )
  }

  private var recordingSection: some View {
    tutorialSection(
      titleKey: "tutorial.recording.title",
      titleFallback: "Recording and playback",
      bodyKey: "tutorial.recording.body",
      bodyFallback: "You can record locally, review saved recordings, and route audio to AirPlay or other system audio outputs."
    )
  }

  private var launchBehaviorSection: some View {
    Section {
      Toggle(
        L10n.text(
          "tutorial.show_on_launch.title",
          fallback: "Show this tutorial on app start"
        ),
        isOn: Binding(
          get: { settingsController.state.showTutorialOnLaunchEnabled },
          set: { settingsController.setShowTutorialOnLaunchEnabled($0) }
        )
      )
      .accessibilityHint(
        L10n.text(
          "tutorial.show_on_launch.hint",
          fallback: "Turn this off if you do not want the tutorial to open automatically next time."
        )
      )
    } header: {
      AppSectionHeader(
        title: L10n.text("tutorial.show_on_launch.section", fallback: "Startup")
      )
    }
    .appSectionStyle()
  }

  private var doneSection: some View {
    Section {
      FocusRetainingButton {
        dismiss()
      } label: {
        Text(
          L10n.text(
            "tutorial.done",
            fallback: "Start using Listen SDR"
          )
        )
      }
    }
    .appSectionStyle()
  }

  @ViewBuilder
  private func tutorialSection(
    titleKey: String,
    titleFallback: String,
    bodyKey: String,
    bodyFallback: String
  ) -> some View {
    Section {
      Text(L10n.text(bodyKey, fallback: bodyFallback))
        .font(.body)
    } header: {
      AppSectionHeader(title: L10n.text(titleKey, fallback: titleFallback))
    }
    .appSectionStyle()
  }
}
