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

struct RadiosView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var favoritesStore: FavoritesStore
  @EnvironmentObject private var historyStore: ListeningHistoryStore
  @State private var editorContext: ProfileEditorContext?
  @State private var isDirectoryPresented = false
  @State private var historySectionFilter: HistorySectionFilter = .all
  @State private var historyBackendFilter: HistoryBackendFilter = .all

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
            let favoriteProfiles = favoritesStore.favoriteProfiles(in: profileStore.profiles)
            let favoriteIDs = Set(favoriteProfiles.map(\.id))
            let otherProfiles = profileStore.profiles.filter { !favoriteIDs.contains($0.id) }
            let filteredRecentReceivers = historyStore.recentReceivers.filter {
              historyBackendFilter.matches($0.backend)
            }
            let filteredRecentListening = historyStore.recentListening.filter {
              historyBackendFilter.matches($0.backend)
            }
            let showsReceiversHistory =
              historySectionFilter == .all || historySectionFilter == .receivers
            let showsListeningHistory =
              historySectionFilter == .all || historySectionFilter == .listening
            let hasAnyHistory = !historyStore.recentReceivers.isEmpty || !historyStore.recentListening.isEmpty
            let noHistoryMatchesFilter =
              (showsReceiversHistory ? filteredRecentReceivers.isEmpty : true)
              && (showsListeningHistory ? filteredRecentListening.isEmpty : true)

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
              }
              .appSectionStyle()
            }

            if showsReceiversHistory && !filteredRecentReceivers.isEmpty {
              Section(L10n.text("history.recent_receivers.section")) {
                ForEach(filteredRecentReceivers) { record in
                  recentReceiverRow(for: record)
                }

                Button(role: .destructive) {
                  historyStore.clearRecentReceivers()
                } label: {
                  Text(L10n.text("history.clear_receivers"))
                }
              }
            }

            if showsListeningHistory && !filteredRecentListening.isEmpty {
              Section(L10n.text("history.recent_listening.section")) {
                ForEach(filteredRecentListening) { record in
                  recentListeningRow(for: record)
                }

                Button(role: .destructive) {
                  historyStore.clearRecentListening()
                } label: {
                  Text(L10n.text("history.clear_listening"))
                }
              }
            }

            if hasAnyHistory && noHistoryMatchesFilter {
              Section {
                Text(L10n.text("history.empty_filtered"))
                  .foregroundStyle(.secondary)
              }
              .appSectionStyle()
            }

            if !favoriteProfiles.isEmpty {
              Section(L10n.text("favorites.receivers.section")) {
                ForEach(favoriteProfiles) { profile in
                  profileRow(for: profile, isFavorite: true)
                }
              }
            }

            if !otherProfiles.isEmpty {
              Section(L10n.text("Radios")) {
                ForEach(otherProfiles) { profile in
                  profileRow(for: profile, isFavorite: false)
                }
              }
            }
          }
          .listStyle(.insetGrouped)
          .scrollContentBackground(.hidden)
        }
      }
      .navigationTitle("Radios")
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

    Button {
      connectAndSelect(profile: candidateProfile)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(record.receiverName)
            .font(.headline)

          Text(record.backend.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.chipFill, in: Capsule())
        }

        Text(candidateProfile.endpointDescription)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)

        Text(
          L10n.text(
            "history.last_used",
            record.lastUsedAt.formatted(date: .abbreviated, time: .shortened)
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
    let modeName = record.mode?.displayName ?? candidateProfile.backend.displayName

    Button {
      restoreListeningRecord(record)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(record.primaryTitle)
          .font(.headline)

        Text(
          [
            FrequencyFormatter.mhzText(fromHz: record.frequencyHz),
            modeName
          ]
            .joined(separator: " | ")
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)

        Text(
          L10n.text(
            "history.recent_listening.detail",
            record.receiverName,
            record.backend.displayName,
            record.lastHeardAt.formatted(date: .abbreviated, time: .shortened)
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
    .accessibilityHint(L10n.text("history.recent_listening.hint"))
  }

  private func connectAndSelect(profile candidateProfile: SDRConnectionProfile) {
    let storedProfile = profileStore.upsertImportedProfile(candidateProfile)
    profileStore.updateSelection(storedProfile.id)
    if radioSession.state != .connected || radioSession.connectedProfileID != storedProfile.id {
      radioSession.connect(to: storedProfile)
    }
  }

  private func restoreListeningRecord(_ record: RecentListeningRecord) {
    let storedProfile = profileStore.upsertImportedProfile(record.makeProfile())
    profileStore.updateSelection(storedProfile.id)
    if radioSession.state == .connected && radioSession.connectedProfileID == storedProfile.id {
      if let mode = record.mode {
        radioSession.setMode(mode)
      }
      radioSession.setFrequencyHz(record.frequencyHz)
      return
    }
    radioSession.connect(
      to: storedProfile,
      restoringFrequencyHz: record.frequencyHz,
      mode: record.mode
    )
  }

  private func isFavoriteListeningRecord(_ record: RecentListeningRecord) -> Bool {
    favoritesStore.stations(for: record.makeProfile()).contains {
      $0.frequencyHz == record.frequencyHz && $0.mode == record.mode
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
