import Foundation

enum PendingShortcutCommandKind: String, Codable {
  case connectLastReceiver
  case openFMDXReceiver
  case toggleMute
  case startRecording
  case stopRecording
}

struct PendingShortcutCommand: Identifiable, Codable {
  let id: UUID
  let kind: PendingShortcutCommandKind
  let createdAt: Date

  init(kind: PendingShortcutCommandKind) {
    id = UUID()
    self.kind = kind
    createdAt = Date()
  }
}

final class AppShortcutCommandCenter {
  static let shared = AppShortcutCommandCenter()

  private let queue = DispatchQueue(label: "ListenSDR.AppShortcutCommandCenter")
  private let defaults = UserDefaults.standard
  private let key = "ListenSDR.pendingShortcutCommands.v1"

  private init() {}

  func enqueue(_ kind: PendingShortcutCommandKind) {
    queue.sync {
      var commands = loadLocked()
      commands.append(PendingShortcutCommand(kind: kind))
      saveLocked(commands)
    }
  }

  @MainActor
  func processPendingCommands(
    navigationState: AppNavigationState,
    profileStore: ProfileStore,
    radioSession: RadioSessionViewModel,
    recordingStore: RecordingStore,
    historyStore: ListeningHistoryStore
  ) {
    let commands = queue.sync { () -> [PendingShortcutCommand] in
      let loaded = loadLocked()
      saveLocked([])
      return loaded
    }

    guard !commands.isEmpty else { return }

    for command in commands {
      execute(
        command,
        navigationState: navigationState,
        profileStore: profileStore,
        radioSession: radioSession,
        recordingStore: recordingStore,
        historyStore: historyStore
      )
    }
  }

  @MainActor
  private func execute(
    _ command: PendingShortcutCommand,
    navigationState: AppNavigationState,
    profileStore: ProfileStore,
    radioSession: RadioSessionViewModel,
    recordingStore: RecordingStore,
    historyStore: ListeningHistoryStore
  ) {
    switch command.kind {
    case .connectLastReceiver:
      guard let profile = historyStore.recentReceivers.first?.makeProfile() ?? profileStore.selectedProfile else {
        Diagnostics.log(severity: .warning, category: "Shortcut", message: "Connect last receiver shortcut ignored: no receiver available")
        return
      }
      connect(profile, openReceiver: true, navigationState: navigationState, profileStore: profileStore, radioSession: radioSession)
      Diagnostics.log(category: "Shortcut", message: "Executed shortcut: connect last receiver")

    case .openFMDXReceiver:
      guard
        let profile = (profileStore.selectedProfile?.backend == .fmDxWebserver ? profileStore.selectedProfile : nil)
          ?? profileStore.firstProfile(where: { $0.backend == .fmDxWebserver })
          ?? historyStore.recentReceivers.first(where: { $0.backend == .fmDxWebserver })?.makeProfile()
      else {
        Diagnostics.log(severity: .warning, category: "Shortcut", message: "Open FM-DX shortcut ignored: no FM-DX receiver available")
        return
      }
      connect(profile, openReceiver: true, navigationState: navigationState, profileStore: profileStore, radioSession: radioSession)
      Diagnostics.log(category: "Shortcut", message: "Executed shortcut: open FM-DX")

    case .toggleMute:
      radioSession.toggleAudioMuted()
      Diagnostics.log(category: "Shortcut", message: "Executed shortcut: toggle mute")

    case .startRecording:
      guard let context = radioSession.currentRecordingContext else {
        Diagnostics.log(severity: .warning, category: "Shortcut", message: "Start recording shortcut ignored: no connected receiver")
        return
      }
      if !recordingStore.isRecording {
        recordingStore.startRecording(
          receiverName: context.receiverName,
          backend: context.backend,
          frequencyHz: context.frequencyHz,
          mode: context.mode
        )
      }
      Diagnostics.log(category: "Shortcut", message: "Executed shortcut: start recording")

    case .stopRecording:
      if recordingStore.isRecording {
        recordingStore.stopRecording()
      }
      Diagnostics.log(category: "Shortcut", message: "Executed shortcut: stop recording")
    }
  }

  @MainActor
  private func connect(
    _ profile: SDRConnectionProfile,
    openReceiver: Bool,
    navigationState: AppNavigationState,
    profileStore: ProfileStore,
    radioSession: RadioSessionViewModel
  ) {
    let storedProfile = profileStore.upsertImportedProfile(profile)
    profileStore.updateSelection(storedProfile.id)
    if openReceiver {
      navigationState.selectedTab = .receiver
    }
    radioSession.connect(to: storedProfile)
  }

  private func loadLocked() -> [PendingShortcutCommand] {
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode([PendingShortcutCommand].self, from: data)) ?? []
  }

  private func saveLocked(_ commands: [PendingShortcutCommand]) {
    if commands.isEmpty {
      defaults.removeObject(forKey: key)
      return
    }
    guard let data = try? JSONEncoder().encode(commands) else { return }
    defaults.set(data, forKey: key)
  }
}
