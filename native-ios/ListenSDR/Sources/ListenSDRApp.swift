import SwiftUI

@main
@MainActor
struct ListenSDRApp: App {
  @StateObject private var profileStore = ProfileStore()
  @StateObject private var radioSession = RadioSessionViewModel()
  @StateObject private var favoritesStore = FavoritesStore()
  @StateObject private var recordingStore = RecordingStore()
  private let shazam = ShazamRecognitionController.shared
  private let diagnostics = Diagnostics.sharedStore

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(profileStore)
        .environmentObject(radioSession)
        .environmentObject(favoritesStore)
        .environmentObject(recordingStore)
        .environmentObject(shazam)
        .environmentObject(diagnostics)
        .task {
          recordingStore.refresh()
        }
    }
  }
}
