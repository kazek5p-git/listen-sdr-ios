import SwiftUI

struct ReceiverDirectoryView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = ReceiverDirectoryViewModel()

  var body: some View {
    NavigationStack {
      List {
        Section("Backend") {
          Picker("Backend source", selection: $viewModel.selectedBackend) {
            ForEach(viewModel.supportedBackends) { backend in
              Text(backend.displayName).tag(backend)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel("Receiver backend list")
        }

        Section {
          if let lastRefreshDate = viewModel.lastRefreshDate {
            Text("Last update: \(lastRefreshDate.formatted(date: .abbreviated, time: .shortened))")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            Text("No directory data cached yet.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .foregroundStyle(.orange)
              .font(.footnote)
              .accessibilityLabel("Directory error")
          }

          if viewModel.isProbingStatus {
            HStack(spacing: 8) {
              ProgressView()
              Text("Checking receiver availability...")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Checking receiver availability")
          }
        } header: {
          Text("Status")
        } footer: {
          Text("Auto-updated from FMDX.org and Receiverbook.de.")
        }

        Section("Receivers") {
          if viewModel.filteredEntries.isEmpty {
            if viewModel.isLoading {
              ProgressView("Refreshing directory...")
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
              Text("No receivers found for current filter.")
                .foregroundStyle(.secondary)
            }
          } else {
            ForEach(viewModel.filteredEntries) { entry in
              directoryRow(for: entry)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Receiver Directory")
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Close") {
            dismiss()
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          if viewModel.isLoading || viewModel.isProbingStatus {
            ProgressView()
              .accessibilityLabel("Refreshing receiver status")
          } else {
            Button {
              Task {
                await viewModel.refresh(force: true)
              }
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh receiver directory")
          }
        }
      }
      .searchable(
        text: $viewModel.searchText,
        prompt: "Search by name, location or host"
      )
      .refreshable {
        await viewModel.refresh(force: true)
      }
      .task {
        viewModel.start()
        viewModel.scheduleStatusProbeForSelectedBackend(force: false)
      }
      .onDisappear {
        viewModel.stop()
      }
      .onChange(of: viewModel.selectedBackend) { _ in
        viewModel.scheduleStatusProbeForSelectedBackend(force: false)
      }
    }
  }

  @ViewBuilder
  private func directoryRow(for entry: ReceiverDirectoryEntry) -> some View {
    let alreadyAdded = profileStore.hasMatchingProfile(entry.makeProfile())

    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.name)
          .font(.headline)
          .accessibilityLabel(entry.name)

        Text(entry.endpointDescription)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)

        Text(entry.detailText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 8) {
        statusBadge(for: entry.status)

        Button {
          let profile = entry.makeProfile()
          let storedProfile = profileStore.upsertImportedProfile(profile)
          profileStore.updateSelection(storedProfile.id)
        } label: {
          Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .accessibilityLabel(alreadyAdded ? "Already added" : "Add profile")
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func statusBadge(for status: ReceiverDirectoryStatus) -> some View {
    Text(status.displayName)
      .font(.caption2)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(statusBackground(for: status), in: Capsule())
      .foregroundStyle(statusForeground(for: status))
  }

  private func statusForeground(for status: ReceiverDirectoryStatus) -> Color {
    switch status {
    case .available:
      return .green
    case .limited:
      return .orange
    case .unreachable:
      return .red
    case .unknown:
      return .secondary
    }
  }

  private func statusBackground(for status: ReceiverDirectoryStatus) -> Color {
    switch status {
    case .available:
      return Color.green.opacity(0.15)
    case .limited:
      return Color.orange.opacity(0.15)
    case .unreachable:
      return Color.red.opacity(0.15)
    case .unknown:
      return Color.secondary.opacity(0.12)
    }
  }
}
