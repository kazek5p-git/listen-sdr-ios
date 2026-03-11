import AppIntents

struct ConnectLastReceiverIntent: AppIntent {
  static var title: LocalizedStringResource = "shortcuts.connect_last.title"
  static var description = IntentDescription("shortcuts.connect_last.description")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    AppShortcutCommandCenter.shared.enqueue(.connectLastReceiver)
    return .result()
  }
}

struct OpenFMDXIntent: AppIntent {
  static var title: LocalizedStringResource = "shortcuts.open_fmdx.title"
  static var description = IntentDescription("shortcuts.open_fmdx.description")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    AppShortcutCommandCenter.shared.enqueue(.openFMDXReceiver)
    return .result()
  }
}

struct ToggleMuteIntent: AppIntent {
  static var title: LocalizedStringResource = "shortcuts.toggle_mute.title"
  static var description = IntentDescription("shortcuts.toggle_mute.description")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    AppShortcutCommandCenter.shared.enqueue(.toggleMute)
    return .result()
  }
}

struct StartRecordingIntent: AppIntent {
  static var title: LocalizedStringResource = "shortcuts.start_recording.title"
  static var description = IntentDescription("shortcuts.start_recording.description")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    AppShortcutCommandCenter.shared.enqueue(.startRecording)
    return .result()
  }
}

struct StopRecordingIntent: AppIntent {
  static var title: LocalizedStringResource = "shortcuts.stop_recording.title"
  static var description = IntentDescription("shortcuts.stop_recording.description")
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    AppShortcutCommandCenter.shared.enqueue(.stopRecording)
    return .result()
  }
}

struct ListenSDRShortcutsProvider: AppShortcutsProvider {
  static var shortcutTileColor: ShortcutTileColor = .blue

  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ConnectLastReceiverIntent(),
      phrases: [
        "Connect last receiver in \(.applicationName)",
        "Open last receiver in \(.applicationName)"
      ],
      shortTitle: "shortcuts.connect_last.short_title",
      systemImageName: "dot.radiowaves.left.and.right"
    )
    AppShortcut(
      intent: OpenFMDXIntent(),
      phrases: [
        "Open FM-DX in \(.applicationName)",
        "Connect FM-DX in \(.applicationName)"
      ],
      shortTitle: "shortcuts.open_fmdx.short_title",
      systemImageName: "radio"
    )
    AppShortcut(
      intent: ToggleMuteIntent(),
      phrases: [
        "Toggle mute in \(.applicationName)",
        "Mute audio in \(.applicationName)"
      ],
      shortTitle: "shortcuts.toggle_mute.short_title",
      systemImageName: "speaker.slash"
    )
    AppShortcut(
      intent: StartRecordingIntent(),
      phrases: [
        "Start recording in \(.applicationName)"
      ],
      shortTitle: "shortcuts.start_recording.short_title",
      systemImageName: "record.circle"
    )
    AppShortcut(
      intent: StopRecordingIntent(),
      phrases: [
        "Stop recording in \(.applicationName)"
      ],
      shortTitle: "shortcuts.stop_recording.short_title",
      systemImageName: "stop.circle"
    )
  }
}
