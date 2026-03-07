import Foundation
import Combine

enum ConnectionState {
  case disconnected
  case connecting
  case connected
  case failed
}

struct ScanChannel: Identifiable, Hashable {
  let id: String
  let name: String
  let frequencyHz: Int
  let mode: DemodulationMode?
}

@MainActor
final class RadioSessionViewModel: ObservableObject {
  @Published private(set) var state: ConnectionState = .disconnected
  @Published private(set) var connectedProfileID: UUID?
  @Published private(set) var statusText: String = "Disconnected"
  @Published private(set) var backendStatusText: String?
  @Published private(set) var lastError: String?
  @Published private(set) var settings: RadioSessionSettings = .default
  @Published private(set) var openWebRXProfiles: [OpenWebRXProfileOption] = []
  @Published private(set) var selectedOpenWebRXProfileID: String?
  @Published private(set) var serverBookmarks: [SDRServerBookmark] = []
  @Published private(set) var openWebRXBandPlan: [SDRBandPlanEntry] = []
  @Published private(set) var fmdxTelemetry: FMDXTelemetry?
  @Published private(set) var kiwiTelemetry: KiwiTelemetry?
  @Published private(set) var isScannerRunning = false
  @Published private(set) var scannerStatusText: String?
  @Published var scannerThreshold: Double = -95

  private var client: (any SDRBackendClient)?
  private var connectTask: Task<Void, Never>?
  private var statusMonitorTask: Task<Void, Never>?
  private var scannerTask: Task<Void, Never>?
  private let settingsKey = "ListenSDR.sessionSettings.v1"

  init() {
    settings = loadPersistedSettings()
    settings.tuneStepHz = RadioSessionSettings.normalizedTuneStep(settings.tuneStepHz)
    SharedAudioOutput.engine.setVolume(settings.audioVolume)
    SharedAudioOutput.engine.setMuted(settings.audioMuted)
    FMDXMP3AudioPlayer.shared.setVolume(settings.audioVolume)
    FMDXMP3AudioPlayer.shared.setMuted(settings.audioMuted)
  }

  func connect(to profile: SDRConnectionProfile) {
    if state == .connecting {
      return
    }

    Diagnostics.log(
      category: "Session",
      message: "Connect requested for \(profile.name) (\(profile.backend.displayName))"
    )

    connectTask?.cancel()
    statusMonitorTask?.cancel()
    statusMonitorTask = nil
    scannerTask?.cancel()
    scannerTask = nil
    isScannerRunning = false
    scannerStatusText = nil
    state = .connecting
    statusText = "Connecting to \(profile.name)..."
    backendStatusText = nil
    lastError = nil
    resetRuntimeState(for: profile.backend)
    scannerThreshold = defaultScannerThreshold(for: profile.backend)

    connectTask = Task { [settings] in
      do {
        if let existingClient = client {
          await existingClient.disconnect()
        }

        let newClient = makeClient(for: profile.backend)
        try await newClient.connect(profile: profile)
        try await newClient.apply(settings: settings)

        if Task.isCancelled {
          return
        }

        await MainActor.run {
          self.client = newClient
          self.connectedProfileID = profile.id
          self.state = .connected
          self.statusText = "Connected to \(profile.name)"
          self.backendStatusText = nil
          self.lastError = nil
          self.startStatusMonitor(
            profileName: profile.name,
            profileID: profile.id,
            client: newClient
          )
        }
        Diagnostics.log(
          category: "Session",
          message: "Connected to \(profile.name)"
        )
      } catch {
        if Task.isCancelled {
          return
        }

        await MainActor.run {
          self.client = nil
          self.connectedProfileID = nil
          self.state = .failed
          self.statusText = "Connection failed"
          self.backendStatusText = nil
          self.lastError = error.localizedDescription
          self.isScannerRunning = false
          self.scannerStatusText = nil
        }
        Diagnostics.log(
          severity: .error,
          category: "Session",
          message: "Connection failed: \(error.localizedDescription)"
        )
      }
    }
  }

  func disconnect() {
    connectTask?.cancel()
    connectTask = nil
    statusMonitorTask?.cancel()
    statusMonitorTask = nil
    scannerTask?.cancel()
    scannerTask = nil

    Diagnostics.log(category: "Session", message: "Disconnect requested")

    Task {
      if let client {
        await client.disconnect()
      }

      await MainActor.run {
        self.client = nil
        self.connectedProfileID = nil
        self.state = .disconnected
        self.statusText = "Disconnected"
        self.backendStatusText = nil
        self.lastError = nil
        self.isScannerRunning = false
        self.scannerStatusText = nil
        self.resetRuntimeState(for: nil)
      }
      Diagnostics.log(category: "Session", message: "Disconnected")
    }
  }

  func reconnect(to profile: SDRConnectionProfile) {
    Diagnostics.log(
      category: "Session",
      message: "Reconnect requested for \(profile.name)"
    )
    disconnect()

    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      if Task.isCancelled {
        return
      }
      await MainActor.run {
        self?.connect(to: profile)
      }
    }
  }

  func selectOpenWebRXProfile(_ profileID: String) {
    guard state == .connected, let client else { return }

    Task {
      do {
        try await client.sendControl(.selectOpenWebRXProfile(profileID))
        await MainActor.run {
          self.selectedOpenWebRXProfileID = profileID
        }
      } catch {
        await MainActor.run {
          self.lastError = error.localizedDescription
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "OpenWebRX profile selection failed: \(error.localizedDescription)"
        )
      }
    }
  }

  func applyServerBookmark(_ bookmark: SDRServerBookmark) {
    if let mode = bookmark.modulation {
      setMode(mode)
    }
    setFrequencyHz(bookmark.frequencyHz)
  }

  func tuneToBand(_ band: SDRBandPlanEntry, using suggestion: SDRBandFrequency? = nil) {
    let targetHz = suggestion?.frequencyHz ?? band.centerFrequencyHz
    setFrequencyHz(targetHz)

    if let suggestionMode = DemodulationMode.fromOpenWebRX(suggestion?.name.lowercased()) {
      setMode(suggestionMode)
    }
  }

  func scannerSignalUnit(for backend: SDRBackend?) -> String {
    switch backend {
    case .fmDxWebserver:
      return "dBf"
    case .kiwiSDR:
      return "dBm"
    default:
      return "dB"
    }
  }

  func startScanner(
    channels: [ScanChannel],
    backend: SDRBackend,
    dwellSeconds: Double = 1.5,
    holdSeconds: Double = 4.0
  ) {
    guard state == .connected, !channels.isEmpty else { return }

    stopScanner()
    isScannerRunning = true
    scannerStatusText = "Scanner started (\(channels.count) channels)"

    scannerTask = Task {
      var index = 0
      let dwellNanos = UInt64(max(0.4, dwellSeconds) * 1_000_000_000)
      let holdNanos = UInt64(max(0.5, holdSeconds) * 1_000_000_000)

      while !Task.isCancelled {
        let channel = channels[index]

        await MainActor.run {
          if let mode = channel.mode {
            self.setMode(mode)
          }
          self.setFrequencyHz(channel.frequencyHz)
          self.scannerStatusText = "Scanning \(channel.name) (\(FrequencyFormatter.mhzText(fromHz: channel.frequencyHz)))"
        }

        try? await Task.sleep(nanoseconds: dwellNanos)
        if Task.isCancelled { break }

        let threshold = await MainActor.run { self.scannerThreshold }
        let signal = await MainActor.run { self.currentScannerSignal() }
        if let signal, signal >= threshold {
          await MainActor.run {
            self.scannerStatusText = "Signal found on \(channel.name): \(String(format: "%.1f", signal)) \(self.scannerSignalUnit(for: backend))"
          }
          try? await Task.sleep(nanoseconds: holdNanos)
          if Task.isCancelled { break }
        }

        index = (index + 1) % channels.count
      }

      await MainActor.run {
        self.isScannerRunning = false
        if self.scannerStatusText?.contains("Signal found") != true {
          self.scannerStatusText = "Scanner stopped"
        }
      }
    }
  }

  func stopScanner() {
    scannerTask?.cancel()
    scannerTask = nil
    isScannerRunning = false
    scannerStatusText = nil
  }

  func setFrequencyHz(_ value: Int) {
    settings.frequencyHz = min(max(value, 100_000), 3_000_000_000)
    persistSettings()
    applyIfConnected()
  }

  func setTuneStepHz(_ value: Int) {
    settings.tuneStepHz = RadioSessionSettings.normalizedTuneStep(value)
    persistSettings()
  }

  func tune(byStepCount stepCount: Int) {
    let delta = stepCount * settings.tuneStepHz
    setFrequencyHz(settings.frequencyHz + delta)
  }

  func setMode(_ mode: DemodulationMode) {
    settings.mode = mode
    persistSettings()
    applyIfConnected()
  }

  func setRFGain(_ value: Double) {
    settings.rfGain = min(max(value, 0), 100)
    persistSettings()
    applyIfConnected()
  }

  func setAudioVolume(_ value: Double) {
    settings.audioVolume = min(max(value, 0), 1)
    SharedAudioOutput.engine.setVolume(settings.audioVolume)
    FMDXMP3AudioPlayer.shared.setVolume(settings.audioVolume)
    persistSettings()
  }

  func setAudioMuted(_ muted: Bool) {
    settings.audioMuted = muted
    SharedAudioOutput.engine.setMuted(muted)
    FMDXMP3AudioPlayer.shared.setMuted(muted)
    persistSettings()
  }

  func setAGCEnabled(_ enabled: Bool) {
    settings.agcEnabled = enabled
    persistSettings()
    applyIfConnected()
  }

  func setNoiseReductionEnabled(_ enabled: Bool) {
    settings.noiseReductionEnabled = enabled
    persistSettings()
    applyIfConnected()
  }

  func setSquelchEnabled(_ enabled: Bool) {
    settings.squelchEnabled = enabled
    persistSettings()
    applyIfConnected()
  }

  func resetDSPSettings() {
    settings.mode = .am
    settings.rfGain = RadioSessionSettings.default.rfGain
    settings.agcEnabled = RadioSessionSettings.default.agcEnabled
    settings.noiseReductionEnabled = RadioSessionSettings.default.noiseReductionEnabled
    settings.squelchEnabled = RadioSessionSettings.default.squelchEnabled
    persistSettings()
    applyIfConnected()

    Diagnostics.log(
      category: "Session",
      message: "DSP settings reset to defaults"
    )
  }

  private func applyIfConnected() {
    guard state == .connected, let client else { return }
    let snapshot = settings

    Task {
      do {
        try await client.apply(settings: snapshot)
      } catch {
        await MainActor.run {
          self.lastError = error.localizedDescription
          self.statusText = "Connected with setting error"
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "Apply settings failed: \(error.localizedDescription)"
        )
      }
    }
  }

  private func makeClient(for backend: SDRBackend) -> any SDRBackendClient {
    switch backend {
    case .kiwiSDR:
      return KiwiSDRClient()
    case .openWebRX:
      return OpenWebRXClient()
    case .fmDxWebserver:
      return FMDXWebserverClient()
    }
  }

  private func loadPersistedSettings() -> RadioSessionSettings {
    guard let raw = UserDefaults.standard.data(forKey: settingsKey),
      let decoded = try? JSONDecoder().decode(RadioSessionSettings.self, from: raw)
    else {
      return .default
    }
    return decoded
  }

  private func persistSettings() {
    guard let encoded = try? JSONEncoder().encode(settings) else { return }
    UserDefaults.standard.set(encoded, forKey: settingsKey)
  }

  private func startStatusMonitor(
    profileName: String,
    profileID: UUID,
    client: any SDRBackendClient
  ) {
    statusMonitorTask?.cancel()

    statusMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 700_000_000)
        if Task.isCancelled {
          return
        }

        let isAlive = await client.isConnected()
        if !isAlive {
          Diagnostics.log(
            severity: .warning,
            category: "Session",
            message: "Connection lost for \(profileName)"
          )
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.client = nil
            self.connectedProfileID = nil
            self.state = .failed
            self.statusText = "Connection lost"
            self.backendStatusText = nil
            self.lastError = "Receiver closed the connection."
            self.stopScanner()
            self.resetRuntimeState(for: nil)
          }
          return
        }

        if let backendError = await client.consumeServerError() {
          await client.disconnect()
          Diagnostics.log(
            severity: .error,
            category: "Session",
            message: "Server error on \(profileName): \(backendError)"
          )
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.client = nil
            self.connectedProfileID = nil
            self.state = .failed
            self.statusText = "Server error on \(profileName)"
            self.backendStatusText = nil
            self.lastError = backendError
            self.stopScanner()
            self.resetRuntimeState(for: nil)
          }
          return
        }

        if let backendStatus = await client.consumeStatusUpdate() {
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.backendStatusText = backendStatus
          }
        }

        if let telemetryEvent = await client.consumeTelemetryUpdate() {
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.apply(telemetryEvent: telemetryEvent)
          }
        }
      }
    }
  }

  private func apply(telemetryEvent: BackendTelemetryEvent) {
    switch telemetryEvent {
    case .openWebRXProfiles(let profiles, let selectedID):
      openWebRXProfiles = profiles
      selectedOpenWebRXProfileID = selectedID

    case .openWebRXBookmarks(let bookmarks):
      serverBookmarks = bookmarks

    case .openWebRXBandPlan(let bands):
      openWebRXBandPlan = bands

    case .fmdx(let telemetry):
      fmdxTelemetry = telemetry

    case .kiwi(let telemetry):
      kiwiTelemetry = telemetry
    }
  }

  private func currentScannerSignal() -> Double? {
    if let signal = fmdxTelemetry?.signal {
      return signal
    }
    if let signal = kiwiTelemetry?.rssiDBm {
      return signal
    }
    return nil
  }

  private func defaultScannerThreshold(for backend: SDRBackend) -> Double {
    switch backend {
    case .fmDxWebserver:
      return 20
    case .kiwiSDR:
      return -95
    case .openWebRX:
      return -95
    }
  }

  private func resetRuntimeState(for backend: SDRBackend?) {
    switch backend {
    case .openWebRX:
      openWebRXProfiles = []
      selectedOpenWebRXProfileID = nil
      serverBookmarks = []
      openWebRXBandPlan = []
      fmdxTelemetry = nil
      kiwiTelemetry = nil
    case .fmDxWebserver:
      openWebRXProfiles = []
      selectedOpenWebRXProfileID = nil
      serverBookmarks = []
      openWebRXBandPlan = []
      fmdxTelemetry = nil
      kiwiTelemetry = nil
    case .kiwiSDR:
      openWebRXProfiles = []
      selectedOpenWebRXProfileID = nil
      serverBookmarks = []
      openWebRXBandPlan = []
      fmdxTelemetry = nil
      kiwiTelemetry = nil
    case .none:
      openWebRXProfiles = []
      selectedOpenWebRXProfileID = nil
      serverBookmarks = []
      openWebRXBandPlan = []
      fmdxTelemetry = nil
      kiwiTelemetry = nil
    }
  }
}
