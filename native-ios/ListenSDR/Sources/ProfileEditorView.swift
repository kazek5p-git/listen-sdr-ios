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
        Section("General") {
          TextField("Profile name", text: $draft.name)
            .accessibilityLabel("Profile name")
            .accessibilityHint("Name shown in your radio list")

          Picker("Backend", selection: $draft.backend) {
            ForEach(SDRBackend.allCases) { backend in
              Text(backend.displayName).tag(backend)
            }
          }
          .accessibilityLabel("Receiver backend")
          .onChange(of: draft.backend) { newBackend in
            draft.port = newBackend.defaultPort
          }
        }

        Section("Server") {
          TextField("Host", text: $draft.host)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel("Host")

          TextField("Port", value: $draft.port, format: .number)
            .keyboardType(.numberPad)
            .accessibilityLabel("Port")

          TextField("Path", text: $draft.path)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel("Path")

          Toggle("Use TLS", isOn: $draft.useTLS)
            .accessibilityHint("Enable secure HTTPS or WSS transport")
        }

        Section("Authentication") {
          TextField("Username", text: $draft.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

          SecureField("Password", text: $draft.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(normalizedDraft)
          }
          .disabled(!isValid)
        }
      }
    }
  }

  private var normalizedDraft: SDRConnectionProfile {
    var profile = draft
    profile.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.path = draft.path.trimmingCharacters(in: .whitespacesAndNewlines)
    return profile
  }

  private var isValid: Bool {
    !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      (1...65535).contains(draft.port)
  }
}
