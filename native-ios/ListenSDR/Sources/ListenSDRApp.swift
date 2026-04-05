import SwiftUI

@main
@MainActor
struct ListenSDRApp: App {
  @StateObject private var accessibilityState = AppAccessibilityState()
  @StateObject private var navigationState: AppNavigationState
  @StateObject private var profileStore: ProfileStore
  @StateObject private var radioSession = RadioSessionViewModel()
  @StateObject private var settingsController = SettingsViewController()
  @StateObject private var favoritesStore = FavoritesStore()
  @StateObject private var recordingStore = RecordingStore()
  @StateObject private var historyStore: ListeningHistoryStore
  private let diagnostics = Diagnostics.sharedStore

  init() {
    let profileStore = ProfileStore()
    let historyStore = ListeningHistoryStore.shared
    let initialTab = AppNavigationState.preferredLaunchTab(
      profileCount: profileStore.profiles.count,
      hasRecentReceiverHistory: !historyStore.recentReceivers.isEmpty,
      hasRecentListeningHistory: !historyStore.recentListening.isEmpty
    )
    _profileStore = StateObject(wrappedValue: profileStore)
    _historyStore = StateObject(wrappedValue: historyStore)
    _navigationState = StateObject(wrappedValue: AppNavigationState(selectedTab: initialTab))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(profileStore)
        .environmentObject(accessibilityState)
        .environmentObject(navigationState)
        .environmentObject(radioSession)
        .environmentObject(settingsController)
        .environmentObject(favoritesStore)
        .environmentObject(recordingStore)
        .environmentObject(historyStore)
        .environmentObject(diagnostics)
        .task {
          radioSession.bind(accessibilityState: accessibilityState)
          settingsController.bind(
            radioSession: radioSession,
            profileStore: profileStore,
            favoritesStore: favoritesStore,
            historyStore: historyStore,
            accessibilityState: accessibilityState
          )
          recordingStore.refresh()
        }
    }
  }
}
