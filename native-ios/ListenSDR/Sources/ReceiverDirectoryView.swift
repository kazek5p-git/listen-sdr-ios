import SwiftUI

struct ReceiverDirectoryView: View {
  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var favoritesStore: FavoritesStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @StateObject private var viewModel = ReceiverDirectoryViewModel()

  var body: some View {
    let countryOptions = viewModel.availableCountryOptions
    let filteredEntries = viewModel.filteredEntries(favoriteReceiverIDs: favoritesStore.favoriteReceiverIDs)

    NavigationStack {
      List {
        backendSection
        filtersSection(countryOptions: countryOptions)
        statusSection
        receiversSection(filteredEntries: filteredEntries)
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
                await viewModel.refresh(force: true, userInitiated: true)
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
        await viewModel.refresh(force: true, userInitiated: true)
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

  private var backendSection: some View {
    Section {
      CyclingOptionCard(
        title: L10n.text("Backend source"),
        selectedTitle: viewModel.selectedBackend.displayName,
        detail: nil,
        canDecrement: viewModel.supportedBackends.count > 1,
        canIncrement: viewModel.supportedBackends.count > 1,
        accessibilityHint: L10n.text("directory.filters.selection_hint")
      ) {
        adjustBackend(by: -1)
      } incrementAction: {
        adjustBackend(by: 1)
      }
    }
    .appSectionStyle()
  }

  private func filtersSection(countryOptions: [ReceiverDirectoryCountryOption]) -> some View {
    Section {
      statusFilterSelectionLink
      entrySortSelectionLink
      if !countryOptions.isEmpty {
        if shouldShowCountrySortControl(countryOptions: countryOptions) {
          countrySortSelectionLink
        }
        countryFilterSelectionLink(countryOptions: countryOptions)
      }
      Toggle(
        L10n.text("directory.filters.favorites_only"),
        isOn: Binding(
          get: { viewModel.favoritesOnly },
          set: { newValue in
            viewModel.favoritesOnly = newValue
            AppInteractionFeedbackCenter.playIfEnabled(newValue ? .enabled : .disabled)
          }
        )
      )
    } header: {
      AppSectionHeader(title: L10n.text("directory.filters.section"))
    }
    .appSectionStyle()
  }

  private var statusSection: some View {
    Section {
      statusSummaryView
      if let refreshResultMessage = viewModel.refreshResultMessage, !refreshResultMessage.isEmpty {
        Text(refreshResultMessage)
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
        probingStatusView
      }
      if viewModel.canClearCache {
        clearCacheButton
      }
    } header: {
      AppSectionHeader(title: L10n.text("Status"))
    } footer: {
      Text(viewModel.sourceSummaryText)
    }
    .appSectionStyle()
  }

  private func receiversSection(filteredEntries: [ReceiverDirectoryEntry]) -> some View {
    Section {
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

  @ViewBuilder
  private func directoryRow(for entry: ReceiverDirectoryEntry) -> some View {
    let candidateProfile = entry.makeProfile()
    let existingProfile = profileStore.matchingProfile(for: candidateProfile)
    let isSelected = existingProfile?.id == profileStore.selectedProfileID
    let isFavorite = favoritesStore.isFavoriteReceiver(entry)

    FocusRetainingButton {
      selectReceiverDirectoryEntry(candidateProfile)
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
        toggleFavoriteReceiver(entry, isFavorite: isFavorite)
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
    .accessibilityLabel(entry.name)
    .accessibilityValue(
      receiverValueText(
        entry: entry,
        existingProfile: existingProfile,
        isSelected: isSelected
      )
    )
    .accessibilityHint(
      receiverHintText(existingProfile: existingProfile, isSelected: isSelected)
    )
    .accessibilityAction {
      selectReceiverDirectoryEntry(candidateProfile)
    }
    .accessibilityAction(named: Text(L10n.text("directory.receiver.connect_now"))) {
      selectAndConnectReceiverDirectoryEntry(candidateProfile)
    }
    .accessibilityRemoveTraits(.isSelected)
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

  private var countrySortOptions: [ReceiverDirectoryCountrySortOption] {
    ReceiverDirectoryCountrySortOption.allCases
  }

  private func adjustBackend(by offset: Int) {
    let backends = viewModel.supportedBackends
    guard !backends.isEmpty else { return }
    let currentIndex = backends.firstIndex(of: viewModel.selectedBackend) ?? 0
    let nextIndex = (currentIndex + offset + backends.count) % backends.count
    applyBackendSelection(backends[nextIndex])
  }

  private func applyBackendSelection(_ backend: SDRBackend) {
    guard backend != viewModel.selectedBackend else { return }
    viewModel.selectedBackend = backend
    announceDirectorySelection(
      title: L10n.text("Backend source"),
      value: backend.displayName
    )
  }

  private var statusFilterSelectionLink: some View {
    NavigationLink {
      SelectionListView(
        title: L10n.text("directory.filters.status"),
        options: statusFilterOptions.map {
          SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
        },
        selectedID: viewModel.statusFilter.rawValue,
        selectionAnnouncement: directorySelectionAnnouncement(
          title: L10n.text("directory.filters.status")
        )
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("directory.filters.status"))
    .accessibilityValue(viewModel.statusFilter.displayName)
    .accessibilityHint(L10n.text("directory.filters.selection_hint"))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        adjustStatusFilter(by: 1)
      case .decrement:
        adjustStatusFilter(by: -1)
      @unknown default:
        break
      }
    }
  }

  private var entrySortSelectionLink: some View {
    NavigationLink {
      SelectionListView(
        title: L10n.text("directory.filters.sort"),
        options: sortOptions.map {
          SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
        },
        selectedID: viewModel.sortOption.rawValue,
        selectionAnnouncement: directorySelectionAnnouncement(
          title: L10n.text("directory.filters.sort")
        )
      ) { value in
        if let option = ReceiverDirectorySortOption(rawValue: value) {
          viewModel.sortOption = option
        }
      }
    } label: {
      LabeledContent(
        L10n.text("directory.filters.sort"),
        value: viewModel.sortOption.displayName
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("directory.filters.sort"))
    .accessibilityValue(viewModel.sortOption.displayName)
    .accessibilityHint(L10n.text("directory.filters.selection_hint"))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        adjustSortOption(by: 1)
      case .decrement:
        adjustSortOption(by: -1)
      @unknown default:
        break
      }
    }
  }

  private var countrySortSelectionLink: some View {
    NavigationLink {
      SelectionListView(
        title: L10n.text("directory.filters.country_sort"),
        options: countrySortOptions.map {
          SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
        },
        selectedID: viewModel.countrySortOption.rawValue,
        selectionAnnouncement: directorySelectionAnnouncement(
          title: L10n.text("directory.filters.country_sort")
        )
      ) { value in
        if let option = ReceiverDirectoryCountrySortOption(rawValue: value) {
          viewModel.countrySortOption = option
        }
      }
    } label: {
      LabeledContent(
        L10n.text("directory.filters.country_sort"),
        value: viewModel.countrySortOption.displayName
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("directory.filters.country_sort"))
    .accessibilityValue(viewModel.countrySortOption.displayName)
    .accessibilityHint(L10n.text("directory.filters.selection_hint"))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        adjustCountrySort(by: 1)
      case .decrement:
        adjustCountrySort(by: -1)
      @unknown default:
        break
      }
    }
  }

  private func countryFilterSelectionLink(countryOptions: [ReceiverDirectoryCountryOption]) -> some View {
    NavigationLink {
      SelectionListView(
        title: L10n.text("directory.filters.country"),
        options: countrySelectionListOptions(countryOptions: countryOptions),
        selectedID: viewModel.selectedCountry,
        selectionAnnouncement: directorySelectionAnnouncement(
          title: L10n.text("directory.filters.country"),
          includeTitle: false
        )
      ) { value in
        viewModel.selectedCountry = value
      }
    } label: {
      LabeledContent(
        L10n.text("directory.filters.country"),
        value: selectedCountryTitle(countryOptions: countryOptions)
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("directory.filters.country"))
    .accessibilityValue(selectedCountryTitle(countryOptions: countryOptions))
    .accessibilityHint(L10n.text("directory.filters.selection_hint"))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        adjustCountry(by: 1, countryOptions: countryOptions)
      case .decrement:
        adjustCountry(by: -1, countryOptions: countryOptions)
      @unknown default:
        break
      }
    }
  }

  private func countrySelectionListOptions(
    countryOptions: [ReceiverDirectoryCountryOption]
  ) -> [SelectionListOption] {
    [SelectionListOption(id: "", title: L10n.text("directory.filter.country.all"), detail: nil)]
      + countryOptions.map { country in
          SelectionListOption(
            id: country.countryLabel,
            title: "\(country.countryLabel) (\(country.receiverCount))",
            detail: nil
          )
      }
  }

  private var statusSummaryView: some View {
    Group {
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
    }
  }

  private var probingStatusView: some View {
    HStack(spacing: 8) {
      ProgressView()
      Text(L10n.text("Checking receiver availability..."))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityLabel(L10n.text("Checking receiver availability"))
  }

  private var clearCacheButton: some View {
    FocusRetainingButton({
      viewModel.clearCache()
    }, role: .destructive) {
      Label(L10n.text("directory.cache.clear"), systemImage: "trash")
    }
  }

  private func shouldShowCountrySortControl(
    countryOptions: [ReceiverDirectoryCountryOption]
  ) -> Bool {
    viewModel.selectedBackend == .fmDxWebserver && countryOptions.count > 1
  }

  private func selectedCountryTitle(
    countryOptions: [ReceiverDirectoryCountryOption]
  ) -> String {
    guard !viewModel.selectedCountry.isEmpty else {
      return L10n.text("directory.filter.country.all")
    }

    if let option = countryOptions.first(where: { $0.countryLabel == viewModel.selectedCountry }) {
      return "\(option.countryLabel) (\(option.receiverCount))"
    }

    return viewModel.selectedCountry
  }

  private func adjustStatusFilter(by offset: Int) {
    adjustSelection(
      options: statusFilterOptions.map(\.rawValue),
      selectedID: viewModel.statusFilter.rawValue,
      offset: offset,
      update: { value in
        if let filter = ReceiverDirectoryStatusFilter(rawValue: value) {
          viewModel.statusFilter = filter
          announceDirectorySelection(
            title: L10n.text("directory.filters.status"),
            value: filter.displayName
          )
        }
      }
    )
  }

  private func adjustSortOption(by offset: Int) {
    adjustSelection(
      options: sortOptions.map(\.rawValue),
      selectedID: viewModel.sortOption.rawValue,
      offset: offset,
      update: { value in
        if let option = ReceiverDirectorySortOption(rawValue: value) {
          viewModel.sortOption = option
          announceDirectorySelection(
            title: L10n.text("directory.filters.sort"),
            value: option.displayName
          )
        }
      }
    )
  }

  private func adjustCountrySort(by offset: Int) {
    adjustSelection(
      options: countrySortOptions.map(\.rawValue),
      selectedID: viewModel.countrySortOption.rawValue,
      offset: offset,
      update: { value in
        if let option = ReceiverDirectoryCountrySortOption(rawValue: value) {
          viewModel.countrySortOption = option
          announceDirectorySelection(
            title: L10n.text("directory.filters.country_sort"),
            value: option.displayName
          )
        }
      }
    )
  }

  private func adjustCountry(
    by offset: Int,
    countryOptions: [ReceiverDirectoryCountryOption]
  ) {
    adjustSelection(
      options: [""] + countryOptions.map(\.countryLabel),
      selectedID: viewModel.selectedCountry,
      offset: offset,
      update: { value in
        viewModel.selectedCountry = value
        announceDirectorySelection(
          title: L10n.text("directory.filters.country"),
          value: selectedCountryTitle(countryOptions: countryOptions),
          includeTitle: false
        )
      }
    )
  }

  private func announceDirectorySelection(
    title: String,
    value: String,
    includeTitle: Bool = true
  ) {
    if includeTitle {
      AppAccessibilityAnnouncementCenter.post("\(title): \(value)")
    } else {
      AppAccessibilityAnnouncementCenter.post(value)
    }
  }

  private func directorySelectionAnnouncement(
    title: String,
    includeTitle: Bool = true
  ) -> (SelectionListOption) -> String? {
    { option in
      AppAccessibilityAnnouncementCenter.selectionAnnouncementText(
        title: title,
        value: option.title,
        includeTitle: includeTitle
      )
    }
  }

  private func adjustSelection(
    options: [String],
    selectedID: String,
    offset: Int = 1,
    update: (String) -> Void
  ) {
    guard !options.isEmpty else { return }
    let currentIndex = options.firstIndex(of: selectedID) ?? 0
    let nextIndex = min(max(currentIndex + offset, 0), options.count - 1)
    guard nextIndex != currentIndex else { return }
    update(options[nextIndex])
  }

  private func openReceiverWebsite(for entry: ReceiverDirectoryEntry) {
    guard let url = URL(string: entry.endpointURL) else { return }
    openURL(url)
  }

  private func selectReceiverDirectoryEntry(_ profile: SDRConnectionProfile) {
    let storedProfile = profileStore.upsertImportedProfile(profile)
    profileStore.updateSelection(storedProfile.id)
    if radioSession.settings.autoConnectSelectedProfileAfterSelection {
      if radioSession.state != .connected || radioSession.connectedProfileID != storedProfile.id {
        radioSession.connect(to: storedProfile)
      }
    }
    navigationState.selectedTab = .receiver
    dismiss()
  }

  private func selectAndConnectReceiverDirectoryEntry(_ profile: SDRConnectionProfile) {
    let storedProfile = profileStore.upsertImportedProfile(profile)
    profileStore.updateSelection(storedProfile.id)
    if radioSession.state != .connected || radioSession.connectedProfileID != storedProfile.id {
      radioSession.connect(to: storedProfile)
    }
    navigationState.selectedTab = .receiver
    dismiss()
  }

  private func toggleFavoriteReceiver(_ entry: ReceiverDirectoryEntry, isFavorite: Bool) {
    favoritesStore.toggleReceiver(entry)
    AppAccessibilityAnnouncementCenter.post(
      L10n.text(
        isFavorite
          ? "directory.receiver.favorite_removed"
          : "directory.receiver.favorite_added",
        entry.name
      )
    )
  }

  private func receiverStateText(
    existingProfile: SDRConnectionProfile?,
    isSelected: Bool
  ) -> String {
    if existingProfile == nil {
      return L10n.text("directory.receiver.state.not_added")
    }
    if isSelected {
      return L10n.text("directory.receiver.state.added_selected")
    }
    return L10n.text("directory.receiver.state.added")
  }

  private func receiverValueText(
    entry: ReceiverDirectoryEntry,
    existingProfile: SDRConnectionProfile?,
    isSelected: Bool
  ) -> String {
    [
      entry.status.displayName,
      entry.detailText,
      receiverStateText(existingProfile: existingProfile, isSelected: isSelected)
    ]
    .filter { !$0.isEmpty }
    .joined(separator: ", ")
  }

  private func receiverHintText(
    existingProfile: SDRConnectionProfile?,
    isSelected: Bool
  ) -> String {
    if existingProfile == nil {
      return L10n.text("directory.receiver.hint.add_select")
    }
    if isSelected {
      return L10n.text("directory.receiver.hint.selected")
    }
    return L10n.text("directory.receiver.hint.select")
  }
}
