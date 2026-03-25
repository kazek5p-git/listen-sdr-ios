import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var accessibilityState: AppAccessibilityState
  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @State private var hasAttemptedStartupAutoConnect = false

  var body: some View {
    TabView(selection: $navigationState.selectedTab) {
      ReceiverView()
        .tag(AppTab.receiver)
        .tabItem {
          Label("Receiver", systemImage: "dial.high")
        }

      RadiosView()
        .tag(AppTab.radios)
        .tabItem {
          Label("Radios", systemImage: "dot.radiowaves.left.and.right")
        }

      SettingsView()
        .tag(AppTab.settings)
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
    }
    .tint(AppTheme.tint)
    .toolbarBackground(.regularMaterial, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .background(AppAccessibilityRotorHost())
    .background(ShortcutCommandHost(scenePhase: scenePhase))
    .appScreenBackground()
    .onAppear {
      accessibilityState.selectedTab = navigationState.selectedTab
      radioSession.updateRuntimePolicy(
        isForegroundActive: scenePhase == .active,
        selectedTab: navigationState.selectedTab
      )
      attemptStartupAutoConnectIfNeeded()
    }
    .onChange(of: navigationState.selectedTab) { selectedTab in
      accessibilityState.selectedTab = selectedTab
      radioSession.updateRuntimePolicy(
        isForegroundActive: scenePhase == .active,
        selectedTab: selectedTab
      )
    }
    .onChange(of: scenePhase) { phase in
      radioSession.updateRuntimePolicy(
        isForegroundActive: phase == .active,
        selectedTab: navigationState.selectedTab
      )
      attemptStartupAutoConnectIfNeeded()
    }
  }

  private func attemptStartupAutoConnectIfNeeded() {
    guard !hasAttemptedStartupAutoConnect else { return }
    guard scenePhase == .active else { return }

    hasAttemptedStartupAutoConnect = true

    guard radioSession.settings.autoConnectSelectedProfileOnLaunch else { return }
    guard let selectedProfile = profileStore.selectedProfile else { return }
    guard radioSession.state != .connecting, radioSession.state != .connected else { return }

    Diagnostics.log(
      category: "Session",
      message: "Startup auto-connect requested for \(selectedProfile.name)"
    )
    radioSession.connect(to: selectedProfile)
  }
}

private struct ShortcutCommandHost: View {
  let scenePhase: ScenePhase

  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var recordingStore: RecordingStore
  @EnvironmentObject private var historyStore: ListeningHistoryStore

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onAppear {
        SystemRemoteCommandController.shared.bind(
          radioSession: radioSession,
          recordingStore: recordingStore
        )
        processPendingShortcuts()
      }
      .onChange(of: scenePhase) { phase in
        if phase == .active {
          processPendingShortcuts()
        }
      }
  }

  private func processPendingShortcuts() {
    AppShortcutCommandCenter.shared.processPendingCommands(
      navigationState: navigationState,
      profileStore: profileStore,
      radioSession: radioSession,
      recordingStore: recordingStore,
      historyStore: historyStore
    )
  }
}
