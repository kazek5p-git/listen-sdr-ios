import SwiftUI
import UIKit

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("ListenSDR.hasShownFirstConnectionTips.v1") private var hasShownFirstConnectionTips = false
  @EnvironmentObject private var accessibilityState: AppAccessibilityState
  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var recordingStore: RecordingStore
  @EnvironmentObject private var settingsController: SettingsViewController
  @State private var hasAttemptedStartupAutoConnect = false
  @State private var hasEvaluatedStartupTutorial = false
  @State private var isStartupTutorialPresented = false
  @State private var isFirstConnectionTipsPresented = false
  @State private var lastLoggedScenePhase: ScenePhase?

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
    .accessibilityAction(.magicTap) {
      _ = radioSession.performMagicTapAction(recordingStore: recordingStore)
    }
    .sheet(isPresented: $isStartupTutorialPresented) {
      NavigationStack {
        AppTutorialView(isPresentedOnLaunch: true)
      }
      .presentationDragIndicator(.visible)
    }
    .alert(
      L10n.text("connection.first_success.title", fallback: "Receiver connected"),
      isPresented: $isFirstConnectionTipsPresented
    ) {
      Button(L10n.text("connection.first_success.dismiss", fallback: "Continue listening")) {}
    } message: {
      Text(
        L10n.text(
          "connection.first_success.body",
          fallback: "Use Magic Tap for your quick action, keep favorite receivers close at hand, and return to Directory whenever you want to try another receiver."
        )
      )
    }
    .onAppear {
      logScenePhaseTransition(to: scenePhase)
      accessibilityState.selectedTab = navigationState.selectedTab
      radioSession.updateRuntimePolicy(
        isForegroundActive: scenePhase == .active,
        selectedTab: navigationState.selectedTab
      )
      attemptStartupAutoConnectIfNeeded()
      attemptStartupTutorialPresentationIfNeeded()
    }
    .onChange(of: navigationState.selectedTab) { selectedTab in
      accessibilityState.selectedTab = selectedTab
      radioSession.updateRuntimePolicy(
        isForegroundActive: scenePhase == .active,
        selectedTab: selectedTab
      )
    }
    .onChange(of: scenePhase) { phase in
      logScenePhaseTransition(to: phase)
      radioSession.updateRuntimePolicy(
        isForegroundActive: phase == .active,
        selectedTab: navigationState.selectedTab
      )
      attemptStartupAutoConnectIfNeeded()
      attemptStartupTutorialPresentationIfNeeded()
    }
    .onChange(of: radioSession.state) { state in
      guard state == .connected else { return }
      guard !hasShownFirstConnectionTips else { return }
      hasShownFirstConnectionTips = true
      isFirstConnectionTipsPresented = true
    }
    .onChange(of: settingsController.isBound) { _ in
      attemptStartupTutorialPresentationIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
      logApplicationLifecycleEvent("UIApplication will resign active")
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
      logApplicationLifecycleEvent("UIApplication did enter background")
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
      logApplicationLifecycleEvent("UIApplication will enter foreground")
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      logApplicationLifecycleEvent("UIApplication did become active")
    }
  }

  private func attemptStartupAutoConnectIfNeeded() {
    guard !hasAttemptedStartupAutoConnect else { return }
    guard scenePhase == .active else { return }

    hasAttemptedStartupAutoConnect = true

    guard radioSession.settings.autoConnectSelectedProfileOnLaunch else {
      Diagnostics.log(category: "Session", message: "Startup auto-connect skipped: disabled")
      return
    }
    guard let selectedProfile = profileStore.selectedProfile else {
      Diagnostics.log(category: "Session", message: "Startup auto-connect skipped: no selected profile")
      return
    }
    guard radioSession.state != .connecting, radioSession.state != .connected else { return }

    Diagnostics.log(
      category: "Session",
      message: "Startup auto-connect requested for \(selectedProfile.name)"
    )
    radioSession.connect(to: selectedProfile)
  }

  private func attemptStartupTutorialPresentationIfNeeded() {
    guard !hasEvaluatedStartupTutorial else { return }
    guard scenePhase == .active else { return }
    guard settingsController.isBound else { return }

    hasEvaluatedStartupTutorial = true
    isStartupTutorialPresented = settingsController.consumeStartupTutorialAutoPresentationIfNeeded()
  }

  private func logScenePhaseTransition(to phase: ScenePhase) {
    let previousPhase = lastLoggedScenePhase?.diagnosticsLabel ?? "unknown"
    let nextPhase = phase.diagnosticsLabel
    lastLoggedScenePhase = phase
    Diagnostics.log(
      category: "App Lifecycle",
      message: "Scene phase changed: \(previousPhase) -> \(nextPhase) tab=\(navigationState.selectedTab.diagnosticsLabel) connection_state=\(String(describing: radioSession.state)) backend=\(radioSession.currentTuningBackend?.displayName ?? "none")"
    )
  }

  private func logApplicationLifecycleEvent(_ event: String) {
    Diagnostics.log(
      category: "App Lifecycle",
      message: "\(event) tab=\(navigationState.selectedTab.diagnosticsLabel) connection_state=\(String(describing: radioSession.state)) backend=\(radioSession.currentTuningBackend?.displayName ?? "none")"
    )
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

private extension ScenePhase {
  var diagnosticsLabel: String {
    switch self {
    case .active:
      return "active"
    case .inactive:
      return "inactive"
    case .background:
      return "background"
    @unknown default:
      return "unknown"
    }
  }
}

private extension AppTab {
  var diagnosticsLabel: String {
    switch self {
    case .receiver:
      return "receiver"
    case .radios:
      return "radios"
    case .settings:
      return "settings"
    }
  }
}
