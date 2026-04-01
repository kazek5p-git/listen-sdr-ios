import SwiftUI

struct ProfileEditorView: View {
  let title: String
  let onSave: (SDRConnectionProfile) -> Void
  let onCancel: () -> Void

  @State private var draft: SDRConnectionProfile
  @State private var showPassword = false

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

          CyclingOptionCard(
            title: L10n.text("Receiver type"),
            selectedTitle: draft.backend.displayName,
            detail: nil,
            canDecrement: SDRBackend.allCases.count > 1,
            canIncrement: SDRBackend.allCases.count > 1,
            accessibilityHint: L10n.text("directory.filters.selection_hint")
          ) {
            adjustBackend(by: -1)
          } incrementAction: {
            adjustBackend(by: 1)
          }
        }
        .appSectionStyle()

        Section(L10n.text("Server")) {
          TextField(L10n.text("Host"), text: $draft.host)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(L10n.text("Host"))
            .accessibilityHint(
              L10n.text(
                "You can paste a full receiver address here. Listen SDR will extract the host, port, path, and secure connection setting when you save."
              )
            )

          TextField(L10n.text("Port"), value: $draft.port, format: .number)
            .keyboardType(.numberPad)
            .accessibilityLabel(L10n.text("Port"))

          TextField(L10n.text("Path"), text: $draft.path)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(L10n.text("Path"))

          Toggle(L10n.text("Use TLS"), isOn: profileTLSBinding)
            .accessibilityHint(L10n.text("Enable secure HTTPS or WSS transport"))

          Text(
            L10n.text(
              "You can paste a full receiver address here. Listen SDR will extract the host, port, path, and secure connection setting when you save."
            )
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        .appSectionStyle()

        Section(L10n.text("Authentication")) {
          if draft.backend != .fmDxWebserver {
            TextField(L10n.text("Username"), text: $draft.username)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }

          passwordField

          Toggle(L10n.text("Show password"), isOn: $showPassword)
            .accessibilityHint(L10n.text("Toggle password visibility"))

          if draft.backend == .fmDxWebserver {
            Text(
              L10n.text(
                "For FM-DX Webserver enter the tune or admin password. Username is not used.",
                fallback: "For FM-DX Webserver enter the tune or admin password. Username is not used."
              )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
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
    ReceiverLinkImportDetector.normalizedManualProfile(draft)
  }

  private var profileBackendBinding: Binding<SDRBackend> {
    Binding(
      get: { draft.backend },
      set: { newBackend in
        draft.applyBackendChange(newBackend)
      }
    )
  }

  private func adjustBackend(by offset: Int) {
    let backends = SDRBackend.allCases
    guard !backends.isEmpty else { return }
    let currentIndex = backends.firstIndex(of: draft.backend) ?? 0
    let nextIndex = (currentIndex + offset + backends.count) % backends.count
    applyBackendSelection(backends[nextIndex])
  }

  private func applyBackendSelection(_ backend: SDRBackend) {
    guard backend != draft.backend else { return }
    draft.applyBackendChange(backend)
    AppAccessibilityAnnouncementCenter.postSelectionIfEnabled(backend.displayName)
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

  @ViewBuilder
  private var passwordField: some View {
    if showPassword {
      TextField(L10n.text("Password"), text: $draft.password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityHint(passwordHint)
    } else {
      SecureField(L10n.text("Password"), text: $draft.password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityHint(passwordHint)
    }
  }

  private var passwordHint: String {
    draft.backend == .fmDxWebserver
      ? L10n.text(
        "For FM-DX Webserver enter the tune or admin password. Username is not used.",
        fallback: "For FM-DX Webserver enter the tune or admin password. Username is not used."
      )
      : ""
  }
}
