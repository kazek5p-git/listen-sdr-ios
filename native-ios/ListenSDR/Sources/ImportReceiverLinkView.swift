import SwiftUI

struct ImportReceiverLinkView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel

  @State private var rawURL = ""
  @State private var isAnalyzing = false
  @State private var errorMessage: String?
  @State private var importedProfile: SDRConnectionProfile?
  @State private var detectionSummary: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(L10n.text("receiver.import.url"), text: $rawURL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .accessibilityHint(L10n.text("receiver.import.url.hint"))

          FocusRetainingButton {
            Task {
              await analyzeLink()
            }
          } label: {
            if isAnalyzing {
              HStack(spacing: 8) {
                ProgressView()
                Text(L10n.text("receiver.import.analyzing"))
              }
              .frame(maxWidth: .infinity)
            } else {
              Text(L10n.text("receiver.import.analyze"))
                .frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isAnalyzing || rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          if let errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        } header: {
          AppSectionHeader(title: L10n.text("receiver.import.section"))
        }
        .appSectionStyle()

        if let importedProfile {
          Section {
            TextField(L10n.text("Profile name"), text: profileNameBinding)

            Picker(L10n.text("Backend"), selection: profileBackendBinding) {
              ForEach(SDRBackend.allCases) { backend in
                Text(backend.displayName).tag(backend)
              }
            }
            .pickerStyle(.segmented)

            LabeledContent(
              L10n.text("receiver.import.detected_endpoint"),
              value: importedProfile.endpointDescription
            )

            if let detectionSummary, !detectionSummary.isEmpty {
              Text(detectionSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            FocusRetainingButton {
              importAndConnect()
            } label: {
              Text(L10n.text("receiver.import.connect"))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          } header: {
            AppSectionHeader(title: L10n.text("receiver.import.preview.section"))
          }
          .appSectionStyle()
        }
      }
      .voiceOverStable()
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Import from link"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Close")) {
            dismiss()
          }
        }
      }
      .appScreenBackground()
    }
  }

  private var profileNameBinding: Binding<String> {
    Binding(
      get: { importedProfile?.name ?? "" },
      set: { importedProfile?.name = $0 }
    )
  }

  private var profileBackendBinding: Binding<SDRBackend> {
    Binding(
      get: { importedProfile?.backend ?? .kiwiSDR },
      set: { newBackend in
        guard importedProfile != nil else { return }
        importedProfile?.backend = newBackend
        importedProfile?.path = ReceiverLinkImportDetector.normalizedProfilePath(
          for: newBackend,
          rawPath: importedProfile?.path ?? "/"
        )
      }
    )
  }

  private func analyzeLink() async {
    let input = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return }

    isAnalyzing = true
    errorMessage = nil

    do {
      let candidate = try await ReceiverLinkImportDetector.analyze(input)
      importedProfile = candidate.profile
      detectionSummary = candidate.detectionSummary
    } catch {
      importedProfile = nil
      detectionSummary = nil
      errorMessage = error.localizedDescription
    }

    isAnalyzing = false
  }

  private func importAndConnect() {
    guard let importedProfile else { return }
    let storedProfile = profileStore.upsertImportedProfile(importedProfile)
    profileStore.updateSelection(storedProfile.id)
    navigationState.selectedTab = .receiver
    radioSession.connect(to: storedProfile)
    dismiss()
  }
}
