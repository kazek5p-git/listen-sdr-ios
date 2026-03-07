import SwiftUI
import UIKit

struct DiagnosticsView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var diagnostics: DiagnosticsStore
  @State private var showingCopyConfirmation = false

  var body: some View {
    NavigationStack {
      List {
        Section("Quick Actions") {
          Button {
            guard let profile = profileStore.selectedProfile else { return }
            radioSession.reconnect(to: profile)
          } label: {
            Label("Reconnect", systemImage: "arrow.clockwise")
          }
          .disabled(profileStore.selectedProfile == nil)

          Button {
            radioSession.resetDSPSettings()
          } label: {
            Label("Reset DSP", systemImage: "slider.horizontal.3")
          }

          Button {
            UIPasteboard.general.string = diagnostics.exportText()
            showingCopyConfirmation = true
            Diagnostics.log(category: "Diagnostics", message: "Diagnostics copied to clipboard")
          } label: {
            Label("Copy diagnostics", systemImage: "doc.on.doc")
          }
          .disabled(diagnostics.entries.isEmpty)
        }

        Section("Logs") {
          if diagnostics.entries.isEmpty {
            UnavailableContentView(
              title: L10n.text("No Diagnostics Yet"),
              systemImage: "doc.text.magnifyingglass",
              description: L10n.text("Connection logs and errors will appear here.")
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
          } else {
            ForEach(Array(diagnostics.entries.reversed())) { entry in
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
                    .background(.thinMaterial, in: Capsule())
                }

              Text(entry.message)
                  .font(.body)
                  .foregroundStyle(color(for: entry.severity))
                  .textSelection(.enabled)
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel(L10n.text("diagnostics.entry_accessibility", entry.category, entry.message))
            }
          }
        }
      }
      .listStyle(.insetGrouped)
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
    }
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
