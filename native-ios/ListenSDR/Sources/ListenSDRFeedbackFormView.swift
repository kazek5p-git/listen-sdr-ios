import SwiftUI

struct ListenSDRFeedbackFormView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var diagnostics: DiagnosticsStore
  @EnvironmentObject private var historyStore: ListeningHistoryStore
  @EnvironmentObject private var recordingStore: RecordingStore
  @Environment(\.dismiss) private var dismiss

  let kind: ListenSDRFeedbackKind

  @State private var senderName = ""
  @State private var message = ""
  @State private var isSending = false
  @State private var inlineError: String?
  @State private var showResultAlert = false
  @State private var resultAlertTitle = ""
  @State private var resultAlertMessage = ""

  var body: some View {
    Form {
      Section {
        TextField(L10n.text("settings.feedback.form.sender"), text: $senderName)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .submitLabel(.next)
          .accessibilityHint(L10n.text("settings.feedback.form.sender.hint"))

        messageEditor

        if let inlineError, !inlineError.isEmpty {
          Text(inlineError)
            .foregroundStyle(.red)
            .font(.footnote)
        }
      } header: {
        AppSectionHeader(title: kind.localizedTitle)
      } footer: {
        Text(L10n.text("settings.feedback.form.footer"))
      }
      .appSectionStyle()

      Section {
        FocusRetainingButton {
          submit()
        } label: {
          if isSending {
            HStack(spacing: 10) {
              ProgressView()
              Text(L10n.text("settings.feedback.form.sending"))
            }
          } else {
            Text(L10n.text("settings.feedback.form.send"))
          }
        }
        .disabled(isSending)
      }
      .appSectionStyle()
    }
    .voiceOverStable()
    .scrollContentBackground(.hidden)
    .navigationTitle(kind.localizedTitle)
    .navigationBarTitleDisplayMode(.inline)
    .appScreenBackground()
    .alert(resultAlertTitle, isPresented: $showResultAlert) {
      Button(L10n.text("OK")) {
        if resultAlertTitle == L10n.text("settings.feedback.form.sent.title") {
          dismiss()
        }
      }
    } message: {
      Text(resultAlertMessage)
    }
  }

  private var messageEditor: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(kind.localizedMessageTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      ZStack(alignment: .topLeading) {
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(kind.localizedMessageTitle)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
            .padding(.leading, 5)
            .accessibilityHidden(true)
        }

        TextEditor(text: $message)
          .frame(minHeight: 160)
          .scrollContentBackground(.hidden)
          .padding(4)
          .accessibilityLabel(kind.localizedMessageTitle)
          .accessibilityHint(L10n.text("settings.feedback.form.message.hint"))
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(AppTheme.cardFill)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(AppTheme.cardStroke, lineWidth: 1)
          )
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func submit() {
    let trimmedSender = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedSender.isEmpty else {
      inlineError = L10n.text("settings.feedback.form.error.sender_required")
      AppAccessibilityAnnouncementCenter.post(inlineError)
      return
    }

    guard !trimmedMessage.isEmpty else {
      inlineError = L10n.text("settings.feedback.form.error.message_required")
      AppAccessibilityAnnouncementCenter.post(inlineError)
      return
    }

    inlineError = nil
    isSending = true

    let context = ListenSDRFeedbackContext.current(
      profile: profileStore.selectedProfile,
      settings: radioSession.settings,
      radioSession: radioSession
    )
    let diagnosticsText = DiagnosticsExportBuilder.buildText(
      profileStore: profileStore,
      radioSession: radioSession,
      diagnostics: diagnostics,
      historyStore: historyStore,
      recordingStore: recordingStore
    )

    Task {
      do {
        try await ListenSDRFeedbackSender.send(
          kind: kind,
          senderName: trimmedSender,
          message: trimmedMessage,
          context: context,
          diagnosticsText: diagnosticsText
        )

        await MainActor.run {
          isSending = false
          senderName = ""
          message = ""
          resultAlertTitle = L10n.text("settings.feedback.form.sent.title")
          resultAlertMessage = L10n.text("settings.feedback.form.sent.body")
          showResultAlert = true
          AppAccessibilityAnnouncementCenter.post(resultAlertTitle)
        }
      } catch {
        await MainActor.run {
          isSending = false
          resultAlertTitle = L10n.text("settings.feedback.form.error.title")
          resultAlertMessage = error.localizedDescription
          showResultAlert = true
          AppAccessibilityAnnouncementCenter.post(resultAlertTitle)
        }
      }
    }
  }
}
