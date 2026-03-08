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
  @Published private(set) var statusText: String = L10n.text("session.status.disconnected")
  @Published private(set) var backendStatusText: String?
  @Published private(set) var lastError: String?
  @Published private(set) var settings: RadioSessionSettings = .default
  @Published private(set) var openWebRXProfiles: [OpenWebRXProfileOption] = []
  @Published private(set) var selectedOpenWebRXProfileID: String?
  @Published private(set) var serverBookmarks: [SDRServerBookmark] = []
  @Published private(set) var openWebRXBandPlan: [SDRBandPlanEntry] = []
  @Published private(set) var fmdxTelemetry: FMDXTelemetry?
  @Published private(set) var fmdxCapabilities: FMDXCapabilities = .empty
  @Published private(set) var selectedFMDXAntennaID: String?
  @Published private(set) var selectedFMDXBandwidthID: String?
  @Published private(set) var fmdxTuneWarningText: String?
  @Published private(set) var kiwiTelemetry: KiwiTelemetry?
  @Published private(set) var isScannerRunning = false
  @Published private(set) var scannerStatusText: String?
  @Published var scannerThreshold: Double = -95

  private let fmDxDefaultFrequencyHz = 87_500_000
  private let fmDxMinFrequencyHz = 64_000_000
  private let fmDxMaxFrequencyHz = 110_000_000
  private let fmDxTuneStepOptionsHz = [50_000, 100_000, 200_000]
  private let fmDxDefaultTuneStepHz = 100_000

  private var client: (any SDRBackendClient)?
  private var connectTask: Task<Void, Never>?
  private var statusMonitorTask: Task<Void, Never>?
  private var scannerTask: Task<Void, Never>?
  private var fmDxTuneDebounceTask: Task<Void, Never>?
  private var fmDxTuneConfirmTask: Task<Void, Never>?
  private var pendingFMDXTuneFrequencyHz: Int?
  private var activeBackend: SDRBackend?
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
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    fmDxTuneConfirmTask?.cancel()
    fmDxTuneConfirmTask = nil
    pendingFMDXTuneFrequencyHz = nil
    isScannerRunning = false
    scannerStatusText = nil
    state = .connecting
    statusText = L10n.text("session.status.connecting_to", profile.name)
    backendStatusText = nil
    lastError = nil
    resetRuntimeState(for: profile.backend)
    scannerThreshold = defaultScannerThreshold(for: profile.backend)
    activeBackend = nil
    normalizeSettingsForBackendBeforeConnect(profile.backend)

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
          self.activeBackend = profile.backend
          self.state = .connected
          self.statusText = L10n.text("session.status.connected_to", profile.name)
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
          self.activeBackend = nil
          self.state = .failed
          self.statusText = L10n.text("session.status.connection_failed")
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
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    fmDxTuneConfirmTask?.cancel()
    fmDxTuneConfirmTask = nil
    pendingFMDXTuneFrequencyHz = nil

    Diagnostics.log(category: "Session", message: "Disconnect requested")

    Task {
      if let client {
        await client.disconnect()
      }

      await MainActor.run {
        self.client = nil
        self.connectedProfileID = nil
        self.activeBackend = nil
        self.state = .disconnected
        self.statusText = L10n.text("session.status.disconnected")
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
    scannerStatusText = L10n.text("scanner.started", channels.count)
    Diagnostics.log(
      category: "Scanner",
      message: "Scanner started on \(backend.displayName) with \(channels.count) channels"
    )

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
          self.scannerStatusText = L10n.text(
            "scanner.scanning",
            channel.name,
            FrequencyFormatter.mhzText(fromHz: channel.frequencyHz)
          )
        }

        try? await Task.sleep(nanoseconds: dwellNanos)
        if Task.isCancelled { break }

        if backend == .fmDxWebserver {
          var locked = await MainActor.run { self.isFMDXTuned(to: channel.frequencyHz) }
          if !locked {
            // FM-DX telemetry can lag briefly after tune command.
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { break }
            locked = await MainActor.run { self.isFMDXTuned(to: channel.frequencyHz) }
          }

          if !locked {
            index = (index + 1) % channels.count
            continue
          }
        }

        let threshold = await MainActor.run { self.scannerThreshold }
        let signal = await MainActor.run { self.currentScannerSignal(for: backend) }
        if let signal, signal >= threshold {
          await MainActor.run {
            self.scannerStatusText = L10n.text(
              "scanner.signal_found",
              channel.name,
              signal,
              self.scannerSignalUnit(for: backend)
            )
          }
          Diagnostics.log(
            category: "Scanner",
            message: "Signal found on \(channel.name) at \(signal) \(self.scannerSignalUnit(for: backend))"
          )
          try? await Task.sleep(nanoseconds: holdNanos)
          if Task.isCancelled { break }
        }

        index = (index + 1) % channels.count
      }

      await MainActor.run {
        self.isScannerRunning = false
        if self.scannerStatusText?.contains(L10n.text("scanner.signal_found_prefix")) != true {
          self.scannerStatusText = L10n.text("scanner.stopped")
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
    if activeBackend == .fmDxWebserver {
      let roundedToKHz = Int((Double(value) / 1_000.0).rounded()) * 1_000
      settings.frequencyHz = min(max(roundedToKHz, fmDxMinFrequencyHz), fmDxMaxFrequencyHz)
    } else {
      settings.frequencyHz = min(max(value, 100_000), 3_000_000_000)
    }
    persistSettings()

    guard activeBackend == .fmDxWebserver else {
      applyIfConnected()
      return
    }
    queueFMDXFrequencySend(settings.frequencyHz)
  }

  func setTuneStepHz(_ value: Int) {
    let normalized = RadioSessionSettings.normalizedTuneStep(value)
    settings.tuneStepHz = activeBackend == .fmDxWebserver ? normalizeFMDXTuneStepHz(normalized) : normalized
    persistSettings()
  }

  func tune(byStepCount stepCount: Int) {
    let delta = stepCount * settings.tuneStepHz
    setFrequencyHz(settings.frequencyHz + delta)
  }

  func setMode(_ mode: DemodulationMode) {
    settings.mode = mode
    persistSettings()
    if activeBackend == .fmDxWebserver {
      return
    }
    applyIfConnected()
  }

  func setRFGain(_ value: Double) {
    settings.rfGain = min(max(value, 0), 100)
    persistSettings()
    if activeBackend == .fmDxWebserver {
      return
    }
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
    if activeBackend == .fmDxWebserver {
      sendFMDXControl(.setFMDXAGC(enabled))
    } else {
      applyIfConnected()
    }
  }

  func setNoiseReductionEnabled(_ enabled: Bool) {
    settings.noiseReductionEnabled = enabled
    persistSettings()
    if activeBackend == .fmDxWebserver {
      sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
    } else {
      applyIfConnected()
    }
  }

  func setIMSEnabled(_ enabled: Bool) {
    settings.imsEnabled = enabled
    persistSettings()
    if activeBackend == .fmDxWebserver {
      sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
    } else {
      applyIfConnected()
    }
  }

  func setFMDXForcedStereoEnabled(_ enabled: Bool) {
    guard activeBackend == .fmDxWebserver else { return }
    sendFMDXControl(.setFMDXForcedStereo(enabled))
  }

  func setFMDXAntenna(_ id: String) {
    guard activeBackend == .fmDxWebserver else { return }
    selectedFMDXAntennaID = id
    sendFMDXControl(.setFMDXAntenna(id))
  }

  func setFMDXBandwidth(_ option: FMDXControlOption) {
    guard activeBackend == .fmDxWebserver else { return }
    selectedFMDXBandwidthID = option.id
    sendFMDXControl(.setFMDXBandwidth(value: option.id, legacyValue: option.legacyValue))
  }

  func setSquelchEnabled(_ enabled: Bool) {
    settings.squelchEnabled = enabled
    persistSettings()
    if activeBackend == .fmDxWebserver {
      return
    }
    applyIfConnected()
  }

  func resetDSPSettings() {
    settings.mode = .am
    settings.rfGain = RadioSessionSettings.default.rfGain
    settings.agcEnabled = RadioSessionSettings.default.agcEnabled
    settings.imsEnabled = RadioSessionSettings.default.imsEnabled
    settings.noiseReductionEnabled = RadioSessionSettings.default.noiseReductionEnabled
    settings.squelchEnabled = RadioSessionSettings.default.squelchEnabled
    persistSettings()
    if activeBackend == .fmDxWebserver {
      sendFMDXControl(.setFMDXAGC(settings.agcEnabled))
      sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
    } else {
      applyIfConnected()
    }

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
          self.statusText = L10n.text("session.status.connected_with_setting_error")
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "Apply settings failed: \(error.localizedDescription)"
        )
      }
    }
  }

  private func sendFMDXControl(_ command: BackendControlCommand) {
    guard state == .connected, activeBackend == .fmDxWebserver, let client else { return }

    Task {
      do {
        try await client.sendControl(command)
      } catch {
        await MainActor.run {
          self.lastError = error.localizedDescription
          self.statusText = L10n.text("session.status.connected_with_setting_error")
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "FM-DX control failed: \(error.localizedDescription)"
        )
      }
    }
  }

  private func queueFMDXFrequencySend(_ frequencyHz: Int) {
    guard state == .connected, activeBackend == .fmDxWebserver else { return }

    fmDxTuneDebounceTask?.cancel()
    let target = frequencyHz
    fmDxTuneDebounceTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 180_000_000)
      if Task.isCancelled { return }
      await MainActor.run {
        self?.sendFMDXFrequencyNow(target)
      }
    }
  }

  private func sendFMDXFrequencyNow(_ frequencyHz: Int) {
    pendingFMDXTuneFrequencyHz = frequencyHz
    fmdxTuneWarningText = nil
    sendFMDXControl(.setFMDXFrequencyHz(frequencyHz))
    scheduleFMDXTuneConfirmation(for: frequencyHz)
  }

  private func scheduleFMDXTuneConfirmation(for frequencyHz: Int) {
    fmDxTuneConfirmTask?.cancel()
    fmDxTuneConfirmTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_700_000_000)
      if Task.isCancelled { return }

      await MainActor.run {
        guard let self else { return }
        guard self.pendingFMDXTuneFrequencyHz == frequencyHz else { return }
        guard self.activeBackend == .fmDxWebserver else { return }

        let requestedText = FrequencyFormatter.mhzText(fromHz: frequencyHz)
        if let actualMHz = self.fmdxTelemetry?.frequencyMHz {
          let actualHz = self.normalizeFMDXFrequencyHz(fromMHz: actualMHz)
          let actualText = FrequencyFormatter.mhzText(fromHz: actualHz)
          if abs(actualHz - frequencyHz) >= 1_000 {
            self.fmdxTuneWarningText = L10n.text("fmdx.tune_warning_mismatch", requestedText, actualText)
          }
        } else {
          self.fmdxTuneWarningText = L10n.text("fmdx.tune_warning_no_confirmation", requestedText)
        }
      }
    }
  }

  private func clearFMDXTuneConfirmationState() {
    pendingFMDXTuneFrequencyHz = nil
    fmDxTuneConfirmTask?.cancel()
    fmDxTuneConfirmTask = nil
    fmdxTuneWarningText = nil
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

  private func normalizeSettingsForBackendBeforeConnect(_ backend: SDRBackend) {
    guard backend == .fmDxWebserver else { return }

    var changed = false

    let normalizedStep = normalizeFMDXTuneStepHz(settings.tuneStepHz)
    if settings.tuneStepHz != normalizedStep {
      settings.tuneStepHz = normalizedStep
      changed = true
    }

    if !(fmDxMinFrequencyHz...fmDxMaxFrequencyHz).contains(settings.frequencyHz) {
      settings.frequencyHz = fmDxDefaultFrequencyHz
      changed = true
    } else {
      let roundedToKHz = Int((Double(settings.frequencyHz) / 1_000.0).rounded()) * 1_000
      if roundedToKHz != settings.frequencyHz {
        settings.frequencyHz = roundedToKHz
        changed = true
      }
    }

    if settings.mode != .fm && settings.mode != .nfm {
      settings.mode = .fm
      changed = true
    }

    if changed {
      persistSettings()
    }
  }

  private func normalizeFMDXTuneStepHz(_ value: Int) -> Int {
    fmDxTuneStepOptionsHz.min(by: { abs($0 - value) < abs($1 - value) }) ?? fmDxDefaultTuneStepHz
  }

  private func normalizeFMDXFrequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    let roundedToKHz = Int((Double(hz) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, fmDxMinFrequencyHz), fmDxMaxFrequencyHz)
  }

  private func resolveFMDXBandwidthSelectionID(from rawValue: String) -> String {
    if fmdxCapabilities.bandwidths.contains(where: { $0.id == rawValue }) {
      return rawValue
    }
    if let match = fmdxCapabilities.bandwidths.first(where: { $0.legacyValue == rawValue }) {
      return match.id
    }
    return rawValue
  }

  private func startStatusMonitor(
    profileName: String,
    profileID: UUID,
    client: any SDRBackendClient
  ) {
    statusMonitorTask?.cancel()

    statusMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
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
            self.activeBackend = nil
            self.state = .failed
            self.statusText = L10n.text("session.status.connection_lost")
            self.backendStatusText = nil
            self.lastError = L10n.text("session.error.receiver_closed")
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
            self.activeBackend = nil
            self.state = .failed
            self.statusText = L10n.text("session.status.server_error_on", profileName)
            self.backendStatusText = nil
            self.lastError = backendError
            self.stopScanner()
            self.resetRuntimeState(for: nil)
          }
          return
        }

        var latestBackendStatus: String?
        while let backendStatus = await client.consumeStatusUpdate() {
          latestBackendStatus = backendStatus
        }
        if let latestBackendStatus {
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.backendStatusText = latestBackendStatus
          }
        }

        var latestTelemetryEvent: BackendTelemetryEvent?
        while let telemetryEvent = await client.consumeTelemetryUpdate() {
          latestTelemetryEvent = telemetryEvent
        }
        if let latestTelemetryEvent {
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            self.apply(telemetryEvent: latestTelemetryEvent)
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

    case .fmdxCapabilities(let capabilities):
      fmdxCapabilities = capabilities

    case .fmdx(let telemetry):
      fmdxTelemetry = telemetry
      if let antenna = telemetry.antenna, !antenna.isEmpty {
        selectedFMDXAntennaID = antenna
      }
      if let bandwidth = telemetry.bandwidth, !bandwidth.isEmpty {
        selectedFMDXBandwidthID = resolveFMDXBandwidthSelectionID(from: bandwidth)
      }
      if let frequencyMHz = telemetry.frequencyMHz {
        let backendFrequencyHz = normalizeFMDXFrequencyHz(fromMHz: frequencyMHz)
        if let pending = pendingFMDXTuneFrequencyHz,
          abs(backendFrequencyHz - pending) < 1_000 {
          clearFMDXTuneConfirmationState()
        }
        if abs(backendFrequencyHz - settings.frequencyHz) >= 1_000 {
          settings.frequencyHz = backendFrequencyHz
          persistSettings()
        }
      }

    case .kiwi(let telemetry):
      kiwiTelemetry = telemetry
    }
  }

  private func currentScannerSignal(for backend: SDRBackend?) -> Double? {
    switch backend {
    case .fmDxWebserver:
      return fmdxTelemetry?.signal

    case .kiwiSDR:
      return kiwiTelemetry?.rssiDBm

    case .openWebRX, .none:
      if let signal = fmdxTelemetry?.signal {
        return signal
      }
      return kiwiTelemetry?.rssiDBm
    }
  }

  private func isFMDXTuned(to frequencyHz: Int) -> Bool {
    guard let frequencyMHz = fmdxTelemetry?.frequencyMHz else { return false }
    let reportedHz = normalizeFMDXFrequencyHz(fromMHz: frequencyMHz)
    return abs(reportedHz - frequencyHz) <= 2_000
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
    _ = backend
    openWebRXProfiles = []
    selectedOpenWebRXProfileID = nil
    serverBookmarks = []
    openWebRXBandPlan = []
    fmdxTelemetry = nil
    fmdxCapabilities = .empty
    selectedFMDXAntennaID = nil
    selectedFMDXBandwidthID = nil
    kiwiTelemetry = nil
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    clearFMDXTuneConfirmationState()
  }
}
