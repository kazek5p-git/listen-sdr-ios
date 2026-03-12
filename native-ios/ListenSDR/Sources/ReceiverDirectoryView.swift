import SwiftUI

struct ReceiverDirectoryView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var favoritesStore: FavoritesStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @StateObject private var viewModel = ReceiverDirectoryViewModel()

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker(L10n.text("Backend source"), selection: $viewModel.selectedBackend) {
            ForEach(viewModel.supportedBackends) { backend in
              Text(backend.displayName).tag(backend)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel(L10n.text("Receiver backend list"))
        } header: {
          AppSectionHeader(title: L10n.text("Backend"))
        }
        .appSectionStyle()

        Section {
          CyclingOptionCard(
            title: L10n.text("directory.filters.status"),
            selectedTitle: viewModel.statusFilter.displayName,
            detail: optionPositionDetail(currentIndex: statusFilterOptions.firstIndex(where: { $0.rawValue == viewModel.statusFilter.rawValue }) ?? 0, totalCount: statusFilterOptions.count),
            canDecrement: canCycle(currentIndex: statusFilterOptions.firstIndex(where: { $0.rawValue == viewModel.statusFilter.rawValue }) ?? 0, totalCount: statusFilterOptions.count, offset: -1),
            canIncrement: canCycle(currentIndex: statusFilterOptions.firstIndex(where: { $0.rawValue == viewModel.statusFilter.rawValue }) ?? 0, totalCount: statusFilterOptions.count, offset: 1),
            accessibilityHint: L10n.text("directory.filters.cycler_hint")
          ) {
            cycleStatusFilter(by: -1)
          } incrementAction: {
            cycleStatusFilter(by: 1)
          }

          CyclingOptionCard(
            title: L10n.text("directory.filters.sort"),
            selectedTitle: viewModel.sortOption.displayName,
            detail: optionPositionDetail(currentIndex: sortOptions.firstIndex(where: { $0.rawValue == viewModel.sortOption.rawValue }) ?? 0, totalCount: sortOptions.count),
            canDecrement: canCycle(currentIndex: sortOptions.firstIndex(where: { $0.rawValue == viewModel.sortOption.rawValue }) ?? 0, totalCount: sortOptions.count, offset: -1),
            canIncrement: canCycle(currentIndex: sortOptions.firstIndex(where: { $0.rawValue == viewModel.sortOption.rawValue }) ?? 0, totalCount: sortOptions.count, offset: 1),
            accessibilityHint: L10n.text("directory.filters.cycler_hint")
          ) {
            cycleSortOption(by: -1)
          } incrementAction: {
            cycleSortOption(by: 1)
          }

          if !viewModel.availableCountries.isEmpty {
            CyclingOptionCard(
              title: L10n.text("directory.filters.country"),
              selectedTitle: selectedCountryTitle,
              detail: optionPositionDetail(currentIndex: countryOptions.firstIndex(of: viewModel.selectedCountry) ?? 0, totalCount: countryOptions.count),
              canDecrement: canCycle(currentIndex: countryOptions.firstIndex(of: viewModel.selectedCountry) ?? 0, totalCount: countryOptions.count, offset: -1),
              canIncrement: canCycle(currentIndex: countryOptions.firstIndex(of: viewModel.selectedCountry) ?? 0, totalCount: countryOptions.count, offset: 1),
              accessibilityHint: L10n.text("directory.filters.cycler_hint")
            ) {
              cycleCountry(by: -1)
            } incrementAction: {
              cycleCountry(by: 1)
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
            Text(L10n.text("No directory data cached yet."))
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
              Text(L10n.text("Checking receiver availability..."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel(L10n.text("Checking receiver availability"))
          }
        } header: {
          AppSectionHeader(title: L10n.text("Status"))
        } footer: {
          Text(viewModel.sourceSummaryText)
        }
        .appSectionStyle()

        Section {
          let filteredEntries = viewModel.filteredEntries(favoriteReceiverIDs: favoritesStore.favoriteReceiverIDs)

          if filteredEntries.isEmpty {
            if viewModel.isLoading {
              ProgressView(L10n.text("Refreshing directory..."))
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
              Text(L10n.text("No receivers found for current filter."))
                .foregroundStyle(.secondary)
            }
          } else {
            ForEach(filteredEntries) { entry in
              directoryRow(for: entry)
            }
          }
        } header: {
          AppSectionHeader(title: L10n.text("Receivers"))
        }
      }
      .voiceOverStable()
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Receiver Directory"))
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(L10n.text("Close")) {
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
        prompt: L10n.text("Search by name, location or host")
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
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        openReceiverWebsite(for: entry)
      } label: {
        Label(
          L10n.text("directory.receiver.open_website"),
          systemImage: "globe"
        )
      }
      .tint(.blue)
    }
    .accessibilityAction(named: Text(L10n.text("directory.receiver.open_website"))) {
      openReceiverWebsite(for: entry)
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

  private var statusFilterOptions: [ReceiverDirectoryStatusFilter] {
    ReceiverDirectoryStatusFilter.allCases
  }

  private var sortOptions: [ReceiverDirectorySortOption] {
    ReceiverDirectorySortOption.allCases
  }

  private var countryOptions: [String] {
    [""] + viewModel.availableCountries
  }

  private var selectedCountryTitle: String {
    viewModel.selectedCountry.isEmpty
      ? L10n.text("directory.filter.country.all")
      : viewModel.selectedCountry
  }

  private func optionPositionDetail(currentIndex: Int, totalCount: Int) -> String? {
    guard totalCount > 1 else { return nil }
    return L10n.text("directory.filters.option_position", currentIndex + 1, totalCount)
  }

  private func canCycle(currentIndex: Int, totalCount: Int, offset: Int) -> Bool {
    guard totalCount > 1 else { return false }
    let nextIndex = currentIndex + offset
    return (0..<totalCount).contains(nextIndex)
  }

  private func cycleStatusFilter(by offset: Int) {
    guard
      let currentIndex = statusFilterOptions.firstIndex(where: { $0.rawValue == viewModel.statusFilter.rawValue }),
      canCycle(currentIndex: currentIndex, totalCount: statusFilterOptions.count, offset: offset)
    else {
      return
    }
    viewModel.statusFilter = statusFilterOptions[currentIndex + offset]
  }

  private func cycleSortOption(by offset: Int) {
    guard
      let currentIndex = sortOptions.firstIndex(where: { $0.rawValue == viewModel.sortOption.rawValue }),
      canCycle(currentIndex: currentIndex, totalCount: sortOptions.count, offset: offset)
    else {
      return
    }
    viewModel.sortOption = sortOptions[currentIndex + offset]
  }

  private func cycleCountry(by offset: Int) {
    guard
      let currentIndex = countryOptions.firstIndex(of: viewModel.selectedCountry),
      canCycle(currentIndex: currentIndex, totalCount: countryOptions.count, offset: offset)
    else {
      return
    }
    viewModel.selectedCountry = countryOptions[currentIndex + offset]
  }

  private func openReceiverWebsite(for entry: ReceiverDirectoryEntry) {
    guard let url = URL(string: entry.endpointURL) else { return }
    openURL(url)
  }
}
