import SwiftUI

@main
@MainActor
struct ListenSDRApp: App {
  @StateObject private var navigationState = AppNavigationState()
  @StateObject private var profileStore = ProfileStore()
  @StateObject private var radioSession = RadioSessionViewModel()
  @StateObject private var favoritesStore = FavoritesStore()
  @StateObject private var recordingStore = RecordingStore()
  @StateObject private var historyStore = ListeningHistoryStore.shared
  private let shazam = ShazamRecognitionController.shared
  private let diagnostics = Diagnostics.sharedStore

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(profileStore)
        .environmentObject(navigationState)
        .environmentObject(radioSession)
        .environmentObject(favoritesStore)
        .environmentObject(recordingStore)
        .environmentObject(historyStore)
        .environmentObject(shazam)
        .environmentObject(diagnostics)
        .task {
          recordingStore.refresh()
        }
    }
  }
}
