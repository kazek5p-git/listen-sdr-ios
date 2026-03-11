import SwiftUI

private struct ProfileEditorContext: Identifiable {
  let id = UUID()
  let title: String
  let profile: SDRConnectionProfile
  let isNew: Bool
}

private enum HistorySectionFilter: String, CaseIterable, Identifiable {
  case all
  case receivers
  case listening

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all:
      return L10n.text("history.filter.scope.all")
    case .receivers:
      return L10n.text("history.filter.scope.receivers")
    case .listening:
      return L10n.text("history.filter.scope.listening")
    }
  }
}

private enum HistoryBackendFilter: String, CaseIterable, Identifiable {
  case all
  case fmdx
  case kiwi
  case openWebRX

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all:
      return L10n.text("history.filter.backend.all")
    case .fmdx:
      return SDRBackend.fmDxWebserver.displayName
    case .kiwi:
      return SDRBackend.kiwiSDR.displayName
    case .openWebRX:
      return SDRBackend.openWebRX.displayName
    }
  }

  func matches(_ backend: SDRBackend) -> Bool {
    switch self {
    case .all:
      return true
    case .fmdx:
      return backend == .fmDxWebserver
    case .kiwi:
      return backend == .kiwiSDR
    case .openWebRX:
      return backend == .openWebRX
    }
  }
}

private enum RadiosSearchScope: String, CaseIterable, Identifiable {
  case historyOnly
  case historyAndRadios

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .historyOnly:
      return L10n.text("radios.search.scope.history_only")
    case .historyAndRadios:
      return L10n.text("radios.search.scope.history_and_radios")
    }
  }
}

private enum HistoryReceiverSort: String, CaseIterable, Identifiable {
  case recent
  case name

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .recent:
      return L10n.text("history.sort.option.recent")
    case .name:
      return L10n.text("history.sort.option.name")
    }
  }
}

private enum HistoryListeningSort: String, CaseIterable, Identifiable {
  case recent
  case name
  case frequency

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .recent:
      return L10n.text("history.sort.option.recent")
    case .name:
      return L10n.text("history.sort.option.name")
    case .frequency:
      return L10n.text("history.sort.option.frequency")
    }
  }
}

struct RadiosView: View {
  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var favoritesStore: FavoritesStore
  @EnvironmentObject private var historyStore: ListeningHistoryStore
  @State private var editorContext: ProfileEditorContext?
  @State private var isDirectoryPresented = false
  @State private var historySectionFilter: HistorySectionFilter = .all
  @State private var historyBackendFilter: HistoryBackendFilter = .all
  @State private var historyReceiverSort: HistoryReceiverSort = .recent
  @State private var historyListeningSort: HistoryListeningSort = .recent
  @State private var searchText = ""
  @State private var searchScope: RadiosSearchScope = .historyOnly
  @State private var isRecentReceiversExpanded = true
  @State private var isRecentListeningExpanded = true

  var body: some View {
    NavigationStack {
      Group {
        if profileStore.profiles.isEmpty
          && historyStore.recentReceivers.isEmpty
          && historyStore.recentListening.isEmpty {
          UnavailableContentView(
            title: L10n.text("No Radios Yet"),
            systemImage: "dot.radiowaves.left.and.right",
            description: L10n.text("Add a KiwiSDR, OpenWebRX or FM-DX receiver profile.")
          )
        } else {
          List {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isSearching = !query.isEmpty
            let favoriteProfiles = favoritesStore.favoriteProfiles(in: profileStore.profiles)
            let favoriteIDs = Set(favoriteProfiles.map(\.id))
            let baseOtherProfiles = profileStore.profiles.filter { !favoriteIDs.contains($0.id) }
            let filteredRecentReceivers = historyStore.recentReceivers.filter {
              historyBackendFilter.matches($0.backend)
                && (!isSearching || recentReceiverMatchesQuery($0, query: query))
            }
            let filteredRecentListening = historyStore.recentListening.filter {
              historyBackendFilter.matches($0.backend)
                && (!isSearching || recentListeningMatchesQuery($0, query: query))
            }
            let sortedRecentReceivers = applyReceiverSort(to: filteredRecentReceivers)
            let sortedRecentListening = applyListeningSort(to: filteredRecentListening)
            let filteredFavoriteProfiles =
              isSearching && searchScope == .historyAndRadios
              ? favoriteProfiles.filter { profileMatchesQuery($0, query: query) }
              : favoriteProfiles
            let filteredOtherProfiles =
              isSearching && searchScope == .historyAndRadios
              ? baseOtherProfiles.filter { profileMatchesQuery($0, query: query) }
              : baseOtherProfiles
            let showsReceiversHistory =
              historySectionFilter == .all || historySectionFilter == .receivers
            let showsListeningHistory =
              historySectionFilter == .all || historySectionFilter == .listening
            let hasAnyHistory = !historyStore.recentReceivers.isEmpty || !historyStore.recentListening.isEmpty
            let showRadioSections = !isSearching || searchScope == .historyAndRadios
            let noHistoryMatchesFilter =
              (showsReceiversHistory ? filteredRecentReceivers.isEmpty : true)
              && (showsListeningHistory ? filteredRecentListening.isEmpty : true)
            let noRadioMatchesFilter =
              filteredFavoriteProfiles.isEmpty && filteredOtherProfiles.isEmpty
            let noSearchMatches =
              isSearching
              && noHistoryMatchesFilter
              && (!showRadioSections || noRadioMatchesFilter)

            Section(L10n.text("radios.search.section")) {
              NavigationLink {
                SelectionListView(
                  title: L10n.text("radios.search.scope"),
                  options: RadiosSearchScope.allCases.map {
                    SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
                  },
                  selectedID: searchScope.rawValue
                ) { value in
                  if let scope = RadiosSearchScope(rawValue: value) {
                    searchScope = scope
                  }
                }
              } label: {
                LabeledContent(
                  L10n.text("radios.search.scope"),
                  value: searchScope.displayName
                )
              }
            }
            .appSectionStyle()

            if hasAnyHistory {
              Section(L10n.text("history.filters.section")) {
                NavigationLink {
                  SelectionListView(
                    title: L10n.text("history.filter.scope"),
                    options: HistorySectionFilter.allCases.map {
                      SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
                    },
                    selectedID: historySectionFilter.rawValue
                  ) { value in
                    if let filter = HistorySectionFilter(rawValue: value) {
                      historySectionFilter = filter
                    }
                  }
                } label: {
                  LabeledContent(
                    L10n.text("history.filter.scope"),
                    value: historySectionFilter.displayName
                  )
                }

                NavigationLink {
                  SelectionListView(
                    title: L10n.text("history.filter.backend"),
                    options: HistoryBackendFilter.allCases.map {
                      SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
                    },
                    selectedID: historyBackendFilter.rawValue
                  ) { value in
                    if let filter = HistoryBackendFilter(rawValue: value) {
                      historyBackendFilter = filter
                    }
                  }
                } label: {
                  LabeledContent(
                    L10n.text("history.filter.backend"),
                    value: historyBackendFilter.displayName
                  )
                }

                if !historyStore.recentReceivers.isEmpty {
                  NavigationLink {
                    SelectionListView(
                      title: L10n.text("history.sort.receivers"),
                      options: HistoryReceiverSort.allCases.map {
                        SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
                      },
                      selectedID: historyReceiverSort.rawValue
                    ) { value in
                      if let sort = HistoryReceiverSort(rawValue: value) {
                        historyReceiverSort = sort
                      }
                    }
                  } label: {
                    LabeledContent(
                      L10n.text("history.sort.receivers"),
                      value: historyReceiverSort.displayName
                    )
                  }
                }

                if !historyStore.recentListening.isEmpty {
                  NavigationLink {
                    SelectionListView(
                      title: L10n.text("history.sort.listening"),
                      options: HistoryListeningSort.allCases.map {
                        SelectionListOption(id: $0.rawValue, title: $0.displayName, detail: nil)
                      },
                      selectedID: historyListeningSort.rawValue
                    ) { value in
                      if let sort = HistoryListeningSort(rawValue: value) {
                        historyListeningSort = sort
                      }
                    }
                  } label: {
                    LabeledContent(
                      L10n.text("history.sort.listening"),
                      value: historyListeningSort.displayName
                    )
                  }
                }
              }
              .appSectionStyle()
            }

            if showsReceiversHistory && !sortedRecentReceivers.isEmpty {
              Section {
                historySectionToggle(
                  title: L10n.text("history.recent_receivers.section"),
                  isExpanded: $isRecentReceiversExpanded
                )

                if isRecentReceiversExpanded {
                  ForEach(sortedRecentReceivers) { record in
                    recentReceiverRow(for: record)
                  }

                  Button(role: .destructive) {
                    historyStore.clearRecentReceivers()
                  } label: {
                    Text(L10n.text("history.clear_receivers"))
                  }
                }
              }
              .appSectionStyle()
            }

            if showsListeningHistory && !sortedRecentListening.isEmpty {
              Section {
                historySectionToggle(
                  title: L10n.text("history.recent_listening.section"),
                  isExpanded: $isRecentListeningExpanded
                )

                if isRecentListeningExpanded {
                  ForEach(sortedRecentListening) { record in
                    recentListeningRow(for: record)
                  }

                  Button(role: .destructive) {
                    historyStore.clearRecentListening()
                  } label: {
                    Text(L10n.text("history.clear_listening"))
                  }
                }
              }
              .appSectionStyle()
            }

            if hasAnyHistory && noHistoryMatchesFilter && !isSearching {
              Section {
                Text(L10n.text("history.empty_filtered"))
                  .foregroundStyle(.secondary)
              }
              .appSectionStyle()
            }

            if showRadioSections && !filteredFavoriteProfiles.isEmpty {
              Section(L10n.text("favorites.receivers.section")) {
                ForEach(filteredFavoriteProfiles) { profile in
                  profileRow(for: profile, isFavorite: true)
                }
              }
            }

            if showRadioSections && !filteredOtherProfiles.isEmpty {
              Section(L10n.text("Radios")) {
                ForEach(filteredOtherProfiles) { profile in
                  profileRow(for: profile, isFavorite: false)
                }
              }
            }

            if noSearchMatches {
              Section {
                Text(L10n.text("radios.search.empty"))
                  .foregroundStyle(.secondary)
              }
              .appSectionStyle()
            }
          }
          .listStyle(.insetGrouped)
          .scrollContentBackground(.hidden)
        }
      }
      .navigationTitle("Radios")
      .searchable(text: $searchText, prompt: L10n.text("radios.search.prompt"))
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            isDirectoryPresented = true
          } label: {
            Label("Directory", systemImage: "globe")
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            editorContext = ProfileEditorContext(
              title: L10n.text("New Radio"),
              profile: SDRConnectionProfile.empty(),
              isNew: true
            )
          } label: {
            Label("Add radio", systemImage: "plus")
          }
        }
      }
      .appScreenBackground()
      .sheet(isPresented: $isDirectoryPresented) {
        ReceiverDirectoryView()
      }
      .sheet(item: $editorContext) { context in
        ProfileEditorView(
          title: context.title,
          initialProfile: context.profile,
          onSave: { profile in
            profileStore.upsert(profile)
            if context.isNew {
              profileStore.updateSelection(profile.id)
            }
            editorContext = nil
          },
          onCancel: {
            editorContext = nil
          }
        )
      }
    }
  }

  @ViewBuilder
  private func profileRow(for profile: SDRConnectionProfile, isFavorite: Bool) -> some View {
    Button {
      profileStore.updateSelection(profile.id)
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: backendIconName(for: profile.backend))
          .font(.headline)
          .foregroundStyle(backendAccent(for: profile.backend))
          .frame(width: 34, height: 34)
          .background(
            backendAccent(for: profile.backend).opacity(0.16),
            in: Circle()
          )
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 6) {
          Text(profile.name)
            .font(.headline)

          Text(profile.backend.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.chipFill, in: Capsule())

          Text(profile.endpointDescription)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 10) {
          if isFavorite {
            Image(systemName: "star.fill")
              .foregroundStyle(.yellow)
              .accessibilityHidden(true)
          }

          if profileStore.selectedProfileID == profile.id {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .accessibilityHidden(true)
          }
        }
      }
      .appCardContainer()
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button {
        favoritesStore.toggleReceiver(profile)
      } label: {
        Label(
          favoritesStore.isFavoriteReceiver(profile)
            ? L10n.text("favorites.receiver.remove")
            : L10n.text("favorites.receiver.add"),
          systemImage: favoritesStore.isFavoriteReceiver(profile) ? "star.slash" : "star"
        )
      }
      .tint(.yellow)

      Button("Edit") {
        editorContext = ProfileEditorContext(
          title: L10n.text("Edit Radio"),
          profile: profile,
          isNew: false
        )
      }

      Button("Delete", role: .destructive) {
        profileStore.delete(profile)
      }
    }
    .accessibilityLabel(profile.name)
    .accessibilityHint(L10n.text("Double tap to select this receiver profile"))
    .accessibilityValue(
      profileStore.selectedProfileID == profile.id
        ? L10n.text("common.selected")
        : L10n.text("common.not_selected")
    )
  }

  @ViewBuilder
  private func recentReceiverRow(for record: RecentReceiverRecord) -> some View {
    let candidateProfile = record.makeProfile()
    let storedProfile = profileStore.matchingProfile(for: candidateProfile)
    let selectedID = storedProfile?.id
    let endpointText = candidateProfile.endpointDescription
    let lastUsedText = record.lastUsedAt.formatted(date: .abbreviated, time: .shortened)

    Button {
      connectAndSelect(profile: candidateProfile)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(record.receiverName)
          .font(.headline)

        Text([record.backend.displayName, endpointText].joined(separator: " | "))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)

        Text(
          L10n.text(
            "history.last_used",
            lastUsedText
          )
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .appCardContainer()
      .overlay(alignment: .topTrailing) {
        if let selectedID, profileStore.selectedProfileID == selectedID {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .padding(10)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      L10n.text(
        "history.recent_receivers.accessibility",
        record.receiverName,
        record.backend.displayName,
        endpointText,
        lastUsedText
      )
    )
    .buttonStyle(.plain)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        favoritesStore.toggleReceiver(candidateProfile)
      } label: {
        Label(
          favoritesStore.isFavoriteReceiver(candidateProfile)
            ? L10n.text("favorites.receiver.remove")
            : L10n.text("favorites.receiver.add"),
          systemImage: favoritesStore.isFavoriteReceiver(candidateProfile) ? "star.slash" : "star"
        )
      }
      .tint(.yellow)

      Button(role: .destructive) {
        historyStore.removeRecentReceiver(record)
      } label: {
        Label(L10n.text("Delete"), systemImage: "trash")
      }
    }
    .accessibilityHint(L10n.text("history.recent_receivers.hint"))
  }

  @ViewBuilder
  private func recentListeningRow(for record: RecentListeningRecord) -> some View {
    let candidateProfile = record.makeProfile()
    let primaryTitle = record.primaryTitle
    let modeName = record.mode?.displayName ?? candidateProfile.backend.displayName
    let frequencyText = FrequencyFormatter.mhzText(fromHz: record.frequencyHz)
    let heardAtText = record.lastHeardAt.formatted(date: .abbreviated, time: .shortened)
    let titleIsFrequency = primaryTitle == frequencyText
    let summaryText = titleIsFrequency
      ? modeName
      : [frequencyText, modeName].joined(separator: " | ")

    Button {
      restoreListeningRecord(record)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(primaryTitle)
          .font(.headline)

        Text(summaryText)
        .font(.subheadline)
        .foregroundStyle(.secondary)

        LabeledContent(
          L10n.text("history.recent_listening.receiver"),
          value: record.receiverName
        )
        .font(.footnote)

        if !titleIsFrequency {
          LabeledContent(
            L10n.text("history.recent_listening.frequency"),
            value: frequencyText
          )
          .font(.footnote)
        }

        Text(
          L10n.text(
            "history.recent_listening.last_heard",
            record.backend.displayName,
            heardAtText
          )
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .appCardContainer()
    }
    .buttonStyle(.plain)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        favoritesStore.toggleStation(
          profile: candidateProfile,
          title: record.stationTitle ?? FrequencyFormatter.mhzText(fromHz: record.frequencyHz),
          frequencyHz: record.frequencyHz,
          mode: record.mode
        )
      } label: {
        Label(
          isFavoriteListeningRecord(record)
            ? L10n.text("favorites.station.remove_current")
            : L10n.text("favorites.station.add_current"),
          systemImage: isFavoriteListeningRecord(record) ? "star.slash" : "star.circle"
        )
      }
      .tint(.yellow)

      Button(role: .destructive) {
        historyStore.removeRecentListening(record)
      } label: {
        Label(L10n.text("Delete"), systemImage: "trash")
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      titleIsFrequency
        ? L10n.text(
          "history.recent_listening.accessibility.frequency_title",
          record.receiverName,
          frequencyText,
          modeName,
          heardAtText
        )
        : L10n.text(
          "history.recent_listening.accessibility",
          primaryTitle,
          record.receiverName,
          frequencyText,
          modeName,
          heardAtText
        )
    )
    .accessibilityHint(L10n.text("history.recent_listening.hint"))
  }

  private func historySectionToggle(title: String, isExpanded: Binding<Bool>) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.wrappedValue.toggle()
      }
    } label: {
      HStack(spacing: 12) {
        Text(title)
          .font(.headline)

        Spacer()

        Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(
      L10n.text(
        isExpanded.wrappedValue
          ? "history.section.expanded"
          : "history.section.collapsed"
      )
    )
    .accessibilityHint(
      L10n.text(
        isExpanded.wrappedValue
          ? "history.section.collapse"
          : "history.section.expand"
      )
    )
  }

  private func connectAndSelect(profile candidateProfile: SDRConnectionProfile) {
    let storedProfile = profileStore.upsertImportedProfile(candidateProfile)
    profileStore.updateSelection(storedProfile.id)
    if radioSession.state != .connected || radioSession.connectedProfileID != storedProfile.id {
      radioSession.connect(to: storedProfile)
    }
    openReceiverTabAfterHistoryActionIfNeeded()
  }

  private func restoreListeningRecord(_ record: RecentListeningRecord) {
    let storedProfile = profileStore.upsertImportedProfile(record.makeProfile())
    profileStore.updateSelection(storedProfile.id)
    if radioSession.state == .connected && radioSession.connectedProfileID == storedProfile.id {
      radioSession.restoreCurrentSession(
        frequencyHz: record.frequencyHz,
        mode: record.mode
      )
      openReceiverTabAfterHistoryActionIfNeeded()
      return
    }
    radioSession.connect(
      to: storedProfile,
      restoringFrequencyHz: record.frequencyHz,
      mode: record.mode
    )
    openReceiverTabAfterHistoryActionIfNeeded()
  }

  private func openReceiverTabAfterHistoryActionIfNeeded() {
    guard radioSession.settings.openReceiverAfterHistoryRestore else { return }
    DispatchQueue.main.async {
      navigationState.selectedTab = .receiver
    }
  }

  private func isFavoriteListeningRecord(_ record: RecentListeningRecord) -> Bool {
    favoritesStore.stations(for: record.makeProfile()).contains {
      $0.frequencyHz == record.frequencyHz && $0.mode == record.mode
    }
  }

  private func recentReceiverMatchesQuery(_ record: RecentReceiverRecord, query: String) -> Bool {
    guard !query.isEmpty else { return true }

    let tokens = [
      record.receiverName,
      record.backend.displayName,
      record.host,
      record.makeProfile().endpointDescription
    ]

    return tokens.contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func recentListeningMatchesQuery(_ record: RecentListeningRecord, query: String) -> Bool {
    guard !query.isEmpty else { return true }

    let tokens = [
      record.primaryTitle,
      record.stationTitle ?? "",
      record.receiverName,
      record.backend.displayName,
      FrequencyFormatter.mhzText(fromHz: record.frequencyHz),
      "\(record.frequencyHz)"
    ]

    return tokens.contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func profileMatchesQuery(_ profile: SDRConnectionProfile, query: String) -> Bool {
    guard !query.isEmpty else { return true }

    let tokens = [
      profile.name,
      profile.backend.displayName,
      profile.host,
      profile.endpointDescription
    ]

    return tokens.contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func applyReceiverSort(to records: [RecentReceiverRecord]) -> [RecentReceiverRecord] {
    switch historyReceiverSort {
    case .recent:
      return records.sorted { lhs, rhs in
        if lhs.lastUsedAt != rhs.lastUsedAt {
          return lhs.lastUsedAt > rhs.lastUsedAt
        }
        return lhs.receiverName.localizedCaseInsensitiveCompare(rhs.receiverName) == .orderedAscending
      }
    case .name:
      return records.sorted { lhs, rhs in
        let comparison = lhs.receiverName.localizedCaseInsensitiveCompare(rhs.receiverName)
        if comparison != .orderedSame {
          return comparison == .orderedAscending
        }
        return lhs.lastUsedAt > rhs.lastUsedAt
      }
    }
  }

  private func applyListeningSort(to records: [RecentListeningRecord]) -> [RecentListeningRecord] {
    switch historyListeningSort {
    case .recent:
      return records.sorted { lhs, rhs in
        if lhs.lastHeardAt != rhs.lastHeardAt {
          return lhs.lastHeardAt > rhs.lastHeardAt
        }
        return lhs.primaryTitle.localizedCaseInsensitiveCompare(rhs.primaryTitle) == .orderedAscending
      }
    case .name:
      return records.sorted { lhs, rhs in
        let comparison = lhs.primaryTitle.localizedCaseInsensitiveCompare(rhs.primaryTitle)
        if comparison != .orderedSame {
          return comparison == .orderedAscending
        }
        if lhs.frequencyHz != rhs.frequencyHz {
          return lhs.frequencyHz < rhs.frequencyHz
        }
        return lhs.lastHeardAt > rhs.lastHeardAt
      }
    case .frequency:
      return records.sorted { lhs, rhs in
        if lhs.frequencyHz != rhs.frequencyHz {
          return lhs.frequencyHz < rhs.frequencyHz
        }
        let comparison = lhs.primaryTitle.localizedCaseInsensitiveCompare(rhs.primaryTitle)
        if comparison != .orderedSame {
          return comparison == .orderedAscending
        }
        return lhs.lastHeardAt > rhs.lastHeardAt
      }
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
