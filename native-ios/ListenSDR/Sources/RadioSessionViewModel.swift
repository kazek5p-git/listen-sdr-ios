import Foundation
import Combine
import UIKit

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

enum FMDXFilterProfile: String, CaseIterable, Identifiable {
  case wide
  case balanced
  case dx

  var id: String { rawValue }

  var localizationKey: String {
    switch self {
    case .wide:
      return "fmdx.filter_profile.wide"
    case .balanced:
      return "fmdx.filter_profile.balanced"
    case .dx:
      return "fmdx.filter_profile.dx"
    }
  }

  var eqEnabled: Bool {
    switch self {
    case .wide:
      return false
    case .balanced:
      return false
    case .dx:
      return true
    }
  }

  var imsEnabled: Bool {
    switch self {
    case .wide:
      return true
    case .balanced, .dx:
      return true
    }
  }

  var preferredBandwidthKHz: Int? {
    switch self {
    case .wide:
      return 150
    case .balanced:
      return 84
    case .dx:
      return 56
    }
  }
}

private enum RDSAnnouncementKind {
  case station
  case radioText
  case pi
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
  @Published private(set) var currentKiwiBandName: String?
  @Published private(set) var fmdxTelemetry: FMDXTelemetry?
  @Published private(set) var fmdxCapabilities: FMDXCapabilities = .empty
  @Published private(set) var fmdxServerPresets: [SDRServerBookmark] = []
  @Published private(set) var selectedFMDXAntennaID: String?
  @Published private(set) var selectedFMDXBandwidthID: String?
  @Published private(set) var fmdxTuneWarningText: String?
  @Published private(set) var kiwiTelemetry: KiwiTelemetry?
  @Published private(set) var isScannerRunning = false
  @Published private(set) var scannerStatusText: String?
  @Published var scannerThreshold: Double = -95
  @Published private(set) var hasSavedSettingsSnapshot = false

  private let fmDxDefaultFrequencyHz = 87_500_000
  private let fmDxMinFrequencyHz = 64_000_000
  private let fmDxMaxFrequencyHz = 110_000_000
  private let kiwiDefaultFrequencyHz = 7_050_000
  private let kiwiFrequencyRangeHz: ClosedRange<Int> = 10_000...32_000_000
  private let openWebRXFrequencyRangeHz: ClosedRange<Int> = 100_000...3_000_000_000

  private var client: (any SDRBackendClient)?
  private var connectTask: Task<Void, Never>?
  private var statusMonitorTask: Task<Void, Never>?
  private var scannerTask: Task<Void, Never>?
  private var fmDxTuneDebounceTask: Task<Void, Never>?
  private var fmDxTuneConfirmTask: Task<Void, Never>?
  private var pendingFMDXTuneFrequencyHz: Int?
  private var hasFMDXCapabilitySnapshot = false
  private var activeBackend: SDRBackend?
  private let settingsKey = "ListenSDR.sessionSettings.v1"
  private let nightModeSnapshotKey = "ListenSDR.nightModeSnapshot.v1"
  private let manualSettingsSnapshotKey = "ListenSDR.manualSettingsSnapshot.v1"
  private var nightModeSnapshot: RadioSessionSettings?
  private var manualSettingsSnapshot: RadioSessionSettings?
  private var autoFilterPendingProfile: FMDXFilterProfile?
  private var autoFilterStableSamples = 0
  private var autoFilterLastAppliedAt = Date.distantPast
  private var suppressAutoFilterUntil = Date.distantPast
  private var hasInitialServerTuningSync = false
  private var initialServerTuningSyncDeadline = Date.distantPast
  private var lastRDSAnnouncementText: String?
  private var lastRDSAnnouncementAt = Date.distantPast
  private var lastRDSAnnouncementKind: RDSAnnouncementKind?

  init() {
    settings = loadPersistedSettings()
    if settings.shazamIntegrationEnabled {
      settings.shazamIntegrationEnabled = false
    }
    if settings.autoFilterProfileEnabled {
      settings.autoFilterProfileEnabled = false
    }
    settings.tuneStepHz = RadioSessionSettings.normalizedTuneStep(settings.tuneStepHz)
    settings.scannerDwellSeconds = RadioSessionSettings.clampedScannerDwellSeconds(settings.scannerDwellSeconds)
    settings.scannerHoldSeconds = RadioSessionSettings.clampedScannerHoldSeconds(settings.scannerHoldSeconds)
    settings.fmdxAudioStartupBufferSeconds = RadioSessionSettings.clampedFMDXAudioStartupBufferSeconds(
      settings.fmdxAudioStartupBufferSeconds
    )
    settings.fmdxAudioMaxLatencySeconds = RadioSessionSettings.clampedFMDXAudioMaxLatencySeconds(
      settings.fmdxAudioMaxLatencySeconds,
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds
    )
    settings.fmdxAudioPacketHoldSeconds = RadioSessionSettings.clampedFMDXAudioPacketHoldSeconds(
      settings.fmdxAudioPacketHoldSeconds
    )
    nightModeSnapshot = loadPersistedSnapshot(forKey: nightModeSnapshotKey)
    manualSettingsSnapshot = loadPersistedSnapshot(forKey: manualSettingsSnapshotKey)
    hasSavedSettingsSnapshot = manualSettingsSnapshot != nil
    SharedAudioOutput.engine.setVolume(settings.audioVolume)
    SharedAudioOutput.engine.setMuted(settings.audioMuted)
    FMDXMP3AudioPlayer.shared.setVolume(settings.audioVolume)
    FMDXMP3AudioPlayer.shared.setMuted(settings.audioMuted)
    applyFMDXAudioTuning()
    ShazamRecognitionController.shared.setIntegrationEnabled(false)
    persistSettings()
  }

  var fmdxSupportsAM: Bool {
    fmdxCapabilities.supportsAM
  }

  var fmdxSupportsFilterControls: Bool {
    fmdxCapabilities.supportsFilterControls
  }

  var fmdxSupportsAGCControl: Bool {
    fmdxCapabilities.supportsAGCControl
  }

  var isAwaitingInitialServerTuningSync: Bool {
    isWaitingForInitialServerTuningSync()
  }

  var currentFMDXAudioPreset: FMDXAudioTuningPreset {
    FMDXAudioTuningPreset.matching(
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds,
      maxLatencySeconds: settings.fmdxAudioMaxLatencySeconds,
      packetHoldSeconds: settings.fmdxAudioPacketHoldSeconds
    )
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

    connectTask = Task {
      do {
        if let existingClient = client {
          await existingClient.disconnect()
        }

        let newClient = makeClient(for: profile.backend)
        try await newClient.connect(profile: profile)

        if Task.isCancelled {
          return
        }

        await MainActor.run {
          self.client = newClient
          self.connectedProfileID = profile.id
          self.activeBackend = profile.backend
          NowPlayingMetadataController.shared.setReceiverName(profile.name)
          NowPlayingMetadataController.shared.setTitle(nil)
          self.hasInitialServerTuningSync = false
          self.initialServerTuningSyncDeadline = Date().addingTimeInterval(4.0)
          self.state = .connected
          self.statusText = L10n.text("session.status.connected_to", profile.name)
          self.backendStatusText = (profile.backend == .openWebRX || profile.backend == .kiwiSDR)
            ? L10n.text("session.status.sync_tuning")
            : nil
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
        NowPlayingMetadataController.shared.setReceiverName(nil)
        NowPlayingMetadataController.shared.setTitle(nil)
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

  func tuneStepOptions(for backend: SDRBackend) -> [Int] {
    tuningBandProfile(for: backend).stepOptionsHz
  }

  func startScanner(
    channels: [ScanChannel],
    backend: SDRBackend,
    dwellSeconds: Double? = nil,
    holdSeconds: Double? = nil
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
      let baseDwellSeconds = max(0.4, dwellSeconds ?? settings.scannerDwellSeconds)
      let baseHoldSeconds = max(0.5, holdSeconds ?? settings.scannerHoldSeconds)

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

        let threshold = await MainActor.run { self.scannerThreshold }
        let preTuneSignal = await MainActor.run { self.currentScannerSignal(for: backend) }
        let adaptiveScanner = await MainActor.run { self.settings.adaptiveScannerEnabled }
        let dwellNanos = UInt64(
          adaptiveDwellSeconds(
            baseDwellSeconds,
            adaptive: adaptiveScanner,
            signal: preTuneSignal,
            threshold: threshold
          ) * 1_000_000_000
        )

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
          let holdNanos = UInt64(
            adaptiveHoldSeconds(
              baseHoldSeconds,
              adaptive: adaptiveScanner,
              signal: signal,
              threshold: threshold
            ) * 1_000_000_000
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
    if isWaitingForInitialServerTuningSync() {
      backendStatusText = L10n.text("session.status.sync_tuning")
      return
    }

    let previousFrequencyHz = settings.frequencyHz
    if activeBackend == .fmDxWebserver {
      let roundedToKHz = Int((Double(value) / 1_000.0).rounded()) * 1_000
      settings.frequencyHz = min(max(roundedToKHz, fmDxMinFrequencyHz), fmDxMaxFrequencyHz)
    } else {
      let range = frequencyRange(for: activeBackend)
      settings.frequencyHz = min(max(value, range.lowerBound), range.upperBound)
    }
    clearRecognizedTrackIfTunedAway(from: previousFrequencyHz, to: settings.frequencyHz)
    let tuneStepChanged = syncTuneStepToCurrentBandIfNeeded()
    persistSettings()
    if tuneStepChanged, activeBackend == .openWebRX {
      backendStatusText = openWebRXStatusSummary(frequencyHz: settings.frequencyHz, mode: settings.mode)
    }
    if tuneStepChanged, activeBackend == .kiwiSDR {
      backendStatusText = kiwiStatusSummary(
        frequencyHz: settings.frequencyHz,
        mode: settings.mode,
        reportedBandName: currentKiwiBandName
      )
    }

    guard activeBackend == .fmDxWebserver else {
      applyIfConnected()
      return
    }
    queueFMDXFrequencySend(settings.frequencyHz)
  }

  func setTuneStepHz(_ value: Int) {
    let normalized = RadioSessionSettings.normalizedTuneStep(value)
    let resolved = activeBackend == .fmDxWebserver
      ? normalizeFMDXTuneStepHz(normalized, mode: settings.mode)
      : normalized
    settings.tuneStepHz = resolved
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Tune step set to \(resolved) Hz (requested \(value) Hz)"
    )
  }

  func tune(byStepCount stepCount: Int) {
    let delta = stepCount * settings.tuneStepHz
    setFrequencyHz(settings.frequencyHz + delta)
  }

  func setMode(_ mode: DemodulationMode) {
    if activeBackend == .fmDxWebserver {
      let amUnsupportedWarning = L10n.text("fmdx.band.am_not_supported")
      var resolvedMode: DemodulationMode = (mode == .fm || mode == .am) ? mode : .fm
      if resolvedMode == .am && hasFMDXCapabilitySnapshot && !fmdxCapabilities.supportsAM {
        resolvedMode = .fm
        fmdxTuneWarningText = amUnsupportedWarning
      } else if resolvedMode == .fm && fmdxTuneWarningText == amUnsupportedWarning {
        fmdxTuneWarningText = nil
      }
      settings.mode = resolvedMode
      settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.tuneStepHz, mode: settings.mode)
      persistSettings()
      return
    }
    settings.mode = mode
    _ = syncTuneStepToCurrentBandIfNeeded()
    persistSettings()
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
    NowPlayingMetadataController.shared.setMuted(muted)
    persistSettings()
  }

  func setAGCEnabled(_ enabled: Bool) {
    settings.agcEnabled = enabled
    persistSettings()
    if activeBackend == .fmDxWebserver {
      guard fmdxCapabilities.supportsAGCControl else { return }
      sendFMDXControl(.setFMDXAGC(enabled))
    } else {
      applyIfConnected()
    }
  }

  func setNoiseReductionEnabled(_ enabled: Bool) {
    settings.noiseReductionEnabled = enabled
    markAutoFilterManuallyOverridden()
    persistSettings()
    if activeBackend == .fmDxWebserver {
      guard fmdxCapabilities.supportsFilterControls else { return }
      sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
    } else {
      applyIfConnected()
    }
  }

  func setIMSEnabled(_ enabled: Bool) {
    settings.imsEnabled = enabled
    markAutoFilterManuallyOverridden()
    persistSettings()
    if activeBackend == .fmDxWebserver {
      guard fmdxCapabilities.supportsFilterControls else { return }
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

  func currentFMDXFilterProfile() -> FMDXFilterProfile? {
    let eq = settings.noiseReductionEnabled
    let ims = settings.imsEnabled
    let supportsFilterControls = fmdxCapabilities.supportsFilterControls

    if !supportsFilterControls {
      guard let selected = selectedFMDXBandwidthOption(),
        let bandwidthKHz = parseBandwidthKHz(from: selected)
      else {
        return nil
      }

      if bandwidthKHz <= 64 {
        return .dx
      }
      if bandwidthKHz >= 110 {
        return .wide
      }
      return .balanced
    }

    if !eq && ims {
      return .wide
    }

    if eq && ims,
      let selected = selectedFMDXBandwidthOption(),
      let bandwidthKHz = parseBandwidthKHz(from: selected),
      bandwidthKHz <= 64 {
      return .dx
    }

    guard !eq && ims else { return nil }

    guard let selected = selectedFMDXBandwidthOption(),
      let bandwidthKHz = parseBandwidthKHz(from: selected)
    else {
      return .balanced
    }

    if bandwidthKHz <= 64 {
      return .dx
    }
    if bandwidthKHz >= 110 {
      return .wide
    }
    return .balanced
  }

  func applyFMDXFilterProfile(_ profile: FMDXFilterProfile) {
    markAutoFilterManuallyOverridden()
    applyFMDXFilterProfile(profile, isAutomatic: false)
  }

  private func applyFMDXFilterProfile(_ profile: FMDXFilterProfile, isAutomatic: Bool) {
    guard activeBackend == .fmDxWebserver else { return }

    if fmdxCapabilities.supportsFilterControls {
      settings.noiseReductionEnabled = profile.eqEnabled
      settings.imsEnabled = profile.imsEnabled
    }
    persistSettings()
    if fmdxCapabilities.supportsFilterControls {
      sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
    }
    if isAutomatic {
      autoFilterLastAppliedAt = Date()
    }

    guard let preferredBandwidthKHz = profile.preferredBandwidthKHz,
      let option = preferredFMDXBandwidthOption(near: preferredBandwidthKHz)
    else {
      return
    }

    selectedFMDXBandwidthID = option.id
    sendFMDXControl(.setFMDXBandwidth(value: option.id, legacyValue: option.legacyValue))
  }

  func setSquelchEnabled(_ enabled: Bool) {
    settings.squelchEnabled = enabled
    persistSettings()
    if activeBackend == .fmDxWebserver {
      return
    }
    if activeBackend == .openWebRX {
      applyIfConnected()
      return
    }
    applyIfConnected()
  }

  func setOpenWebRXSquelchLevel(_ value: Int) {
    settings.openWebRXSquelchLevel = RadioSessionSettings.clampedOpenWebRXSquelchLevel(value)
    persistSettings()
    guard activeBackend == .openWebRX else { return }
    sendOpenWebRXSquelchControl()
  }

  func setKiwiSquelchThreshold(_ value: Int) {
    settings.kiwiSquelchThreshold = RadioSessionSettings.clampedKiwiSquelchThreshold(value)
    persistSettings()
    guard activeBackend == .kiwiSDR else { return }
    applyIfConnected()
  }

  func setKiwiWaterfallSpeed(_ value: Int) {
    settings.kiwiWaterfallSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(value)
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallZoom(_ value: Int) {
    settings.kiwiWaterfallZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(value)
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallMinDB(_ value: Int) {
    let clamped = RadioSessionSettings.clampedKiwiWaterfallMinDB(value)
    settings.kiwiWaterfallMinDB = clamped
    if settings.kiwiWaterfallMaxDB <= clamped {
      settings.kiwiWaterfallMaxDB = min(0, clamped + 10)
    }
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallMaxDB(_ value: Int) {
    var clamped = RadioSessionSettings.clampedKiwiWaterfallMaxDB(value)
    if clamped <= settings.kiwiWaterfallMinDB {
      clamped = min(30, settings.kiwiWaterfallMinDB + 10)
    }
    settings.kiwiWaterfallMaxDB = clamped
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setShowRdsErrorCounters(_ enabled: Bool) {
    settings.showRdsErrorCounters = enabled
    persistSettings()
  }

  func setVoiceOverRDSAnnouncementMode(_ mode: VoiceOverRDSAnnouncementMode) {
    settings.voiceOverRDSAnnouncementMode = mode
    lastRDSAnnouncementText = nil
    lastRDSAnnouncementAt = .distantPast
    lastRDSAnnouncementKind = nil
    persistSettings()
  }

  func setVoiceOverRDSAnnouncementsEnabled(_ enabled: Bool) {
    setVoiceOverRDSAnnouncementMode(enabled ? .full : .off)
  }

  func setShazamIntegrationEnabled(_ _: Bool) {
    settings.shazamIntegrationEnabled = false
    persistSettings()
    ShazamRecognitionController.shared.setIntegrationEnabled(false)
  }

  func setAutoFilterProfileEnabled(_ _: Bool) {
    settings.autoFilterProfileEnabled = false
    persistSettings()
    autoFilterPendingProfile = nil
    autoFilterStableSamples = 0
    suppressAutoFilterUntil = Date()
  }

  func setAdaptiveScannerEnabled(_ enabled: Bool) {
    settings.adaptiveScannerEnabled = enabled
    persistSettings()
  }

  func setScannerDwellSeconds(_ value: Double) {
    settings.scannerDwellSeconds = RadioSessionSettings.clampedScannerDwellSeconds(value)
    persistSettings()
  }

  func setScannerHoldSeconds(_ value: Double) {
    settings.scannerHoldSeconds = RadioSessionSettings.clampedScannerHoldSeconds(value)
    persistSettings()
  }

  func setFMDXAudioStartupBufferSeconds(_ value: Double) {
    settings.fmdxAudioStartupBufferSeconds = RadioSessionSettings.clampedFMDXAudioStartupBufferSeconds(value)
    settings.fmdxAudioMaxLatencySeconds = RadioSessionSettings.clampedFMDXAudioMaxLatencySeconds(
      settings.fmdxAudioMaxLatencySeconds,
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds
    )
    persistSettings()
    applyFMDXAudioTuning()
  }

  func setFMDXAudioMaxLatencySeconds(_ value: Double) {
    settings.fmdxAudioMaxLatencySeconds = RadioSessionSettings.clampedFMDXAudioMaxLatencySeconds(
      value,
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds
    )
    persistSettings()
    applyFMDXAudioTuning()
  }

  func setFMDXAudioPacketHoldSeconds(_ value: Double) {
    settings.fmdxAudioPacketHoldSeconds = RadioSessionSettings.clampedFMDXAudioPacketHoldSeconds(value)
    persistSettings()
    applyFMDXAudioTuning()
  }

  func resetFMDXAudioTuning() {
    applyFMDXAudioPreset(.balanced)
  }

  func applyFMDXAudioPreset(_ preset: FMDXAudioTuningPreset) {
    guard let values = preset.tuningValues else { return }
    settings.fmdxAudioStartupBufferSeconds = values.startupBufferSeconds
    settings.fmdxAudioMaxLatencySeconds = values.maxLatencySeconds
    settings.fmdxAudioPacketHoldSeconds = values.packetHoldSeconds
    persistSettings()
    applyFMDXAudioTuning()
  }

  func saveCurrentSettingsSnapshot() {
    var snapshot = settings
    snapshot.dxNightModeEnabled = false
    manualSettingsSnapshot = snapshot
    hasSavedSettingsSnapshot = true
    persistSnapshot(snapshot, forKey: manualSettingsSnapshotKey)
    Diagnostics.log(category: "Session", message: "Settings snapshot saved")
  }

  func restoreSavedSettingsSnapshot() {
    guard let snapshot = manualSettingsSnapshot else { return }
    applySettingsSnapshot(snapshot, includeFrequency: true)
    Diagnostics.log(category: "Session", message: "Settings snapshot restored")
  }

  func setDXNightModeEnabled(_ enabled: Bool) {
    if enabled {
      guard settings.dxNightModeEnabled == false else { return }
      var snapshot = settings
      snapshot.dxNightModeEnabled = false
      nightModeSnapshot = snapshot
      persistSnapshot(snapshot, forKey: nightModeSnapshotKey)
      applyNightDXProfile()
      settings.dxNightModeEnabled = true
      persistSettings()
      Diagnostics.log(category: "Session", message: "Night DX mode enabled")
      return
    }

    guard settings.dxNightModeEnabled else { return }
    settings.dxNightModeEnabled = false
    if let snapshot = nightModeSnapshot {
      applySettingsSnapshot(snapshot, includeFrequency: false)
    } else {
      persistSettings()
      applyCurrentSettingsToConnectedBackend()
    }
    nightModeSnapshot = nil
    clearPersistedSnapshot(forKey: nightModeSnapshotKey)
    Diagnostics.log(category: "Session", message: "Night DX mode disabled")
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
      if fmdxCapabilities.supportsAGCControl {
        sendFMDXControl(.setFMDXAGC(settings.agcEnabled))
      }
      if fmdxCapabilities.supportsFilterControls {
        sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
      }
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
    if isWaitingForInitialServerTuningSync() {
      backendStatusText = L10n.text("session.status.sync_tuning")
      return
    }
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

  private func sendOpenWebRXSquelchControl() {
    guard state == .connected, activeBackend == .openWebRX, let client else { return }
    let level = settings.openWebRXSquelchLevel

    Task {
      do {
        try await client.sendControl(.setOpenWebRXSquelchLevel(level))
      } catch {
        await MainActor.run {
          self.lastError = error.localizedDescription
          self.statusText = L10n.text("session.status.connected_with_setting_error")
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "OpenWebRX squelch control failed: \(error.localizedDescription)"
        )
      }
    }
  }

  private func sendKiwiWaterfallControl() {
    guard state == .connected, activeBackend == .kiwiSDR, let client else { return }
    let speed = settings.kiwiWaterfallSpeed
    let zoom = settings.kiwiWaterfallZoom
    let minDB = settings.kiwiWaterfallMinDB
    let maxDB = settings.kiwiWaterfallMaxDB
    let centerFrequencyHz = settings.frequencyHz

    Task {
      do {
        try await client.sendControl(
          .setKiwiWaterfall(
            speed: speed,
            zoom: zoom,
            minDB: minDB,
            maxDB: maxDB,
            centerFrequencyHz: centerFrequencyHz
          )
        )
      } catch {
        // Some Kiwi servers expose audio-only streams without waterfall socket.
        // In that case keep settings persisted and avoid breaking tuning flow.
        applyIfConnected()
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "Kiwi waterfall control failed, fallback apply used: \(error.localizedDescription)"
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

  private func loadPersistedSnapshot(forKey key: String) -> RadioSessionSettings? {
    guard let raw = UserDefaults.standard.data(forKey: key),
      let decoded = try? JSONDecoder().decode(RadioSessionSettings.self, from: raw) else {
      return nil
    }
    return decoded
  }

  private func persistSnapshot(_ snapshot: RadioSessionSettings, forKey key: String) {
    guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
    UserDefaults.standard.set(encoded, forKey: key)
  }

  private func clearPersistedSnapshot(forKey key: String) {
    UserDefaults.standard.removeObject(forKey: key)
  }

  private func markAutoFilterManuallyOverridden() {
    autoFilterPendingProfile = nil
    autoFilterStableSamples = 0
    suppressAutoFilterUntil = Date().addingTimeInterval(3.0)
  }

  private func applyNightDXProfile() {
    settings.audioVolume = min(settings.audioVolume, 0.42)
    settings.audioMuted = false
    settings.agcEnabled = true
    settings.noiseReductionEnabled = true
    settings.imsEnabled = true
    settings.showRdsErrorCounters = false
    settings.autoFilterProfileEnabled = false
    settings.adaptiveScannerEnabled = true
    settings.scannerDwellSeconds = 1.1
    settings.scannerHoldSeconds = 5.5
    settings.kiwiWaterfallSpeed = 1
    settings.kiwiWaterfallZoom = 0
    if activeBackend == .fmDxWebserver {
      settings.mode = .fm
      settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.tuneStepHz, mode: .fm)
    }
    persistSettings()
    applyCurrentSettingsToConnectedBackend()
  }

  private func applySettingsSnapshot(_ snapshot: RadioSessionSettings, includeFrequency: Bool) {
    let previousFrequency = settings.frequencyHz
    var merged = snapshot
    merged.dxNightModeEnabled = settings.dxNightModeEnabled
    merged.autoFilterProfileEnabled = false
    if !includeFrequency {
      merged.frequencyHz = previousFrequency
    }
    merged.tuneStepHz = RadioSessionSettings.normalizedTuneStep(merged.tuneStepHz)
    merged.scannerDwellSeconds = RadioSessionSettings.clampedScannerDwellSeconds(merged.scannerDwellSeconds)
    merged.scannerHoldSeconds = RadioSessionSettings.clampedScannerHoldSeconds(merged.scannerHoldSeconds)
    merged.fmdxAudioStartupBufferSeconds = RadioSessionSettings.clampedFMDXAudioStartupBufferSeconds(
      merged.fmdxAudioStartupBufferSeconds
    )
    merged.fmdxAudioMaxLatencySeconds = RadioSessionSettings.clampedFMDXAudioMaxLatencySeconds(
      merged.fmdxAudioMaxLatencySeconds,
      startupBufferSeconds: merged.fmdxAudioStartupBufferSeconds
    )
    merged.fmdxAudioPacketHoldSeconds = RadioSessionSettings.clampedFMDXAudioPacketHoldSeconds(
      merged.fmdxAudioPacketHoldSeconds
    )
    settings = merged
    if let backend = activeBackend {
      normalizeSettingsForBackendBeforeConnect(backend)
    } else {
      persistSettings()
    }
    applyCurrentSettingsToConnectedBackend()
  }

  private func applyCurrentSettingsToConnectedBackend() {
    SharedAudioOutput.engine.setVolume(settings.audioVolume)
    SharedAudioOutput.engine.setMuted(settings.audioMuted)
    FMDXMP3AudioPlayer.shared.setVolume(settings.audioVolume)
    FMDXMP3AudioPlayer.shared.setMuted(settings.audioMuted)
    applyFMDXAudioTuning()

    if activeBackend == .fmDxWebserver {
      queueFMDXFrequencySend(settings.frequencyHz)
      if fmdxCapabilities.supportsAGCControl {
        sendFMDXControl(.setFMDXAGC(settings.agcEnabled))
      }
      if fmdxCapabilities.supportsFilterControls {
        sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
      }
      if let profile = currentFMDXFilterProfile() {
        applyFMDXFilterProfile(profile, isAutomatic: true)
      }
      return
    }
    applyIfConnected()
  }

  private func normalizeSettingsForBackendBeforeConnect(_ backend: SDRBackend) {
    var changed = false

    let clampedDwell = RadioSessionSettings.clampedScannerDwellSeconds(settings.scannerDwellSeconds)
    if settings.scannerDwellSeconds != clampedDwell {
      settings.scannerDwellSeconds = clampedDwell
      changed = true
    }
    let clampedHold = RadioSessionSettings.clampedScannerHoldSeconds(settings.scannerHoldSeconds)
    if settings.scannerHoldSeconds != clampedHold {
      settings.scannerHoldSeconds = clampedHold
      changed = true
    }
    let clampedFMDXStartupBuffer = RadioSessionSettings.clampedFMDXAudioStartupBufferSeconds(
      settings.fmdxAudioStartupBufferSeconds
    )
    if settings.fmdxAudioStartupBufferSeconds != clampedFMDXStartupBuffer {
      settings.fmdxAudioStartupBufferSeconds = clampedFMDXStartupBuffer
      changed = true
    }
    let clampedFMDXMaxLatency = RadioSessionSettings.clampedFMDXAudioMaxLatencySeconds(
      settings.fmdxAudioMaxLatencySeconds,
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds
    )
    if settings.fmdxAudioMaxLatencySeconds != clampedFMDXMaxLatency {
      settings.fmdxAudioMaxLatencySeconds = clampedFMDXMaxLatency
      changed = true
    }
    let clampedFMDXPacketHold = RadioSessionSettings.clampedFMDXAudioPacketHoldSeconds(
      settings.fmdxAudioPacketHoldSeconds
    )
    if settings.fmdxAudioPacketHoldSeconds != clampedFMDXPacketHold {
      settings.fmdxAudioPacketHoldSeconds = clampedFMDXPacketHold
      changed = true
    }

    switch backend {
    case .fmDxWebserver:
      if settings.mode != .fm && settings.mode != .am {
        settings.mode = .fm
        changed = true
      }

      let normalizedStep = normalizeFMDXTuneStepHz(settings.tuneStepHz, mode: settings.mode)
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

    case .kiwiSDR:
      if !kiwiFrequencyRangeHz.contains(settings.frequencyHz) {
        settings.frequencyHz = kiwiDefaultFrequencyHz
        changed = true
      }

      let kiwiThreshold = RadioSessionSettings.clampedKiwiSquelchThreshold(settings.kiwiSquelchThreshold)
      if settings.kiwiSquelchThreshold != kiwiThreshold {
        settings.kiwiSquelchThreshold = kiwiThreshold
        changed = true
      }

      let kiwiSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(settings.kiwiWaterfallSpeed)
      if settings.kiwiWaterfallSpeed != kiwiSpeed {
        settings.kiwiWaterfallSpeed = kiwiSpeed
        changed = true
      }

      let kiwiZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(settings.kiwiWaterfallZoom)
      if settings.kiwiWaterfallZoom != kiwiZoom {
        settings.kiwiWaterfallZoom = kiwiZoom
        changed = true
      }

      let kiwiMinDB = RadioSessionSettings.clampedKiwiWaterfallMinDB(settings.kiwiWaterfallMinDB)
      if settings.kiwiWaterfallMinDB != kiwiMinDB {
        settings.kiwiWaterfallMinDB = kiwiMinDB
        changed = true
      }

      var kiwiMaxDB = RadioSessionSettings.clampedKiwiWaterfallMaxDB(settings.kiwiWaterfallMaxDB)
      if kiwiMaxDB <= settings.kiwiWaterfallMinDB {
        kiwiMaxDB = min(30, settings.kiwiWaterfallMinDB + 10)
      }
      if settings.kiwiWaterfallMaxDB != kiwiMaxDB {
        settings.kiwiWaterfallMaxDB = kiwiMaxDB
        changed = true
      }

    case .openWebRX:
      let clamped = min(max(settings.frequencyHz, openWebRXFrequencyRangeHz.lowerBound), openWebRXFrequencyRangeHz.upperBound)
      if settings.frequencyHz != clamped {
        settings.frequencyHz = clamped
        changed = true
      }

      let openWebRXSquelchLevel = RadioSessionSettings.clampedOpenWebRXSquelchLevel(settings.openWebRXSquelchLevel)
      if settings.openWebRXSquelchLevel != openWebRXSquelchLevel {
        settings.openWebRXSquelchLevel = openWebRXSquelchLevel
        changed = true
      }
    }

    if changed {
      persistSettings()
    }
  }

  private func applyFMDXAudioTuning() {
    FMDXMP3AudioPlayer.shared.setPlaybackTuning(
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds,
      maxLatencySeconds: settings.fmdxAudioMaxLatencySeconds,
      packetHoldSeconds: settings.fmdxAudioPacketHoldSeconds
    )
  }

  private func normalizeFMDXTuneStepHz(_ value: Int, mode: DemodulationMode) -> Int {
    let profile = BandTuningProfiles.resolve(
      for: BandTuningContext(
        backend: .fmDxWebserver,
        frequencyHz: settings.frequencyHz,
        mode: mode,
        bandName: nil,
        bandTags: []
      )
    )
    return profile.stepOptionsHz.min(by: { abs($0 - value) < abs($1 - value) }) ?? profile.defaultStepHz
  }

  private func normalizeFMDXFrequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    let roundedToKHz = Int((Double(hz) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, fmDxMinFrequencyHz), fmDxMaxFrequencyHz)
  }

  private func frequencyRange(for backend: SDRBackend?) -> ClosedRange<Int> {
    switch backend {
    case .fmDxWebserver:
      return fmDxMinFrequencyHz...fmDxMaxFrequencyHz
    case .kiwiSDR:
      return kiwiFrequencyRangeHz
    case .openWebRX, .none:
      return openWebRXFrequencyRangeHz
    }
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

  private func selectedFMDXBandwidthOption() -> FMDXControlOption? {
    if let selectedFMDXBandwidthID,
      let selected = fmdxCapabilities.bandwidths.first(where: { $0.id == selectedFMDXBandwidthID }) {
      return selected
    }
    return fmdxCapabilities.bandwidths.first
  }

  private func preferredFMDXBandwidthOption(near targetKHz: Int) -> FMDXControlOption? {
    let parsedOptions = fmdxCapabilities.bandwidths.compactMap { option -> (FMDXControlOption, Int)? in
      guard let bandwidthKHz = parseBandwidthKHz(from: option) else { return nil }
      return (option, bandwidthKHz)
    }

    guard !parsedOptions.isEmpty else { return nil }
    return parsedOptions
      .min(by: { abs($0.1 - targetKHz) < abs($1.1 - targetKHz) })?
      .0
  }

  private func parseBandwidthKHz(from option: FMDXControlOption) -> Int? {
    let normalized = option.label
      .lowercased()
      .replacingOccurrences(of: ",", with: ".")
    guard let value = parseFirstDouble(in: normalized) else { return nil }

    if normalized.contains("mhz") {
      return Int((value * 1_000.0).rounded())
    }
    if normalized.contains("khz") || normalized.contains("k") {
      return Int(value.rounded())
    }
    if value > 1_000 {
      return Int((value / 1_000.0).rounded())
    }
    return Int(value.rounded())
  }

  private func parseFirstDouble(in text: String) -> Double? {
    guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)"#, options: []) else {
      return nil
    }
    let nsText = text as NSString
    guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else {
      return nil
    }
    let token = nsText.substring(with: match.range(at: 1))
    return Double(token)
  }

  private func parseFMDXToggleState(_ raw: String?) -> Bool? {
    guard let raw else { return nil }
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["1", "on", "true", "enabled", "yes", "auto", "agc"].contains(normalized) {
      return true
    }
    if ["0", "off", "false", "disabled", "no", "manual", "man"].contains(normalized) {
      return false
    }
    return nil
  }

  private func evaluateAutoFMDXFilterProfile(using telemetry: FMDXTelemetry) {
    guard settings.autoFilterProfileEnabled else { return }
    guard activeBackend == .fmDxWebserver else { return }
    guard state == .connected else { return }
    guard Date() >= suppressAutoFilterUntil else { return }
    guard let signal = telemetry.signal else { return }

    let candidate: FMDXFilterProfile
    switch signal {
    case ..<22:
      candidate = .dx
    case 22..<40:
      candidate = .balanced
    default:
      candidate = .wide
    }

    if autoFilterPendingProfile == candidate {
      autoFilterStableSamples += 1
    } else {
      autoFilterPendingProfile = candidate
      autoFilterStableSamples = 1
      return
    }

    guard autoFilterStableSamples >= 3 else { return }
    guard Date().timeIntervalSince(autoFilterLastAppliedAt) >= 2.5 else { return }
    if currentFMDXFilterProfile() == candidate {
      return
    }

    applyFMDXFilterProfile(candidate, isAutomatic: true)
    Diagnostics.log(
      category: "FM-DX",
      message: "Auto filter profile applied: \(candidate.rawValue) (signal \(String(format: "%.1f", signal)) dBf)"
    )
  }

  private func startStatusMonitor(
    profileName: String,
    profileID: UUID,
    client: any SDRBackendClient
  ) {
    statusMonitorTask?.cancel()

    statusMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_300_000_000)
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

        var telemetryEvents: [BackendTelemetryEvent] = []
        while let telemetryEvent = await client.consumeTelemetryUpdate() {
          telemetryEvents.append(telemetryEvent)
        }
        if !telemetryEvents.isEmpty {
          await MainActor.run {
            guard self.connectedProfileID == profileID else { return }
            for telemetryEvent in telemetryEvents {
              self.apply(telemetryEvent: telemetryEvent)
            }
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
      if syncTuneStepToCurrentBandIfNeeded() {
        persistSettings()
      }
      if activeBackend == .openWebRX {
        backendStatusText = openWebRXStatusSummary(frequencyHz: settings.frequencyHz, mode: settings.mode)
      }

    case .openWebRXTuning(let frequencyHz, let mode):
      hasInitialServerTuningSync = true
      NowPlayingMetadataController.shared.setTitle(nil)
      var changed = false
      let clamped = min(max(frequencyHz, openWebRXFrequencyRangeHz.lowerBound), openWebRXFrequencyRangeHz.upperBound)
      if settings.frequencyHz != clamped {
        clearRecognizedTrackIfTunedAway(from: settings.frequencyHz, to: clamped)
        settings.frequencyHz = clamped
        changed = true
      }
      if let mode, settings.mode != mode {
        settings.mode = mode
        changed = true
      }
      if syncTuneStepToCurrentBandIfNeeded() {
        changed = true
      }
      if changed {
        persistSettings()
      }
      backendStatusText = openWebRXStatusSummary(frequencyHz: clamped, mode: mode)

    case .kiwiTuning(let frequencyHz, let mode, let bandName):
      hasInitialServerTuningSync = true
      NowPlayingMetadataController.shared.setTitle(nil)
      var changed = false
      let clamped = min(max(frequencyHz, kiwiFrequencyRangeHz.lowerBound), kiwiFrequencyRangeHz.upperBound)
      if settings.frequencyHz != clamped {
        clearRecognizedTrackIfTunedAway(from: settings.frequencyHz, to: clamped)
        settings.frequencyHz = clamped
        changed = true
      }
      if let mode, settings.mode != mode {
        settings.mode = mode
        changed = true
      }
      currentKiwiBandName = normalizedBandName(bandName)
      if syncTuneStepToCurrentBandIfNeeded() {
        changed = true
      }
      if changed {
        persistSettings()
      }
      backendStatusText = kiwiStatusSummary(frequencyHz: clamped, mode: mode, reportedBandName: bandName)

    case .fmdxCapabilities(let capabilities):
      fmdxCapabilities = capabilities
      hasFMDXCapabilitySnapshot = true
      if settings.mode == .am && !capabilities.supportsAM {
        settings.mode = .fm
        settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.tuneStepHz, mode: .fm)
        fmdxTuneWarningText = L10n.text("fmdx.band.am_not_supported")
        persistSettings()
      }
      if activeBackend == .fmDxWebserver, state == .connected {
        applyCurrentSettingsToConnectedBackend()
      }

    case .fmdxPresets(let presets):
      fmdxServerPresets = presets
      if activeBackend == .fmDxWebserver {
        serverBookmarks = presets
      }

    case .fmdx(let telemetry):
      let previousTelemetry = fmdxTelemetry
      fmdxTelemetry = telemetry
      NowPlayingMetadataController.shared.setTitle(nowPlayingTitle(for: telemetry))
      var changedSettings = false
      if let antenna = telemetry.antenna, !antenna.isEmpty {
        selectedFMDXAntennaID = antenna
      }
      if let bandwidth = telemetry.bandwidth, !bandwidth.isEmpty {
        selectedFMDXBandwidthID = resolveFMDXBandwidthSelectionID(from: bandwidth)
      }
      if let agcEnabled = parseFMDXToggleState(telemetry.agc),
        settings.agcEnabled != agcEnabled {
        settings.agcEnabled = agcEnabled
        changedSettings = true
      }
      if let eqEnabled = parseFMDXToggleState(telemetry.eq),
        settings.noiseReductionEnabled != eqEnabled {
        settings.noiseReductionEnabled = eqEnabled
        changedSettings = true
      }
      if let imsEnabled = parseFMDXToggleState(telemetry.ims),
        settings.imsEnabled != imsEnabled {
        settings.imsEnabled = imsEnabled
        changedSettings = true
      }
      if let frequencyMHz = telemetry.frequencyMHz {
        let backendFrequencyHz = normalizeFMDXFrequencyHz(fromMHz: frequencyMHz)
        if let pending = pendingFMDXTuneFrequencyHz,
          abs(backendFrequencyHz - pending) < 1_000 {
          clearFMDXTuneConfirmationState()
        }
        if abs(backendFrequencyHz - settings.frequencyHz) >= 1_000 {
          clearRecognizedTrackIfTunedAway(from: settings.frequencyHz, to: backendFrequencyHz)
          settings.frequencyHz = backendFrequencyHz
          changedSettings = true
        }
      }
      if changedSettings {
        persistSettings()
      }
      announceRDSChangeIfNeeded(previous: previousTelemetry, current: telemetry)
      evaluateAutoFMDXFilterProfile(using: telemetry)

    case .kiwi(let telemetry):
      kiwiTelemetry = telemetry
      NowPlayingMetadataController.shared.setTitle(nil)
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

  private func adaptiveDwellSeconds(
    _ base: Double,
    adaptive: Bool,
    signal: Double?,
    threshold: Double
  ) -> Double {
    guard adaptive else { return base }
    guard let signal else { return max(0.5, base * 0.75) }

    let margin = signal - threshold
    if margin >= 10 {
      return min(6.0, base * 1.45)
    }
    if margin >= 4 {
      return min(6.0, base * 1.15)
    }
    if margin <= -8 {
      return max(0.5, base * 0.58)
    }
    if margin <= -4 {
      return max(0.5, base * 0.72)
    }
    return base
  }

  private func adaptiveHoldSeconds(
    _ base: Double,
    adaptive: Bool,
    signal: Double?,
    threshold: Double
  ) -> Double {
    guard adaptive else { return base }
    guard let signal else { return max(0.5, base * 0.7) }

    let margin = signal - threshold
    if margin >= 12 {
      return min(20.0, base * 2.6)
    }
    if margin >= 6 {
      return min(16.0, base * 1.8)
    }
    if margin <= 2 {
      return max(0.5, base * 0.78)
    }
    return base
  }

  private func openWebRXStatusSummary(frequencyHz: Int, mode: DemodulationMode?) -> String {
    var parts: [String] = [FrequencyFormatter.mhzText(fromHz: frequencyHz)]
    if let mode {
      parts.append(mode.displayName)
    }
    if let band = openWebRXBandEntry(for: frequencyHz) {
      parts.append(band.name)
    }
    return parts.joined(separator: " | ")
  }

  private func kiwiStatusSummary(
    frequencyHz: Int,
    mode: DemodulationMode?,
    reportedBandName: String?
  ) -> String {
    var parts: [String] = [FrequencyFormatter.mhzText(fromHz: frequencyHz)]
    if let mode {
      parts.append(mode.displayName)
    }
    if let normalizedBand = normalizedBandName(reportedBandName), !normalizedBand.isEmpty {
      parts.append(normalizedBand)
    } else if let inferredBand = inferredKiwiBandName(for: frequencyHz) {
      parts.append(inferredBand)
    }
    return parts.joined(separator: " | ")
  }

  private func normalizedBandName(_ name: String?) -> String? {
    guard let name else { return nil }
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func inferredKiwiBandName(for frequencyHz: Int) -> String? {
    switch frequencyHz {
    case 150_000...299_999:
      return "LW"
    case 300_000...2_999_999:
      return "MW"
    case 3_000_000...29_999_999:
      return "SW"
    case 64_000_000...110_000_000:
      return "FM"
    case 30_000_000...299_999_999:
      return "VHF"
    default:
      return nil
    }
  }

  private func resetRuntimeState(for backend: SDRBackend?) {
    _ = backend
    ShazamRecognitionController.shared.cancelRecognition(clearResult: true)
    openWebRXProfiles = []
    selectedOpenWebRXProfileID = nil
    serverBookmarks = []
    openWebRXBandPlan = []
    currentKiwiBandName = nil
    fmdxTelemetry = nil
    fmdxCapabilities = .empty
    hasFMDXCapabilitySnapshot = false
    fmdxServerPresets = []
    selectedFMDXAntennaID = nil
    selectedFMDXBandwidthID = nil
    kiwiTelemetry = nil
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    clearFMDXTuneConfirmationState()
    autoFilterPendingProfile = nil
    autoFilterStableSamples = 0
    suppressAutoFilterUntil = Date.distantPast
    hasInitialServerTuningSync = false
    initialServerTuningSyncDeadline = Date.distantPast
    lastRDSAnnouncementText = nil
    lastRDSAnnouncementAt = Date.distantPast
    lastRDSAnnouncementKind = nil
    if backend != .fmDxWebserver {
      NowPlayingMetadataController.shared.setTitle(nil)
    }
  }

  private func clearRecognizedTrackIfTunedAway(from oldFrequencyHz: Int, to newFrequencyHz: Int) {
    guard oldFrequencyHz != newFrequencyHz else { return }
    NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
  }

  private func nowPlayingTitle(for telemetry: FMDXTelemetry) -> String? {
    let radioText = mergedRDSRadioText(from: telemetry)
    if let radioText {
      return radioText
    }

    if let programService = normalizedRDSValue(telemetry.ps) {
      return programService
    }

    return nil
  }

  private func mergedRDSRadioText(from telemetry: FMDXTelemetry) -> String? {
    let rt0 = normalizedRDSValue(telemetry.rt0)
    let rt1 = normalizedRDSValue(telemetry.rt1)

    switch (rt0, rt1) {
    case let (.some(first), .some(second)):
      if first == second {
        return first
      }
      return "\(first) \(second)"
    case let (.some(first), .none):
      return first
    case let (.none, .some(second)):
      return second
    case (.none, .none):
      return nil
    }
  }

  private func announceRDSChangeIfNeeded(previous: FMDXTelemetry?, current: FMDXTelemetry) {
    guard settings.voiceOverRDSAnnouncementMode != .off else { return }
    guard UIAccessibility.isVoiceOverRunning else { return }
    guard activeBackend == .fmDxWebserver else { return }
    guard state == .connected else { return }

    let now = Date()
    guard let announcement = rdsAnnouncement(previous: previous, current: current) else { return }
    if now.timeIntervalSince(lastRDSAnnouncementAt) < minimumAnnouncementInterval(for: announcement.kind) {
      return
    }
    guard announcement.text != lastRDSAnnouncementText || announcement.kind != lastRDSAnnouncementKind else { return }

    lastRDSAnnouncementText = announcement.text
    lastRDSAnnouncementAt = now
    lastRDSAnnouncementKind = announcement.kind
    UIAccessibility.post(notification: .announcement, argument: announcement.text)
  }

  private func rdsAnnouncement(
    previous: FMDXTelemetry?,
    current: FMDXTelemetry
  ) -> (kind: RDSAnnouncementKind, text: String)? {
    let mode = settings.voiceOverRDSAnnouncementMode
    let previousPS = normalizedRDSValue(previous?.ps)
    let currentPS = normalizedRDSValue(current.ps)
    let previousStation = preferredRDSStationName(from: previous)
    let currentStation = preferredRDSStationName(from: current)

    if currentStation != previousStation, let currentStation {
      return (.station, L10n.text("accessibility.rds_announcement.station", currentStation))
    }
    if currentPS != previousPS, let currentPS, mode == .full {
      return (.station, L10n.text("accessibility.rds_announcement.ps", currentPS))
    }

    guard mode == .full else { return nil }

    let hadPreviousRDS = previousPS != nil
      || normalizedRDSValue(previous?.rt0) != nil
      || normalizedRDSValue(previous?.rt1) != nil
      || normalizedRDSValue(previous?.pi) != nil

    let previousRT = stableRDSRadioText(from: previous)
    let currentRT = stableRDSRadioText(from: current)
    if hadPreviousRDS, currentRT != previousRT, let currentRT {
      return (.radioText, L10n.text("accessibility.rds_announcement.rt", currentRT))
    }

    let previousPI = normalizedRDSValue(previous?.pi)
    let currentPI = normalizedRDSValue(current.pi)
    if hadPreviousRDS, currentPI != previousPI, let currentPI, currentPS == nil {
      return (.pi, L10n.text("accessibility.rds_announcement.pi", currentPI))
    }

    return nil
  }

  private func minimumAnnouncementInterval(for kind: RDSAnnouncementKind) -> TimeInterval {
    switch kind {
    case .station:
      return 1.2
    case .radioText:
      return 4.0
    case .pi:
      return 2.0
    }
  }

  private func preferredRDSStationName(from telemetry: FMDXTelemetry?) -> String? {
    if let station = normalizedRDSValue(telemetry?.txInfo?.station) {
      return station
    }
    return normalizedRDSValue(telemetry?.ps)
  }

  private func stableRDSRadioText(from telemetry: FMDXTelemetry?) -> String? {
    guard let telemetry else { return nil }
    guard let text = mergedRDSRadioText(from: telemetry) else { return nil }

    let normalized = text
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard normalized.count >= 8 else { return nil }
    guard normalized != preferredRDSStationName(from: telemetry) else { return nil }
    return normalized
  }

  private func normalizedRDSValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\u{00a0}", with: " ")
    guard !normalized.isEmpty else { return nil }
    guard normalized != "?" else { return nil }
    return normalized
  }

  private func canPushLocalTuningToServerYet() -> Bool {
    if hasInitialServerTuningSync {
      return true
    }
    return Date() >= initialServerTuningSyncDeadline
  }

  private func isWaitingForInitialServerTuningSync() -> Bool {
    guard state == .connected else { return false }
    guard activeBackend == .openWebRX || activeBackend == .kiwiSDR else { return false }
    return !canPushLocalTuningToServerYet()
  }

  private func tuningBandProfile(for backend: SDRBackend) -> BandTuningProfile {
    BandTuningProfiles.resolve(for: tuningBandContext(for: backend))
  }

  private func tuningBandContext(for backend: SDRBackend) -> BandTuningContext {
    let bandEntry = backend == .openWebRX ? openWebRXBandEntry(for: settings.frequencyHz) : nil
    let inferredKiwiBandName = backend == .kiwiSDR ? (currentKiwiBandName ?? inferredKiwiBandName(for: settings.frequencyHz)) : nil

    return BandTuningContext(
      backend: backend,
      frequencyHz: settings.frequencyHz,
      mode: settings.mode,
      bandName: bandEntry?.name ?? inferredKiwiBandName,
      bandTags: bandEntry?.tags ?? []
    )
  }

  private func openWebRXBandEntry(for frequencyHz: Int) -> SDRBandPlanEntry? {
    openWebRXBandPlan.first(where: { $0.lowerBoundHz...$0.upperBoundHz ~= frequencyHz })
  }

  private func syncTuneStepToCurrentBandIfNeeded() -> Bool {
    guard let backend = activeBackend else { return false }
    let profile = tuningBandProfile(for: backend)
    guard settings.tuneStepHz != profile.defaultStepHz else { return false }
    guard !profile.stepOptionsHz.contains(settings.tuneStepHz) else { return false }
    settings.tuneStepHz = profile.defaultStepHz
    Diagnostics.log(
      category: "Session",
      message: "Tune step auto-adjusted to \(profile.defaultStepHz) Hz for band profile \(profile.id)"
    )
    return true
  }
}
