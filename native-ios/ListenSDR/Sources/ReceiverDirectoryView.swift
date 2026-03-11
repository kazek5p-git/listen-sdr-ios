import SwiftUI

struct ReceiverDirectoryView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var favoritesStore: FavoritesStore
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = ReceiverDirectoryViewModel()

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("Backend source", selection: $viewModel.selectedBackend) {
            ForEach(viewModel.supportedBackends) { backend in
              Text(backend.displayName).tag(backend)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel(L10n.text("Receiver backend list"))
        } header: {
          AppSectionHeader(title: "Backend")
        }
        .appSectionStyle()

        Section {
          NavigationLink {
            SelectionListView(
              title: L10n.text("directory.filters.status"),
              options: ReceiverDirectoryStatusFilter.allCases.map {
                SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
              },
              selectedID: viewModel.statusFilter.rawValue
            ) { value in
              if let filter = ReceiverDirectoryStatusFilter(rawValue: value) {
                viewModel.statusFilter = filter
              }
            }
          } label: {
            LabeledContent(
              L10n.text("directory.filters.status"),
              value: viewModel.statusFilter.displayName
            )
          }

          NavigationLink {
            SelectionListView(
              title: L10n.text("directory.filters.sort"),
              options: ReceiverDirectorySortOption.allCases.map {
                SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
              },
              selectedID: viewModel.sortOption.rawValue
            ) { value in
              if let sortOption = ReceiverDirectorySortOption(rawValue: value) {
                viewModel.sortOption = sortOption
              }
            }
          } label: {
            LabeledContent(
              L10n.text("directory.filters.sort"),
              value: viewModel.sortOption.displayName
            )
          }

          if !viewModel.availableCountries.isEmpty {
            NavigationLink {
              SelectionListView(
                title: L10n.text("directory.filters.country"),
                options: [SelectionListOption(id: "", title: L10n.text("directory.filter.country.all"), detail: nil)]
                  + viewModel.availableCountries.map { country in
                    SelectionListOption(id: country, title: country, detail: nil)
                  },
                selectedID: viewModel.selectedCountry
              ) { value in
                viewModel.selectedCountry = value
              }
            } label: {
              LabeledContent(
                L10n.text("directory.filters.country"),
                value: viewModel.selectedCountry.isEmpty
                  ? L10n.text("directory.filter.country.all")
                  : viewModel.selectedCountry
              )
            }
          }

          Toggle(
            L10n.text("directory.filters.favorites_only"),
            isOn: $viewModel.favoritesOnly
          )
        } header: {
          AppSectionHeader(title: L10n.text("directory.filters.section"))
        }
        .appSectionStyle()

        Section {
          if let lastRefreshDate = viewModel.lastRefreshDate {
            Text(
              L10n.text(
                "directory.last_update",
                lastRefreshDate.formatted(date: .abbreviated, time: .shortened)
              )
            )
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
              .accessibilityLabel(L10n.text("Directory error"))
          }

          if let cacheStatusText = viewModel.cacheStatusText {
            Text(cacheStatusText)
              .foregroundStyle(.secondary)
              .font(.footnote)
          }

          if viewModel.isProbingStatus {
            HStack(spacing: 8) {
              ProgressView()
              Text("Checking receiver availability...")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel(L10n.text("Checking receiver availability"))
          }
        } header: {
          AppSectionHeader(title: "Status")
        } footer: {
          Text(viewModel.sourceSummaryText)
        }
        .appSectionStyle()

        Section {
          let filteredEntries = viewModel.filteredEntries(favoriteReceiverIDs: favoritesStore.favoriteReceiverIDs)

          if filteredEntries.isEmpty {
            if viewModel.isLoading {
              ProgressView("Refreshing directory...")
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
              Text("No receivers found for current filter.")
                .foregroundStyle(.secondary)
            }
          } else {
            ForEach(filteredEntries) { entry in
              directoryRow(for: entry)
            }
          }
        } header: {
          AppSectionHeader(title: "Receivers")
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
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
              .accessibilityLabel(L10n.text("Refreshing receiver status"))
          } else {
            Button {
              Task {
                await viewModel.refresh(force: true)
              }
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(L10n.text("Refresh receiver directory"))
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
        viewModel.selectedCountry = ""
        viewModel.scheduleStatusProbeForSelectedBackend(force: false)
      }
      .appScreenBackground()
    }
  }

  @ViewBuilder
  private func directoryRow(for entry: ReceiverDirectoryEntry) -> some View {
    let candidateProfile = entry.makeProfile()
    let existingProfile = profileStore.matchingProfile(for: candidateProfile)
    let isSelected = existingProfile?.id == profileStore.selectedProfileID
    let isFavorite = favoritesStore.isFavoriteReceiver(entry)

    Button {
      let storedProfile = profileStore.upsertImportedProfile(candidateProfile)
      profileStore.updateSelection(storedProfile.id)
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: backendIconName(for: entry.backend))
          .font(.headline)
          .foregroundStyle(backendAccent(for: entry.backend))
          .frame(width: 34, height: 34)
          .background(
            backendAccent(for: entry.backend).opacity(0.16),
            in: Circle()
          )
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          Text(entry.name)
            .font(.headline)

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
          if isFavorite {
            Image(systemName: "star.fill")
              .imageScale(.medium)
              .foregroundStyle(.yellow)
          }

          statusBadge(for: entry.status)

          if existingProfile == nil {
            Image(systemName: "plus.circle.fill")
              .imageScale(.large)
              .foregroundStyle(.tint)
          } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .imageScale(.large)
              .foregroundStyle(.green)
          } else {
            Image(systemName: "checkmark.circle")
              .imageScale(.large)
              .foregroundStyle(.secondary)
          }
        }
      }
      .appCardContainer()
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      Button {
        favoritesStore.toggleReceiver(entry)
      } label: {
        Label(
          isFavorite ? L10n.text("favorites.receiver.remove") : L10n.text("favorites.receiver.add"),
          systemImage: isFavorite ? "star.slash" : "star"
        )
      }
      .tint(.yellow)
    }
    .accessibilityAction(
      named: Text(
        isFavorite ? L10n.text("favorites.receiver.remove") : L10n.text("favorites.receiver.add")
      )
    ) {
      favoritesStore.toggleReceiver(entry)
    }
    .accessibilityLabel(entry.name)
    .accessibilityValue(
      isSelected
        ? L10n.text("common.selected")
        : (existingProfile == nil ? L10n.text("common.not_added") : L10n.text("common.added"))
    )
    .accessibilityHint(L10n.text("Double tap to add or select this receiver profile"))
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

  private func backendIconName(for backend: SDRBackend) -> String {
    switch backend {
    case .kiwiSDR:
      return "dot.radiowaves.left.and.right"
    case .openWebRX:
      return "antenna.radiowaves.left.and.right"
    case .fmDxWebserver:
      return "dot.scope"
    }
  }

  private func backendAccent(for backend: SDRBackend) -> Color {
    switch backend {
    case .kiwiSDR:
      return AppTheme.tint
    case .openWebRX:
      return AppTheme.accent
    case .fmDxWebserver:
      return .orange
    }
  }
}
