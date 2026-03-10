import SwiftUI
import UIKit

struct DiagnosticsView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var diagnostics: DiagnosticsStore
  @State private var showingCopyConfirmation = false

  private var audioSuggestionEntries: [DiagnosticLogEntry] {
    Array(
      diagnostics.entries
        .filter { $0.category == "Audio Suggestion" }
        .suffix(10)
        .reversed()
    )
  }

  private var generalLogEntries: [DiagnosticLogEntry] {
    Array(
      diagnostics.entries
        .filter { $0.category != "Audio Suggestion" }
        .reversed()
    )
  }

  var body: some View {
    List {
      Section("Quick Actions") {
        Button {
          guard let profile = profileStore.selectedProfile else { return }
          radioSession.reconnect(to: profile)
        } label: {
          Label("Reconnect", systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardContainer(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }
        .disabled(profileStore.selectedProfile == nil)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

        Button {
          radioSession.resetDSPSettings()
        } label: {
          Label("Reset DSP", systemImage: "slider.horizontal.3")
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardContainer(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

        Button {
          UIPasteboard.general.string = diagnostics.exportText()
          showingCopyConfirmation = true
          Diagnostics.log(category: "Diagnostics", message: "Diagnostics copied to clipboard")
        } label: {
          Label("Copy diagnostics", systemImage: "doc.on.doc")
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardContainer(padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }
        .disabled(diagnostics.entries.isEmpty)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
      }

      if !audioSuggestionEntries.isEmpty {
        Section(L10n.text("diagnostics.audio_suggestions.section")) {
          ForEach(audioSuggestionEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(timeText(entry.date))
                  .font(.caption)
                  .foregroundStyle(.secondary)

                Spacer()

                Text(entry.category)
                  .font(.caption2)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .background(AppTheme.chipFill, in: Capsule())
              }

              Text(entry.message)
                .font(.body)
                .foregroundStyle(color(for: entry.severity))
                .textSelection(.enabled)
            }
            .appCardContainer()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("diagnostics.entry_accessibility", entry.category, entry.message))
          }
        }
      }

      if let quality = radioSession.fmdxAudioQualityReport {
        Section(L10n.text("diagnostics.audio_quality.section")) {
          LabeledContent(
            L10n.text("diagnostics.audio_quality.score"),
            value: "\(quality.score)/100"
          )

          LabeledContent(
            L10n.text("diagnostics.audio_quality.level"),
            value: quality.level.localizedTitle
          )

          Text(quality.localizedSummary)
            .font(.footnote)
            .foregroundStyle(.secondary)

          LabeledContent(
            L10n.text("diagnostics.audio_quality.queue"),
            value: "\(String(format: "%.2f", quality.queuedDurationSeconds)) s"
          )

          LabeledContent(
            L10n.text("diagnostics.audio_quality.buffers"),
            value: "\(quality.queuedBufferCount)"
          )

          LabeledContent(
            L10n.text("diagnostics.audio_quality.output_gap"),
            value: "\(String(format: "%.2f", quality.outputGapSeconds)) s"
          )

          if let trimAge = quality.latencyTrimAgeSeconds {
            LabeledContent(
              L10n.text("diagnostics.audio_quality.last_trim"),
              value: "\(String(format: "%.1f", trimAge)) s"
            )
          } else {
            LabeledContent(
              L10n.text("diagnostics.audio_quality.last_trim"),
              value: L10n.text("diagnostics.audio_quality.no_trim")
            )
          }

          if let signal = quality.signalDBf {
            LabeledContent(
              L10n.text("diagnostics.audio_quality.signal"),
              value: "\(String(format: "%.1f", signal)) dBf"
            )
          }
        }
      }

      Section("Logs") {
        if generalLogEntries.isEmpty {
          UnavailableContentView(
            title: L10n.text("No Diagnostics Yet"),
            systemImage: "doc.text.magnifyingglass",
            description: L10n.text("Connection logs and errors will appear here.")
          )
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
        } else {
          ForEach(generalLogEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(timeText(entry.date))
                  .font(.caption)
                  .foregroundStyle(.secondary)

                Spacer()

                Text(entry.category)
                  .font(.caption2)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .background(AppTheme.chipFill, in: Capsule())
              }

              Text(entry.message)
                .font(.body)
                .foregroundStyle(color(for: entry.severity))
                .textSelection(.enabled)
            }
            .appCardContainer()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("diagnostics.entry_accessibility", entry.category, entry.message))
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("Diagnostics")
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Clear") {
          diagnostics.clear()
          Diagnostics.log(category: "Diagnostics", message: "Diagnostics log cleared")
        }
        .disabled(diagnostics.entries.isEmpty)
      }
    }
    .alert("Copied", isPresented: $showingCopyConfirmation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Diagnostics were copied to the clipboard.")
    }
    .appScreenBackground()
  }

  private func timeText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }

  private func color(for severity: DiagnosticSeverity) -> Color {
    switch severity {
    case .info:
      return .primary
    case .warning:
      return .orange
    case .error:
      return .red
    }
  }
}
