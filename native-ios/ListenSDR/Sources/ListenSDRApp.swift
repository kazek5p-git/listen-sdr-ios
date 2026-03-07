import SwiftUI

@main
@MainActor
struct ListenSDRApp: App {
  @StateObject private var profileStore = ProfileStore()
  @StateObject private var radioSession = RadioSessionViewModel()
  @StateObject private var presetStore = FrequencyPresetStore()
  private let diagnostics = Diagnostics.sharedStore

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(profileStore)
        .environmentObject(radioSession)
        .environmentObject(presetStore)
        .environmentObject(diagnostics)
    }
  }
}
