import Foundation
import Combine

enum ConnectionState {
  case disconnected
  case connecting
  case connected
  case failed
}

@MainActor
final class RadioSessionViewModel: ObservableObject {
  @Published private(set) var state: ConnectionState = .disconnected
  @Published private(set) var connectedProfileID: UUID?
  @Published private(set) var statusText: String = "Disconnected"
  @Published private(set) var backendStatusText: String?
  @Published private(set) var lastError: String?
  @Published private(set) var settings: RadioSessionSettings = .default

  private var client: (any SDRBackendClient)?
  private var connectTask: Task<Void, Never>?
  private var statusMonitorTask: Task<Void, Never>?
  private let settingsKey = "ListenSDR.sessionSettings.v1"

  init() {
    settings = loadPersistedSettings()
    settings.tuneStepHz = RadioSessionSettings.normalizedTuneStep(settings.tuneStepHz)
    SharedAudioOutput.engine.setVolume(settings.audioVolume)
    SharedAudioOutput.engine.setMuted(settings.audioMuted)
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
    state = .connecting
    statusText = "Connecting to \(profile.name)..."
    backendStatusText = nil
    lastError = nil

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
    persistSettings()
  }

  func setAudioMuted(_ muted: Bool) {
    settings.audioMuted = muted
    SharedAudioOutput.engine.setMuted(muted)
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
          }
          return
        }

        if let backendStatus = await client.consumeStatusUpdate() {
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.backendStatusText = backendStatus
          }
        }
      }
    }
  }
}
