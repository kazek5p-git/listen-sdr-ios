import SwiftUI

struct ProfileEditorView: View {
  let title: String
  let onSave: (SDRConnectionProfile) -> Void
  let onCancel: () -> Void

  @State private var draft: SDRConnectionProfile

  init(
    title: String,
    initialProfile: SDRConnectionProfile,
    onSave: @escaping (SDRConnectionProfile) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.onSave = onSave
    self.onCancel = onCancel
    _draft = State(initialValue: initialProfile)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("General")) {
          TextField(L10n.text("Profile name"), text: $draft.name)
            .accessibilityLabel(L10n.text("Profile name"))
            .accessibilityHint(L10n.text("Name shown in your radio list"))

          Picker(L10n.text("Backend"), selection: profileBackendBinding) {
            ForEach(SDRBackend.allCases) { backend in
              Text(backend.displayName).tag(backend)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel(L10n.text("Receiver backend"))
        }
        .appSectionStyle()

        Section(L10n.text("Server")) {
          TextField(L10n.text("Host"), text: $draft.host)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(L10n.text("Host"))

          TextField(L10n.text("Port"), value: $draft.port, format: .number)
            .keyboardType(.numberPad)
            .accessibilityLabel(L10n.text("Port"))

          TextField(L10n.text("Path"), text: $draft.path)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(L10n.text("Path"))

          Toggle(L10n.text("Use TLS"), isOn: profileTLSBinding)
            .accessibilityHint(L10n.text("Enable secure HTTPS or WSS transport"))
        }
        .appSectionStyle()

        Section(L10n.text("Authentication")) {
          TextField(L10n.text("Username"), text: $draft.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

          SecureField(L10n.text("Password"), text: $draft.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .appSectionStyle()
      }
      .scrollContentBackground(.hidden)
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Cancel"), action: onCancel)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Save")) {
            onSave(normalizedDraft)
          }
          .disabled(!isValid)
        }
      }
      .appScreenBackground()
    }
  }

  private var normalizedDraft: SDRConnectionProfile {
    var profile = draft
    profile.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.path = draft.path.trimmingCharacters(in: .whitespacesAndNewlines)
    return profile
  }

  private var profileBackendBinding: Binding<SDRBackend> {
    Binding(
      get: { draft.backend },
      set: { newBackend in
        draft.applyBackendChange(newBackend)
      }
    )
  }

  private var profileTLSBinding: Binding<Bool> {
    Binding(
      get: { draft.useTLS },
      set: { newValue in
        draft.applyTLSChange(newValue)
        AppInteractionFeedbackCenter.playIfEnabled(newValue ? .enabled : .disabled)
      }
    )
  }

  private var isValid: Bool {
    !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      (1...65535).contains(draft.port)
  }
}
