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

private struct ChannelScannerSignalProbe {
  let signal: Double?
  let rawSignal: Double?
  let state: String
  let filterState: String?

  var wasRejectedByInterferenceFilter: Bool {
    rawSignal != nil && signal == nil && filterState?.hasPrefix("filter=rejected:") == true
  }
}

private struct ChannelScannerInterferenceFilterThresholds {
  let minimumAnalysisBuffers: Int
  let maximumSampleAgeSeconds: Double
  let stationaryEnvelopeLevelStdDB: Double
  let stationaryEnvelopeVariation: Double
  let lowFrequencyHumLevelStdDB: Double
  let lowFrequencyHumZeroCrossingRate: Double
  let lowFrequencyHumSpectralActivity: Double
  let widebandStaticLevelStdDB: Double
  let widebandStaticEnvelopeVariation: Double
  let widebandStaticMinimumZeroCrossingRate: Double
  let widebandStaticMinimumSpectralActivity: Double
}

struct OpenWebRXScannerSquelchPolicy {
  static func effectiveEnabled(storedEnabled: Bool, isLockedByScanner: Bool) -> Bool {
    storedEnabled && !isLockedByScanner
  }

  static func applyingOverride(
    to settings: RadioSessionSettings,
    backend: SDRBackend?,
    isLockedByScanner: Bool
  ) -> RadioSessionSettings {
    guard backend == .openWebRX, isLockedByScanner else { return settings }
    var snapshot = settings
    snapshot.squelchEnabled = false
    return snapshot
  }
}

struct KiwiScannerSquelchPolicy {
  static func effectiveEnabled(storedEnabled: Bool, isLockedByScanner: Bool) -> Bool {
    storedEnabled && !isLockedByScanner
  }

  static func applyingOverride(
    to settings: RadioSessionSettings,
    backend: SDRBackend?,
    isLockedByScanner: Bool
  ) -> RadioSessionSettings {
    guard backend == .kiwiSDR, isLockedByScanner else { return settings }
    var snapshot = settings
    snapshot.squelchEnabled = false
    return snapshot
  }
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

struct SharedAudioDiagnosticsSnapshot {
  let sampleCount: Int
  let peakQueuedBuffers: Int
  let peakSecondsSinceLastEnqueue: Double
}

struct FMDXAudioDiagnosticsSnapshot {
  let sampleCount: Int
  let peakQueuedDurationSeconds: Double
  let peakQueuedBuffers: Int
  let peakOutputGapSeconds: Double
  let latencyTrimEvents: Int
  let queueStarted: Bool
  let currentQueuedDurationSeconds: Double
  let currentQueuedBuffers: Int
  let currentOutputGapSeconds: Double
  let currentLatencyTrimAgeSeconds: Double?
  let currentQualityScore: Int?
  let currentQualityLevel: String?
}

struct AudioSessionDiagnosticsSnapshot {
  let connectedDurationSeconds: Double?
  let automaticReconnectAttempts: Int
  let automaticReconnectSuccesses: Int
  let sharedAudio: SharedAudioDiagnosticsSnapshot
  let fmdxAudio: FMDXAudioDiagnosticsSnapshot?
}

@MainActor
final class RadioSessionViewModel: ObservableObject {
  private enum ActiveScannerKind {
    case channelList
    case fmdxBandRange(restoreFrequencyHz: Int, restoreMode: DemodulationMode)
  }

  private struct FMDXTelemetryCheckpoint {
    let revision: UInt64
    let updatedAt: Date
  }

  @Published private(set) var state: ConnectionState = .disconnected
  @Published private(set) var connectedProfileID: UUID?
  @Published private(set) var statusText: String = L10n.text("session.status.disconnected")
  @Published private(set) var backendStatusText: String?
  @Published private(set) var lastError: String?
  @Published private(set) var settings: RadioSessionSettings = .default
  @Published private(set) var openWebRXProfiles: [OpenWebRXProfileOption] = []
  @Published private(set) var selectedOpenWebRXProfileID: String?
  @Published private(set) var lastOpenWebRXBookmark: SDRServerBookmark?
  @Published private(set) var serverBookmarks: [SDRServerBookmark] = []
  @Published private(set) var openWebRXBandPlan: [SDRBandPlanEntry] = []
  @Published private(set) var currentKiwiBandName: String?
  @Published private(set) var fmdxTelemetry: FMDXTelemetry?
  @Published private(set) var fmdxCapabilities: FMDXCapabilities = .empty
  @Published private(set) var fmdxServerPresets: [SDRServerBookmark] = []
  @Published private(set) var fmdxPresetSourceDescription: String?
  @Published private(set) var selectedFMDXAntennaID: String?
  @Published private(set) var selectedFMDXBandwidthID: String?
  @Published private(set) var fmdxTuneWarningText: String?
  @Published private(set) var kiwiTelemetry: KiwiTelemetry?
  @Published private(set) var isScannerRunning = false
  @Published private(set) var isOpenWebRXSquelchLockedByScanner = false
  @Published private(set) var isKiwiSquelchLockedByScanner = false
  @Published private(set) var scannerStatusText: String?
  @Published var scannerThreshold: Double = -95
  @Published private(set) var channelScannerResults: [ChannelScannerResult] = []
  @Published private(set) var fmdxBandScannerResults: [FMDXBandScanResult] = []
  @Published private(set) var hasSavedSettingsSnapshot = false
  @Published private(set) var audioPresetSuggestion: FMDXAudioPresetSuggestion?
  @Published private(set) var fmdxAudioQualityReport: FMDXAudioQualityReport?
  @Published private(set) var fmdxAudioQualityTrend: [FMDXAudioQualitySample] = []

  private let fmDxAMMinFrequencyHz = 100_000
  private let fmDxAMMaxFrequencyHz = 29_600_000
  private let fmDxFMMinFrequencyHz = 64_000_000
  private let fmDxFMMaxFrequencyHz = 110_000_000
  private let kiwiDefaultFrequencyHz = 7_050_000
  private let kiwiFrequencyRangeHz: ClosedRange<Int> = 10_000...32_000_000
  private let openWebRXFrequencyRangeHz: ClosedRange<Int> = 100_000...3_000_000_000

  private var client: (any SDRBackendClient)?
  private var connectTask: Task<Void, Never>?
  private var statusMonitorTask: Task<Void, Never>?
  private var sessionRecoveryTask: Task<Void, Never>?
  private var scannerTask: Task<Void, Never>?
  private var activeScannerKind: ActiveScannerKind?
  private var activeScannerToken: UUID?
  private var fmDxTuneDebounceTask: Task<Void, Never>?
  private var fmDxTuneConfirmTask: Task<Void, Never>?
  private var kiwiPassbandDebounceTask: Task<Void, Never>?
  private var kiwiNoiseDebounceTask: Task<Void, Never>?
  private var pendingFMDXTuneFrequencyHz: Int?
  private var isShowingFMDXTuneConfirmationWarning = false
  private var pendingFMDXAudioModeIsStereo: Bool?
  private var pendingFMDXAudioModeDeadline = Date.distantPast
  private var hasFMDXCapabilitySnapshot = false
  private var activeBackend: SDRBackend?
  private let settingsKey = "ListenSDR.sessionSettings.v1"
  private let nightModeSnapshotKey = "ListenSDR.nightModeSnapshot.v1"
  private let manualSettingsSnapshotKey = "ListenSDR.manualSettingsSnapshot.v1"
  private let receiverDataCache = ReceiverDataCache.shared
  private let historyStore = ListeningHistoryStore.shared
  private weak var accessibilityState: AppAccessibilityState?
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
  private var lastLoggedAudioSuggestionPreset: FMDXAudioTuningPreset?
  private var lastLoggedFMDXAudioQualityLevel: FMDXAudioQualityLevel?
  private var lastFMDXAudioQualitySampleAt = Date.distantPast
  private let fmdxAudioQualityTrendWindowSeconds: TimeInterval = 60
  private let fmdxAudioQualitySampleIntervalSeconds: TimeInterval = 5
  private var lastFMDXBroadcastFMFrequencyHz = 87_500_000
  private var lastFMDXOIRTFrequencyHz = 70_300_000
  private var lastFMDXLWFrequencyHz = 225_000
  private var lastFMDXMWFrequencyHz = 999_000
  private var lastFMDXSWFrequencyHz = 7_050_000
  private var lastSelectedFMDXFMQuickBand: FMDXQuickBand = .fm
  private var lastSelectedFMDXAMQuickBand: FMDXQuickBand = .mw
  private var channelScannerSignalPreviewActive = false
  private var activeProfileCacheKey: String?
  private var currentConnectedProfile: SDRConnectionProfile?
  private var listeningHistoryCaptureTask: Task<Void, Never>?
  private var recentFrequencyCaptureTask: Task<Void, Never>?
  private var deferredRestoreTask: Task<Void, Never>?
  private var initialTuningFallbackTask: Task<Void, Never>?
  private let autoReconnectDelaySeconds: [UInt64] = [1, 2, 3, 5, 8, 12]
  private let autoReconnectWindowSeconds: TimeInterval = 75
  private let manualReconnectDelayNanoseconds: UInt64 = 120_000_000
  private let deferredRestorePollNanoseconds: UInt64 = 90_000_000
  private var runtimePolicy: BackendRuntimePolicy = .interactive
  private var lastReducedActivityAudioAnalysisAt = Date.distantPast
  private var connectedSince = Date.distantPast
  private var automaticReconnectAttempts = 0
  private var automaticReconnectSuccesses = 0
  private var sharedAudioSampleCount = 0
  private var sharedAudioPeakQueuedBuffers = 0
  private var sharedAudioPeakEnqueueGapSeconds: TimeInterval = 0
  private var lastSharedAudioBufferLogAt = Date.distantPast
  private var lastSharedAudioLoggedQueue = -1
  private var lastSharedAudioLoggedGapSeconds: TimeInterval = -1
  private var lastSharedAudioLoggedRunning = false
  private var lastSharedAudioLoggedStartError: String?
  private var fmdxAudioSampleCount = 0
  private var fmdxPeakQueuedDurationSeconds: TimeInterval = 0
  private var fmdxPeakQueuedBuffers = 0
  private var fmdxPeakOutputGapSeconds: TimeInterval = 0
  private var fmdxLatencyTrimEvents = 0
  private var lastFMDXLatencyTrimLoggedAt = Date.distantPast
  private var lastFMDXBufferLogAt = Date.distantPast
  private var lastFMDXLoggedQueueStarted = false
  private var lastFMDXLoggedQueuedDurationSeconds: TimeInterval = -1
  private var lastFMDXLoggedQueuedBuffers = -1
  private var lastFMDXLoggedOutputGapSeconds: TimeInterval = -1
  private var lastFMDXTelemetryAppliedAt = Date.distantPast
  private var lastFMDXTelemetryRevision: UInt64 = 0
  private let fmdxBandScannerRetryDelayNanoseconds: UInt64 = 140_000_000

  init() {
    settings = loadPersistedSettings()
    if settings.autoFilterProfileEnabled {
      settings.autoFilterProfileEnabled = false
    }
    settings.tuneStepHz = RadioSessionSettings.normalizedTuneStep(settings.tuneStepHz)
    settings.preferredTuneStepHz = RadioSessionSettings.normalizedTuneStep(settings.preferredTuneStepHz)
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
    settings.fmdxCustomScanSettleSeconds = RadioSessionSettings.clampedFMDXCustomScanSettleSeconds(
      settings.fmdxCustomScanSettleSeconds
    )
    settings.fmdxCustomScanMetadataWindowSeconds = RadioSessionSettings.clampedFMDXCustomScanMetadataWindowSeconds(
      settings.fmdxCustomScanMetadataWindowSeconds
    )
    nightModeSnapshot = loadPersistedSnapshot(forKey: nightModeSnapshotKey)
    manualSettingsSnapshot = loadPersistedSnapshot(forKey: manualSettingsSnapshotKey)
    hasSavedSettingsSnapshot = manualSettingsSnapshot != nil
    SharedAudioOutput.engine.setVolume(settings.audioVolume)
    SharedAudioOutput.engine.setMuted(settings.audioMuted)
    SharedAudioOutput.engine.setMixWithOtherAudioApps(settings.mixWithOtherAudioApps)
    FMDXMP3AudioPlayer.shared.setVolume(settings.audioVolume)
    FMDXMP3AudioPlayer.shared.setMuted(settings.audioMuted)
    FMDXMP3AudioPlayer.shared.setMixWithOtherAudioApps(settings.mixWithOtherAudioApps)
    applyFMDXAudioTuning()
    seedFMDXBandMemory()
    persistSettings()
  }

  func bind(accessibilityState: AppAccessibilityState) {
    self.accessibilityState = accessibilityState
  }

  func updateRuntimePolicy(isForegroundActive: Bool, selectedTab: AppTab) {
    let newPolicy: BackendRuntimePolicy
    if isForegroundActive {
      newPolicy = selectedTab == .receiver ? .interactive : .passive
    } else {
      newPolicy = .background
    }

    guard runtimePolicy != newPolicy else { return }
    runtimePolicy = newPolicy
    applyRuntimePolicyToConnectedClient()
  }

  var fmdxSupportsAM: Bool {
    fmdxCapabilities.supportsAM
  }

  var currentFMDXFrequencyRangeHz: ClosedRange<Int> {
    fmdxFrequencyRange(for: settings.mode)
  }

  var availableFMDXQuickBands: [FMDXQuickBand] {
    if settings.mode == .am, fmdxSupportsAM {
      return [.lw, .mw, .sw]
    }
    return [.oirt, .fm]
  }

  var currentFMDXQuickBand: FMDXQuickBand {
    fmdxQuickBand(for: settings.frequencyHz, mode: settings.mode)
  }

  var fmdxSupportsFilterControls: Bool {
    fmdxCapabilities.supportsFilterControls
  }

  var fmdxSupportsAGCControl: Bool {
    fmdxCapabilities.supportsAGCControl
  }

  var effectiveFMDXAudioMode: FMDXAudioMode {
    if let pendingFMDXAudioModeIsStereo, Date() < pendingFMDXAudioModeDeadline {
      return FMDXAudioMode(isStereo: pendingFMDXAudioModeIsStereo)
    }

    return fmdxTelemetry?.audioMode ?? .mono
  }

  var effectiveFMDXAudioModeIsStereo: Bool {
    effectiveFMDXAudioMode.isStereo
  }

  var isAwaitingInitialServerTuningSync: Bool {
    isWaitingForInitialServerTuningSync()
  }

  var effectiveOpenWebRXSquelchEnabled: Bool {
    OpenWebRXScannerSquelchPolicy.effectiveEnabled(
      storedEnabled: settings.squelchEnabled,
      isLockedByScanner: isOpenWebRXSquelchLockedByScanner
    )
  }

  var effectiveKiwiSquelchEnabled: Bool {
    KiwiScannerSquelchPolicy.effectiveEnabled(
      storedEnabled: settings.squelchEnabled,
      isLockedByScanner: isKiwiSquelchLockedByScanner
    )
  }

  var currentTuningBackend: SDRBackend? {
    activeBackend
  }

  var connectedProfileSnapshot: SDRConnectionProfile? {
    currentConnectedProfile
  }

  var currentRecordingContext: AudioRecordingContext? {
    guard state == .connected else { return nil }
    guard let profile = currentConnectedProfile else { return nil }
    let format: AudioRecordingFormat = profile.backend == .fmDxWebserver ? .mp3 : .wav
    return AudioRecordingContext(
      receiverName: profile.name,
      backend: profile.backend,
      frequencyHz: settings.frequencyHz,
      mode: settings.mode,
      format: format
    )
  }

  var currentFMDXAudioPreset: FMDXAudioTuningPreset {
    FMDXAudioTuningPreset.matching(
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds,
      maxLatencySeconds: settings.fmdxAudioMaxLatencySeconds,
      packetHoldSeconds: settings.fmdxAudioPacketHoldSeconds
    )
  }

  var audioDiagnosticsSnapshot: AudioSessionDiagnosticsSnapshot {
    let connectedDurationSeconds = connectedSince == .distantPast
      ? nil
      : Date().timeIntervalSince(connectedSince)
    let sharedAudio = SharedAudioDiagnosticsSnapshot(
      sampleCount: sharedAudioSampleCount,
      peakQueuedBuffers: sharedAudioPeakQueuedBuffers,
      peakSecondsSinceLastEnqueue: sharedAudioPeakEnqueueGapSeconds
    )

    let fmdxAudio: FMDXAudioDiagnosticsSnapshot?
    if activeBackend == .fmDxWebserver || fmdxAudioSampleCount > 0 || fmdxAudioQualityReport != nil {
      let snapshot = FMDXMP3AudioPlayer.shared.runtimeSnapshot()
      fmdxAudio = FMDXAudioDiagnosticsSnapshot(
        sampleCount: fmdxAudioSampleCount,
        peakQueuedDurationSeconds: fmdxPeakQueuedDurationSeconds,
        peakQueuedBuffers: fmdxPeakQueuedBuffers,
        peakOutputGapSeconds: fmdxPeakOutputGapSeconds,
        latencyTrimEvents: fmdxLatencyTrimEvents,
        queueStarted: snapshot.queueStarted,
        currentQueuedDurationSeconds: snapshot.queuedDurationSeconds,
        currentQueuedBuffers: snapshot.queuedBufferCount,
        currentOutputGapSeconds: snapshot.secondsSinceLastAudioOutput,
        currentLatencyTrimAgeSeconds: snapshot.secondsSinceLastLatencyTrim,
        currentQualityScore: fmdxAudioQualityReport?.score,
        currentQualityLevel: fmdxAudioQualityReport?.level.rawValue
      )
    } else {
      fmdxAudio = nil
    }

    return AudioSessionDiagnosticsSnapshot(
      connectedDurationSeconds: connectedDurationSeconds,
      automaticReconnectAttempts: automaticReconnectAttempts,
      automaticReconnectSuccesses: automaticReconnectSuccesses,
      sharedAudio: sharedAudio,
      fmdxAudio: fmdxAudio
    )
  }

  var currentKiwiPassband: ReceiverBandpass {
    settings.kiwiPassband(for: settings.mode, sampleRateHz: kiwiTelemetry?.sampleRateHz)
  }

  var kiwiPassbandLimitHz: Int {
    RadioSessionSettings.kiwiPassbandLimitHz(sampleRateHz: kiwiTelemetry?.sampleRateHz)
  }

  func connect(
    to profile: SDRConnectionProfile,
    restoringFrequencyHz: Int? = nil,
    mode restoringMode: DemodulationMode? = nil
  ) {
    if state == .connecting && sessionRecoveryTask == nil {
      Diagnostics.log(
        category: "Session",
        message: "Superseding in-flight connection with \(profile.name)"
      )
    }

    cancelAutomaticRecovery()

    Diagnostics.log(
      category: "Session",
      message: "Connect requested for \(profile.name) (\(profile.backend.displayName))"
    )

    connectTask?.cancel()
    cancelSessionTransientTasks(resetScannerState: true)
    state = .connecting
    statusText = L10n.text("session.status.connecting_to", profile.name)
    backendStatusText = nil
    lastError = nil
    resetRuntimeState(for: profile.backend)
    scannerThreshold = defaultScannerThreshold(for: profile.backend)
    activeBackend = nil
    currentConnectedProfile = nil
    activeProfileCacheKey = ReceiverIdentity.key(for: profile)
    normalizeSettingsForBackendBeforeConnect(profile.backend)
    hydrateCachedReceiverData(for: profile)
    let runtimePolicySnapshot = runtimePolicy

    connectTask = Task {
      do {
        if let existingClient = client {
          await existingClient.disconnect()
        }

        let newClient = makeClient(for: profile.backend)
        try await newClient.connect(profile: profile)
        await newClient.setRuntimePolicy(runtimePolicySnapshot)

        if Task.isCancelled {
          return
        }

        await MainActor.run {
          self.client = newClient
          self.connectedProfileID = profile.id
          self.activeBackend = profile.backend
          self.activeProfileCacheKey = ReceiverIdentity.key(for: profile)
          self.currentConnectedProfile = profile
          self.historyStore.recordReceiver(profile)
          NowPlayingMetadataController.shared.setReceiverName(profile.name)
          NowPlayingMetadataController.shared.setTitle(nil)
          self.hasInitialServerTuningSync = false
          self.initialServerTuningSyncDeadline = Date().addingTimeInterval(4.0)
          self.state = .connected
          self.connectedSince = Date()
          self.statusText = L10n.text("session.status.connected_to", profile.name)
          self.updateBackendStatusText(
            (profile.backend == .openWebRX || profile.backend == .kiwiSDR)
              ? L10n.text("session.status.sync_tuning")
              : nil
          )
          self.lastError = nil
          self.startStatusMonitor(
            profile: profile,
            client: newClient
          )
          self.scheduleInitialTuningFallbackAfterConnection(profileID: profile.id)
          self.scheduleListeningHistoryCapture()
          self.scheduleRestoreAfterConnection(
            profileID: profile.id,
            frequencyHz: restoringFrequencyHz,
            mode: restoringMode
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
          self.activeProfileCacheKey = nil
          self.currentConnectedProfile = nil
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
    cancelAutomaticRecovery()
    connectTask?.cancel()
    connectTask = nil
    cancelSessionTransientTasks(resetScannerState: true)

    Diagnostics.log(category: "Session", message: "Disconnect requested")

    Task {
      if let client {
        await client.disconnect()
      }

      await MainActor.run {
        self.client = nil
        self.connectedProfileID = nil
        self.activeBackend = nil
        self.activeProfileCacheKey = nil
        self.currentConnectedProfile = nil
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
    listeningHistoryCaptureTask?.cancel()
    listeningHistoryCaptureTask = nil
    recentFrequencyCaptureTask?.cancel()
    recentFrequencyCaptureTask = nil
    deferredRestoreTask?.cancel()
    deferredRestoreTask = nil
    disconnect()

    Task { [weak self] in
      try? await Task.sleep(nanoseconds: self?.manualReconnectDelayNanoseconds ?? 120_000_000)
      if Task.isCancelled {
        return
      }
      await MainActor.run {
        self?.connect(to: profile)
      }
    }
  }

  func selectOpenWebRXProfile(_ profileID: String, for profile: SDRConnectionProfile? = nil) {
    selectedOpenWebRXProfileID = profileID
    let cacheKey = profile.map(ReceiverIdentity.key(for:)) ?? activeProfileCacheKey
    if let cacheKey {
      receiverDataCache.update(receiverID: cacheKey) { cached in
        cached.selectedOpenWebRXProfileID = profileID
      }
    }

    guard state == .connected, activeBackend == .openWebRX, let client else { return }

    Task {
      do {
        try await client.sendControl(.selectOpenWebRXProfile(profileID))
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
    rememberOpenWebRXBookmark(bookmark)
    if let mode = bookmark.modulation {
      setMode(mode)
    }
    setFrequencyHz(bookmark.frequencyHz)
  }

  func restoreLastOpenWebRXBookmark() {
    guard let lastOpenWebRXBookmark else { return }
    applyServerBookmark(lastOpenWebRXBookmark)
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
    case .openWebRX:
      return "dBFS"
    case .none:
      return "dB"
    }
  }

  func tuneStepOptions(for backend: SDRBackend) -> [Int] {
    tuningBandProfile(for: backend).stepOptionsHz
  }

  func effectiveTuneStepHz(for backend: SDRBackend?) -> Int {
    resolvedTuneStepHz(
      forPreferred: settings.preferredTuneStepHz,
      preferenceMode: settings.tuneStepPreferenceMode,
      backend: backend
    )
  }

  func startScanner(
    channels: [ScanChannel],
    backend: SDRBackend,
    dwellSeconds: Double? = nil,
    holdSeconds: Double? = nil
  ) {
    guard state == .connected, !channels.isEmpty else { return }

    cancelActiveScanner(
      updateStatus: false,
      preserveResults: true,
      restoreSession: false,
      reason: "replace-with-channel-scanner"
    )
    let scannerToken = UUID()
    activeScannerToken = scannerToken
    activeScannerKind = .channelList
    isScannerRunning = true
    setOpenWebRXScannerSquelchLock(backend == .openWebRX)
    setKiwiScannerSquelchLock(backend == .kiwiSDR)
    setChannelScannerSignalPreviewActive(false, for: backend)
    channelScannerResults = []
    scannerStatusText = L10n.text("scanner.started", channels.count)
    let initialThreshold = scannerThreshold
    let initialSignalUnit = scannerSignalUnit(for: backend)
    let initialAdaptiveScanner = settings.adaptiveScannerEnabled
    let initialSaveResults = settings.saveChannelScannerResultsEnabled
    let initialStopOnSignal = settings.stopChannelScannerOnSignal
    let initialInterferenceFilter = settings.filterChannelScannerInterferenceEnabled
    Diagnostics.log(
      category: "Scanner",
      message:
        "Channel scanner started: backend=\(backend.displayName) channels=\(channels.count) threshold=\(formattedScannerValue(initialThreshold, unit: initialSignalUnit)) dwell=\(String(format: "%.2f", max(0.4, dwellSeconds ?? settings.scannerDwellSeconds)))s hold=\(String(format: "%.2f", max(0.5, holdSeconds ?? settings.scannerHoldSeconds)))s adaptive=\(initialAdaptiveScanner) save_results=\(initialSaveResults) stop_on_signal=\(initialStopOnSignal) filter_interference=\(initialInterferenceFilter) filter_profile=\(settings.channelScannerInterferenceFilterProfile.rawValue)"
    )

    scannerTask = Task {
      var index = 0
      var hopCount = 0
      let baseDwellSeconds = max(0.4, dwellSeconds ?? settings.scannerDwellSeconds)
      let baseHoldSeconds = max(0.5, holdSeconds ?? settings.scannerHoldSeconds)
      let shouldPersistResults = await MainActor.run { self.settings.saveChannelScannerResultsEnabled }
      let shouldStopOnSignal = await MainActor.run { self.settings.stopChannelScannerOnSignal }
      var stoppedOnSignalResult: ChannelScannerResult?
      var lastProbeState: String?
      var lastRejectedInterferenceSignature: String?

      while !Task.isCancelled {
        let channel = channels[index]

        await MainActor.run {
          self.setChannelScannerSignalPreviewActive(false, for: backend)
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

        let probe = await MainActor.run { self.currentChannelScannerSignalProbe(for: backend) }
        let signal = probe.signal
        let signalUnit = await MainActor.run { self.scannerSignalUnit(for: backend) }
        hopCount += 1
        if shouldLogChannelScannerProbe(
          hopCount: hopCount,
          totalChannels: channels.count,
          signal: signal,
          threshold: threshold,
          probeState: probe.state,
          previousProbeState: lastProbeState
        ) {
          Diagnostics.log(
            category: "Scanner",
            message:
              "Channel scanner sample: backend=\(backend.displayName) channel=\(channel.name) freq=\(FrequencyFormatter.mhzText(fromHz: channel.frequencyHz)) signal=\(formattedScannerProbeValue(probe, unit: signalUnit)) threshold=\(formattedScannerValue(threshold, unit: signalUnit))"
          )
        }
        lastProbeState = probe.state

        if probe.wasRejectedByInterferenceFilter,
          let rawSignal = probe.rawSignal,
          rawSignal >= threshold,
          shouldLogChannelScannerInterferenceRejection(
            hopCount: hopCount,
            totalChannels: channels.count,
            signature: "\(channel.id)|\(probe.filterState ?? "")",
            previousSignature: lastRejectedInterferenceSignature
          ) {
          lastRejectedInterferenceSignature = "\(channel.id)|\(probe.filterState ?? "")"
          Diagnostics.log(
            category: "Scanner",
            message:
              "Channel scanner rejected possible interference: backend=\(backend.displayName) channel=\(channel.name) freq=\(FrequencyFormatter.mhzText(fromHz: channel.frequencyHz)) raw_signal=\(formattedScannerValue(rawSignal, unit: signalUnit)) threshold=\(formattedScannerValue(threshold, unit: signalUnit)) reason=\(probe.filterState ?? "filter=rejected:unspecified")"
          )
        }

        if let signal, signal >= threshold {
          let result = ChannelScannerResult(
            id: "\(channel.frequencyHz)|\(channel.mode?.rawValue ?? "none")",
            name: channel.name,
            frequencyHz: channel.frequencyHz,
            mode: channel.mode,
            signal: signal,
            signalUnit: signalUnit,
            detectedAt: Date()
          )
          await MainActor.run {
            self.setChannelScannerSignalPreviewActive(true, for: backend)
            self.mergeChannelScannerResult(result)
            self.scannerStatusText = L10n.text(
              "scanner.signal_found",
              channel.name,
              signal,
              self.scannerSignalUnit(for: backend)
            )
          }
          Diagnostics.log(
            category: "Scanner",
            message:
              "Channel scanner hit: backend=\(backend.displayName) channel=\(channel.name) freq=\(FrequencyFormatter.mhzText(fromHz: channel.frequencyHz)) signal=\(formattedScannerValue(signal, unit: signalUnit)) threshold=\(formattedScannerValue(threshold, unit: signalUnit)) margin=\(formattedScannerDelta(signal - threshold, unit: signalUnit)) save_results=\(shouldPersistResults) stop_on_signal=\(shouldStopOnSignal)"
          )
          if shouldStopOnSignal {
            stoppedOnSignalResult = result
            break
          }
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
        guard self.activeScannerToken == scannerToken else { return }
        self.scannerTask = nil
        self.isScannerRunning = false
        self.activeScannerKind = nil
        self.activeScannerToken = nil
        self.setOpenWebRXScannerSquelchLock(false)
        self.setKiwiScannerSquelchLock(false)
        self.setChannelScannerSignalPreviewActive(false, for: backend)
        if shouldPersistResults {
          self.persistCurrentChannelScannerResults(self.channelScannerResults)
          Diagnostics.log(
            category: "Scanner",
            message:
              "Channel scanner results saved: backend=\(backend.displayName) count=\(self.channelScannerResults.count)"
          )
        }
        if let stoppedOnSignalResult {
          self.scannerStatusText = L10n.text(
            "scanner.channel.status.stopped_on_signal",
            stoppedOnSignalResult.name
          )
          Diagnostics.log(
            category: "Scanner",
            message:
              "Channel scanner stopped on signal: backend=\(backend.displayName) channel=\(stoppedOnSignalResult.name) freq=\(FrequencyFormatter.mhzText(fromHz: stoppedOnSignalResult.frequencyHz)) signal=\(formattedScannerValue(stoppedOnSignalResult.signal, unit: stoppedOnSignalResult.signalUnit)) results=\(self.channelScannerResults.count)"
          )
        } else if self.scannerStatusText?.contains(L10n.text("scanner.signal_found_prefix")) != true {
          self.scannerStatusText = L10n.text("scanner.stopped")
          Diagnostics.log(
            category: "Scanner",
            message:
              "Channel scanner stopped: backend=\(backend.displayName) reason=cancelled results=\(self.channelScannerResults.count)"
          )
        }
      }
    }
  }

  func startFMDXBandScanner(
    rangePreset: FMDXBandScanRangePreset,
    stepHz requestedStepHz: Int,
    scanMode: FMDXBandScanMode = .standard
  ) {
    guard state == .connected, activeBackend == .fmDxWebserver else { return }

    let definition = rangePreset.definition
    guard !(definition.mode == .am) || fmdxSupportsAM else {
      isShowingFMDXTuneConfirmationWarning = false
      fmdxTuneWarningText = L10n.text("fmdx.band.am_not_supported")
      return
    }

    cancelActiveScanner(
      updateStatus: false,
      preserveResults: false,
      restoreSession: false,
      reason: "replace-with-fmdx-band-scanner"
    )

    let scannerToken = UUID()
    let normalizedStepHz = normalizedFMDXBandScannerStepHz(requestedStepHz, definition: definition)
    let frequencies = FMDXBandScanSequenceBuilder.buildFrequencies(
      in: definition.rangeHz,
      stepHz: normalizedStepHz,
      startBehavior: settings.fmdxBandScanStartBehavior,
      currentFrequencyHz: settings.frequencyHz
    )
    guard !frequencies.isEmpty else { return }

    let restoreFrequencyHz = settings.frequencyHz
    let restoreMode = settings.mode
    let threshold = scannerThreshold
    let hitBehavior = settings.fmdxBandScanHitBehavior
    let shouldSaveScanResults = settings.saveFMDXScannerResultsEnabled
    let effectiveScanMode: FMDXBandScanMode =
      shouldSaveScanResults || scanMode != .quickNewSignals ? scanMode : .standard
    let savedResultsBeforeScan = shouldSaveScanResults ? currentSavedFMDXScanResults() : []
    let hadSavedBaseline = !savedResultsBeforeScan.isEmpty

    activeScannerToken = scannerToken
    activeScannerKind = .fmdxBandRange(
      restoreFrequencyHz: restoreFrequencyHz,
      restoreMode: restoreMode
    )
    fmdxBandScannerResults = []
    isScannerRunning = true
    scannerStatusText = L10n.text(
      "fmdx.scanner.status.started",
      rangePreset.localizedTitle,
      frequencies.count
    )
    Diagnostics.log(
      category: "FMDX Scanner",
      message: "Band scanner started: range=\(rangePreset.rawValue) mode=\(effectiveScanMode.rawValue) step_hz=\(normalizedStepHz) threshold=\(threshold) points=\(frequencies.count) start_behavior=\(settings.fmdxBandScanStartBehavior.rawValue) hit_behavior=\(hitBehavior.rawValue)"
    )

    scannerTask = Task { [weak self] in
      guard let self else { return }

      var rawSamples: [FMDXBandScanSample] = []
      rawSamples.reserveCapacity(max(8, frequencies.count / 4))
      var stoppedOnSignalSample: FMDXBandScanSample?

      for (index, frequencyHz) in frequencies.enumerated() {
        if Task.isCancelled { return }

        await MainActor.run {
          guard self.activeScannerToken == scannerToken else { return }
          self.scannerStatusText = L10n.text(
            "fmdx.scanner.status.scanning",
            rangePreset.localizedTitle,
            FrequencyFormatter.fmDxMHzText(fromHz: frequencyHz),
            index + 1,
            frequencies.count
          )
        }

        if let sample = await self.scanFMDXBandScannerPoint(
          frequencyHz: frequencyHz,
          mode: definition.mode,
          metadataProfileBand: definition.metadataProfileBand,
          threshold: threshold,
          scanMode: effectiveScanMode
        ) {
          if Task.isCancelled { return }
          rawSamples.append(sample)
          if hitBehavior == .stopOnSignal {
            stoppedOnSignalSample = sample
            break
          }
        }
      }

      if Task.isCancelled { return }

      let results = FMDXBandScanReducer.reduce(
        samples: rawSamples,
        mergeSpacingHz: definition.mergeSpacingProfileBand.peakMergeSpacingHz(stepHz: normalizedStepHz)
      )
      let displayResults: [FMDXBandScanResult]
      if effectiveScanMode == .quickNewSignals && shouldSaveScanResults && hadSavedBaseline {
        displayResults = self.filterNewFMDXBandScanResults(
          results,
          comparedTo: savedResultsBeforeScan
        )
      } else {
        displayResults = results
      }
      let shouldRestoreSession = stoppedOnSignalSample == nil

      await MainActor.run {
        guard self.activeScannerToken == scannerToken else { return }
        self.scannerTask = nil
        self.isScannerRunning = false
        self.activeScannerKind = nil
        self.activeScannerToken = nil
        self.fmdxBandScannerResults = displayResults
        if shouldSaveScanResults {
          self.persistCurrentFMDXScanResults(results)
        }
        if shouldRestoreSession {
          self.restoreFMDXBandScannerSession(
            frequencyHz: restoreFrequencyHz,
            mode: restoreMode
          )
        } else {
          self.scheduleListeningHistoryCapture()
        }
        self.scannerStatusText = self.completedFMDXBandScannerStatusText(
          rangeTitle: rangePreset.localizedTitle,
          scanMode: effectiveScanMode,
          stoppedOnSignalSample: stoppedOnSignalSample,
          shouldSaveScanResults: shouldSaveScanResults,
          hadSavedBaseline: hadSavedBaseline,
          displayResultCount: displayResults.count,
          fullResultCount: results.count
        )
        Diagnostics.log(
          category: "FMDX Scanner",
          message: "Band scanner finished: range=\(rangePreset.rawValue) mode=\(effectiveScanMode.rawValue) shown_results=\(displayResults.count) saved_results=\(results.count) baseline=\(hadSavedBaseline) stopped_on_signal=\(stoppedOnSignalSample != nil)"
        )
      }
    }
  }

  private func scanFMDXBandScannerPoint(
    frequencyHz: Int,
    mode: DemodulationMode,
    metadataProfileBand: FMDXQuickBand,
    threshold: Double,
    scanMode: FMDXBandScanMode
  ) async -> FMDXBandScanSample? {
    let timingProfile = scanMode.timingProfile(
      for: metadataProfileBand,
      settings: settings
    )
    let maxTuneAttempts = timingProfile.tuneAttemptCount

    for attempt in 1...maxTuneAttempts {
      let checkpoint = await MainActor.run {
        self.prepareFMDXBandScannerTune(
          frequencyHz: frequencyHz,
          mode: mode
        )
      }

      let lockCheckpoint = await self.awaitFMDXBandScannerTuneLock(
        frequencyHz: frequencyHz,
        settleSeconds: timingProfile.settleSeconds,
        after: checkpoint,
        minimumDeadlineSeconds: timingProfile.minimumDeadlineSeconds,
        confirmationGraceSeconds: timingProfile.confirmationGraceSeconds,
        minimumPostLockSettleSeconds: timingProfile.minimumPostLockSettleSeconds
      )
      if Task.isCancelled { return nil }
      guard let lockCheckpoint else {
        let telemetryAge = await MainActor.run {
          self.fmdxTelemetryAgeText()
        }
        Diagnostics.log(
          severity: attempt < maxTuneAttempts ? .info : .warning,
          category: "FMDX Scanner",
          message: "Fresh telemetry timeout during band scan: metadata_profile=\(metadataProfileBand.rawValue) frequency_hz=\(frequencyHz) mode=\(scanMode.rawValue) attempt=\(attempt)/\(maxTuneAttempts) telemetry_age=\(telemetryAge)"
        )

        if attempt < maxTuneAttempts {
          try? await Task.sleep(nanoseconds: fmdxBandScannerRetryDelayNanoseconds)
          continue
        }
        return nil
      }

      return await self.collectFMDXBandScanSample(
        expectedFrequencyHz: frequencyHz,
        mode: mode,
        threshold: threshold,
        metadataAfter: lockCheckpoint,
        timingProfile: timingProfile
      )
    }

    return nil
  }

  func stopScanner() {
    cancelActiveScanner(
      updateStatus: true,
      preserveResults: true,
      restoreSession: true,
      reason: "user-request"
    )
  }

  private func cancelActiveScanner(
    updateStatus: Bool,
    preserveResults: Bool,
    restoreSession: Bool,
    reason: String
  ) {
    scannerTask?.cancel()
    scannerTask = nil

    let scannerKind = activeScannerKind
    activeScannerKind = nil
    activeScannerToken = nil
    isScannerRunning = false
    setOpenWebRXScannerSquelchLock(false)
    setKiwiScannerSquelchLock(false)
    setChannelScannerSignalPreviewActive(false)

    if !preserveResults {
      channelScannerResults = []
      fmdxBandScannerResults = []
    } else if settings.saveChannelScannerResultsEnabled {
      persistCurrentChannelScannerResults(channelScannerResults)
    }

    if let scannerKind {
      let scannerName: String
      switch scannerKind {
      case .channelList:
        scannerName = "channel-list"
      case .fmdxBandRange:
        scannerName = "fmdx-band"
      }
      Diagnostics.log(
        category: "Scanner",
        message:
          "Scanner cancelled: kind=\(scannerName) reason=\(reason) preserve_results=\(preserveResults) restore_session=\(restoreSession)"
      )
    }

    if restoreSession,
      case let .fmdxBandRange(restoreFrequencyHz, restoreMode) = scannerKind {
      restoreFMDXBandScannerSession(
        frequencyHz: restoreFrequencyHz,
        mode: restoreMode
      )
    } else {
      scheduleListeningHistoryCapture()
    }

    if updateStatus {
      scannerStatusText = L10n.text("scanner.stopped")
    } else {
      scannerStatusText = nil
    }
  }

  private func restoreFMDXBandScannerSession(
    frequencyHz: Int,
    mode: DemodulationMode
  ) {
    guard state == .connected, activeBackend == .fmDxWebserver else { return }
    setMode(mode)
    setFrequencyHz(frequencyHz)
  }

  private func prepareFMDXBandScannerTune(
    frequencyHz: Int,
    mode: DemodulationMode
  ) -> FMDXTelemetryCheckpoint {
    guard state == .connected, activeBackend == .fmDxWebserver else {
      return currentFMDXTelemetryCheckpoint()
    }

    let checkpoint = currentFMDXTelemetryCheckpoint()

    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    clearFMDXTuneConfirmationState()

    let normalizedFrequencyHz = normalizedFMDXFrequencyHz(frequencyHz, mode: mode)
    settings.mode = mode
    settings.frequencyHz = normalizedFrequencyHz
    settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.preferredTuneStepHz, mode: mode)
    rememberFMDXFrequency(normalizedFrequencyHz, mode: mode)
    sendFMDXFrequencyNow(normalizedFrequencyHz, scheduleConfirmation: false)
    return checkpoint
  }

  private func normalizedFMDXBandScannerStepHz(
    _ requestedStepHz: Int,
    definition: FMDXBandScanRangeDefinition
  ) -> Int {
    if definition.stepOptionsHz.contains(requestedStepHz) {
      return requestedStepHz
    }
    return definition.defaultStepHz
  }

  private func awaitFMDXBandScannerTuneLock(
    frequencyHz: Int,
    settleSeconds: Double,
    after checkpoint: FMDXTelemetryCheckpoint,
    minimumDeadlineSeconds: Double,
    confirmationGraceSeconds: Double,
    minimumPostLockSettleSeconds: Double
  ) async -> FMDXTelemetryCheckpoint? {
    let deadline = Date().addingTimeInterval(max(minimumDeadlineSeconds, settleSeconds + confirmationGraceSeconds))

    while !Task.isCancelled && Date() < deadline {
      let lockCheckpoint = await MainActor.run {
        self.freshFMDXScannerTelemetryCheckpoint(
          for: frequencyHz,
          after: checkpoint
        )
      }
      if let lockCheckpoint {
        let settleNanoseconds = UInt64(max(minimumPostLockSettleSeconds, settleSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: settleNanoseconds)
        return lockCheckpoint
      }
      try? await Task.sleep(nanoseconds: 70_000_000)
    }

    return await MainActor.run {
      self.freshFMDXScannerTelemetryCheckpoint(
        for: frequencyHz,
        after: checkpoint
      )
    }
  }

  private func currentFMDXTelemetryCheckpoint() -> FMDXTelemetryCheckpoint {
    FMDXTelemetryCheckpoint(
      revision: lastFMDXTelemetryRevision,
      updatedAt: lastFMDXTelemetryAppliedAt
    )
  }

  private func freshFMDXScannerTelemetryCheckpoint(
    for frequencyHz: Int,
    after checkpoint: FMDXTelemetryCheckpoint
  ) -> FMDXTelemetryCheckpoint? {
    guard lastFMDXTelemetryRevision > checkpoint.revision else { return nil }
    guard lastFMDXTelemetryAppliedAt >= checkpoint.updatedAt else { return nil }
    guard isFMDXTuned(to: frequencyHz) else { return nil }
    return currentFMDXTelemetryCheckpoint()
  }

  private func fmdxTelemetryAgeText() -> String {
    guard lastFMDXTelemetryAppliedAt != .distantPast else { return "none" }
    return String(format: "%.2fs", Date().timeIntervalSince(lastFMDXTelemetryAppliedAt))
  }

  private func makeFMDXBandScanSample(
    expectedFrequencyHz: Int,
    mode: DemodulationMode,
    threshold: Double,
    metadataAfter checkpoint: FMDXTelemetryCheckpoint?
  ) -> FMDXBandScanSample? {
    guard let telemetry = fmdxTelemetry else { return nil }
    guard let signal = telemetry.signal, signal >= threshold else { return nil }
    guard let frequencyMHz = telemetry.frequencyMHz else { return nil }

    let reportedFrequencyHz = normalizeFMDXReportedFrequencyHz(fromMHz: frequencyMHz)
    guard abs(reportedFrequencyHz - expectedFrequencyHz) <= 2_000 else { return nil }
    let metadataIsFresh = isFMDXBandScanMetadataFresh(after: checkpoint)

    return FMDXBandScanSample(
      frequencyHz: reportedFrequencyHz,
      mode: mode,
      signal: signal,
      signalTop: telemetry.signalTop,
      stationName: metadataIsFresh ? preferredRDSStationName(from: telemetry) : nil,
      programService: metadataIsFresh ? normalizedRDSValue(telemetry.ps) : nil,
      radioText0: metadataIsFresh ? normalizedRDSValue(telemetry.rt0) : nil,
      radioText1: metadataIsFresh ? normalizedRDSValue(telemetry.rt1) : nil,
      city: metadataIsFresh ? normalizedRDSValue(telemetry.txInfo?.city) : nil,
      countryName: metadataIsFresh ? normalizedRDSValue(telemetry.countryName) : nil,
      distanceKm: metadataIsFresh ? normalizedRDSValue(telemetry.txInfo?.distanceKm) : nil,
      erpKW: metadataIsFresh ? normalizedRDSValue(telemetry.txInfo?.erpKW) : nil,
      userCount: metadataIsFresh ? telemetry.users : nil
    )
  }

  private func collectFMDXBandScanSample(
    expectedFrequencyHz: Int,
    mode: DemodulationMode,
    threshold: Double,
    metadataAfter checkpoint: FMDXTelemetryCheckpoint,
    timingProfile: FMDXBandScanTimingProfile
  ) async -> FMDXBandScanSample? {
    var bestSample = await MainActor.run {
      self.makeFMDXBandScanSample(
        expectedFrequencyHz: expectedFrequencyHz,
        mode: mode,
        threshold: threshold,
        metadataAfter: checkpoint
      )
    }

    guard let initialSample = bestSample else { return nil }
    guard timingProfile.metadataWindowSeconds > 0 else { return initialSample }

    let startedAt = Date()
    let deadline = startedAt.addingTimeInterval(timingProfile.metadataWindowSeconds)
    let minimumWindowSeconds = timingProfile.minimumMetadataWindowSeconds
    let pollNanoseconds = UInt64(timingProfile.metadataPollSeconds * 1_000_000_000)

    while !Task.isCancelled && Date() < deadline {
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed >= minimumWindowSeconds,
        let bestSample,
        fmdxBandScanSampleHasStationMetadata(bestSample) {
        break
      }

      try? await Task.sleep(nanoseconds: pollNanoseconds)
      if Task.isCancelled { break }

      let candidate = await MainActor.run {
        self.makeFMDXBandScanSample(
          expectedFrequencyHz: expectedFrequencyHz,
          mode: mode,
          threshold: threshold,
          metadataAfter: checkpoint
        )
      }

      if let candidate {
        bestSample = preferredFMDXBandScanSample(bestSample, candidate)
      }
    }

    return bestSample
  }
  private func preferredFMDXBandScanSample(
    _ current: FMDXBandScanSample?,
    _ candidate: FMDXBandScanSample
  ) -> FMDXBandScanSample {
    guard let current else { return candidate }

    let currentScore = fmdxBandScanMetadataScore(current)
    let candidateScore = fmdxBandScanMetadataScore(candidate)
    if candidateScore != currentScore {
      return candidateScore > currentScore ? candidate : current
    }

    if candidate.signal != current.signal {
      return candidate.signal > current.signal ? candidate : current
    }

    if let candidateSignalTop = candidate.signalTop,
      let currentSignalTop = current.signalTop,
      candidateSignalTop != currentSignalTop {
      return candidateSignalTop > currentSignalTop ? candidate : current
    }

    return current
  }

  private func fmdxBandScanMetadataScore(_ sample: FMDXBandScanSample) -> Int {
    var score = 0

    if let stationName = sample.stationName, !stationName.isEmpty {
      score += 80
    }
    if let programService = sample.programService, !programService.isEmpty {
      score += 60
    }
    if let city = sample.city, !city.isEmpty {
      score += 16
    }
    if let countryName = sample.countryName, !countryName.isEmpty {
      score += 10
    }
    if let distanceKm = sample.distanceKm, !distanceKm.isEmpty {
      score += 8
    }
    if let erpKW = sample.erpKW, !erpKW.isEmpty {
      score += 6
    }

    return score
  }

  private func fmdxBandScanSampleHasStationMetadata(_ sample: FMDXBandScanSample) -> Bool {
    if let stationName = sample.stationName, !stationName.isEmpty {
      return true
    }
    if let programService = sample.programService, !programService.isEmpty {
      return true
    }
    return false
  }

  private func mergeChannelScannerResult(_ result: ChannelScannerResult) {
    if let index = channelScannerResults.firstIndex(where: { $0.id == result.id }) {
      if result.signal > channelScannerResults[index].signal {
        channelScannerResults[index] = result
      }
    } else {
      channelScannerResults.append(result)
    }

    channelScannerResults.sort { lhs, rhs in
      if lhs.signal != rhs.signal {
        return lhs.signal > rhs.signal
      }
      return lhs.frequencyHz < rhs.frequencyHz
    }
  }

  private func persistCurrentChannelScannerResults(_ results: [ChannelScannerResult]) {
    persistCachedReceiverData { cached in
      cached.savedChannelScannerResults = results
    }
  }

  private func shouldLogChannelScannerProbe(
    hopCount: Int,
    totalChannels: Int,
    signal: Double?,
    threshold: Double,
    probeState: String,
    previousProbeState: String?
  ) -> Bool {
    if hopCount <= min(3, max(1, totalChannels)) {
      return true
    }

    if probeState != previousProbeState {
      return true
    }

    let stride = max(10, min(24, totalChannels))
    if hopCount % stride == 0 {
      return true
    }

    guard let signal else { return false }
    return abs(signal - threshold) <= 2.0 && hopCount % 4 == 0
  }

  private func shouldLogChannelScannerInterferenceRejection(
    hopCount: Int,
    totalChannels: Int,
    signature: String,
    previousSignature: String?
  ) -> Bool {
    if previousSignature != signature {
      return true
    }

    let stride = max(12, totalChannels)
    return hopCount % stride == 0
  }

  private func formattedScannerValue(_ value: Double, unit: String) -> String {
    "\(String(format: "%.1f", value)) \(unit)"
  }

  private func formattedScannerDelta(_ value: Double, unit: String) -> String {
    let sign = value >= 0 ? "+" : ""
    return "\(sign)\(String(format: "%.1f", value)) \(unit)"
  }

  private func formattedScannerProbeValue(_ probe: ChannelScannerSignalProbe, unit: String) -> String {
    let stateSuffix = probe.filterState.map { "\(probe.state); \($0)" } ?? probe.state
    if let value = probe.signal {
      return "\(String(format: "%.1f", value)) \(unit) [\(stateSuffix)]"
    }
    if let rawSignal = probe.rawSignal, probe.wasRejectedByInterferenceFilter {
      return "rejected \(String(format: "%.1f", rawSignal)) \(unit) [\(stateSuffix)]"
    }
    return "unavailable [\(stateSuffix)]"
  }

  private func formattedScannerMetric(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private func isFMDXBandScanMetadataFresh(after checkpoint: FMDXTelemetryCheckpoint?) -> Bool {
    guard let checkpoint else { return true }
    guard lastFMDXTelemetryRevision > checkpoint.revision else { return false }
    return lastFMDXTelemetryAppliedAt > checkpoint.updatedAt
  }

  private func currentSavedFMDXScanResults() -> [FMDXBandScanResult] {
    guard let activeProfileCacheKey else { return [] }
    return receiverDataCache.cachedData(for: activeProfileCacheKey)?.fmdxSavedScanResults ?? []
  }

  private func persistCurrentFMDXScanResults(_ results: [FMDXBandScanResult]) {
    persistCachedReceiverData { cached in
      cached.fmdxSavedScanResults = results
    }
  }

  private func filterNewFMDXBandScanResults(
    _ results: [FMDXBandScanResult],
    comparedTo savedResults: [FMDXBandScanResult]
  ) -> [FMDXBandScanResult] {
    FMDXSavedScanResultMatcher.filterNewResults(results, comparedTo: savedResults)
  }

  private func completedFMDXBandScannerStatusText(
    rangeTitle: String,
    scanMode: FMDXBandScanMode,
    stoppedOnSignalSample: FMDXBandScanSample?,
    shouldSaveScanResults: Bool,
    hadSavedBaseline: Bool,
    displayResultCount: Int,
    fullResultCount: Int
  ) -> String {
    if let stoppedOnSignalSample {
      return L10n.text(
        "fmdx.scanner.status.stopped_on_signal",
        fmdxBandScanSampleStatusTitle(stoppedOnSignalSample)
      )
    }

    switch scanMode {
    case .standard, .veryFast, .custom:
      return fullResultCount == 0
        ? L10n.text("fmdx.scanner.status.finished_empty", rangeTitle)
        : L10n.text("fmdx.scanner.status.finished_results", rangeTitle, fullResultCount)

    case .quickNewSignals:
      guard shouldSaveScanResults, hadSavedBaseline else {
        return L10n.text("fmdx.scanner.status.quick_no_baseline", rangeTitle)
      }

      return displayResultCount == 0
        ? L10n.text("fmdx.scanner.status.quick_empty", rangeTitle)
        : L10n.text("fmdx.scanner.status.quick_results", rangeTitle, displayResultCount)
    }
  }

  private func fmdxBandScanSampleStatusTitle(_ sample: FMDXBandScanSample) -> String {
    if let stationName = sample.stationName, !stationName.isEmpty {
      return stationName
    }
    if let programService = sample.programService, !programService.isEmpty {
      return programService
    }
    return FrequencyFormatter.fmDxMHzText(fromHz: sample.frequencyHz)
  }

  func setFrequencyHz(_ value: Int) {
    if isWaitingForInitialServerTuningSync() {
      updateBackendStatusText(L10n.text("session.status.sync_tuning"))
      return
    }

    if activeBackend == .fmDxWebserver {
      let roundedToKHz = Int((Double(value) / 1_000.0).rounded()) * 1_000
      settings.frequencyHz = normalizedFMDXFrequencyHz(roundedToKHz, mode: settings.mode)
      rememberFMDXFrequency(settings.frequencyHz, mode: settings.mode)
    } else {
      let range = frequencyRange(for: activeBackend)
      settings.frequencyHz = min(max(value, range.lowerBound), range.upperBound)
    }
    let tuneStepChanged = syncTuneStepToCurrentBandIfNeeded()
    persistSettings()
    if tuneStepChanged, activeBackend == .openWebRX {
      updateBackendStatusText(openWebRXStatusSummary(frequencyHz: settings.frequencyHz, mode: settings.mode))
    }
    if tuneStepChanged, activeBackend == .kiwiSDR {
      updateBackendStatusText(kiwiStatusSummary(
        frequencyHz: settings.frequencyHz,
        mode: settings.mode,
        reportedBandName: currentKiwiBandName
      ))
    }

    guard activeBackend == .fmDxWebserver else {
      applyIfConnected()
      scheduleListeningHistoryCapture()
      scheduleRecentFrequencyCapture()
      return
    }
    queueFMDXFrequencySend(settings.frequencyHz)
    scheduleListeningHistoryCapture()
    scheduleRecentFrequencyCapture()
  }

  func setTuneStepHz(_ value: Int) {
    let normalized = RadioSessionSettings.normalizedTuneStep(value)
    settings.tuneStepPreferenceMode = .manual
    settings.preferredTuneStepHz = normalized
    let resolved = resolvedTuneStepHz(
      forPreferred: normalized,
      preferenceMode: .manual,
      backend: activeBackend
    )
    settings.tuneStepHz = resolved
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Tune step set to \(resolved) Hz (preferred \(normalized) Hz, requested \(value) Hz, mode=manual)"
    )
  }

  func setTuneStepPreferenceMode(_ mode: TuneStepPreferenceMode) {
    guard settings.tuneStepPreferenceMode != mode else { return }
    settings.tuneStepPreferenceMode = mode
    settings.tuneStepHz = resolvedTuneStepHz(
      forPreferred: settings.preferredTuneStepHz,
      preferenceMode: mode,
      backend: activeBackend
    )
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Tune step preference changed to \(mode.rawValue) with resolved step \(settings.tuneStepHz) Hz"
    )
  }

  func setTuningGestureDirection(_ direction: TuningGestureDirection) {
    guard settings.tuningGestureDirection != direction else { return }
    settings.tuningGestureDirection = direction
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Tuning gesture direction set to \(direction.rawValue)"
    )
  }

  func setFMDXTuneConfirmationWarningsEnabled(_ enabled: Bool) {
    guard settings.fmdxTuneConfirmationWarningsEnabled != enabled else { return }
    settings.fmdxTuneConfirmationWarningsEnabled = enabled
    if !enabled, isShowingFMDXTuneConfirmationWarning {
      isShowingFMDXTuneConfirmationWarning = false
      fmdxTuneWarningText = nil
    }
    persistSettings()
  }

  func setOpenReceiverAfterHistoryRestore(_ enabled: Bool) {
    guard settings.openReceiverAfterHistoryRestore != enabled else { return }
    settings.openReceiverAfterHistoryRestore = enabled
    persistSettings()
  }

  func setShowRecentFrequencies(_ enabled: Bool) {
    guard settings.showRecentFrequencies != enabled else { return }
    settings.showRecentFrequencies = enabled
    if !enabled {
      recentFrequencyCaptureTask?.cancel()
      recentFrequencyCaptureTask = nil
    }
    persistSettings()
  }

  func setIncludeRecentFrequenciesFromOtherReceivers(_ enabled: Bool) {
    guard settings.includeRecentFrequenciesFromOtherReceivers != enabled else { return }
    settings.includeRecentFrequenciesFromOtherReceivers = enabled
    persistSettings()
  }

  func setAutoConnectSelectedProfileOnLaunch(_ enabled: Bool) {
    guard settings.autoConnectSelectedProfileOnLaunch != enabled else { return }
    settings.autoConnectSelectedProfileOnLaunch = enabled
    persistSettings()
  }

  func restoreCurrentSession(
    frequencyHz: Int?,
    mode: DemodulationMode?
  ) {
    guard state == .connected, let profileID = connectedProfileID else { return }

    if isWaitingForInitialServerTuningSync() {
      scheduleRestoreAfterConnection(
        profileID: profileID,
        frequencyHz: frequencyHz,
        mode: mode
      )
      return
    }

    if let mode {
      setMode(mode)
    }
    if let frequencyHz {
      setFrequencyHz(frequencyHz)
    }
  }

  func tune(byStepCount stepCount: Int) {
    let delta = stepCount * settings.tuneStepHz
    setFrequencyHz(settings.frequencyHz + delta)
  }

  func setMode(_ mode: DemodulationMode) {
    if activeBackend == .fmDxWebserver {
      let amUnsupportedWarning = L10n.text("fmdx.band.am_not_supported")
      let previousMode = settings.mode
      let previousFrequencyHz = settings.frequencyHz
      var resolvedMode: DemodulationMode = (mode == .fm || mode == .am) ? mode : .fm
      if resolvedMode == .am && hasFMDXCapabilitySnapshot && !fmdxCapabilities.supportsAM {
        resolvedMode = .fm
        isShowingFMDXTuneConfirmationWarning = false
        fmdxTuneWarningText = amUnsupportedWarning
      } else if resolvedMode == .fm && fmdxTuneWarningText == amUnsupportedWarning {
        isShowingFMDXTuneConfirmationWarning = false
        fmdxTuneWarningText = nil
      }

      if previousMode != resolvedMode {
        rememberFMDXFrequency(previousFrequencyHz, mode: previousMode)
      }

      settings.mode = resolvedMode
      if !fmdxFrequencyRange(for: resolvedMode).contains(settings.frequencyHz) {
        settings.frequencyHz = preferredFMDXFrequency(for: resolvedMode)
      }
      Diagnostics.log(
        category: "FMDX",
        message: "Band switch requested: requested=\(mode.rawValue) resolved=\(resolvedMode.rawValue) supportsAM=\(fmdxCapabilities.supportsAM) previous_mode=\(previousMode.rawValue) previous_frequency_hz=\(previousFrequencyHz) target_frequency_hz=\(settings.frequencyHz)"
      )
      rememberFMDXFrequency(settings.frequencyHz, mode: resolvedMode)
      settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.preferredTuneStepHz, mode: settings.mode)
      persistSettings()
      if previousMode != resolvedMode || previousFrequencyHz != settings.frequencyHz {
        applyCurrentSettingsToConnectedBackend()
      }
      scheduleListeningHistoryCapture()
      scheduleRecentFrequencyCapture()
      return
    }
    let targetBackend = activeBackend ?? currentConnectedProfile?.backend ?? .openWebRX
    settings.mode = normalizeMode(mode, for: targetBackend)
    _ = syncTuneStepToCurrentBandIfNeeded()
    persistSettings()
    applyIfConnected()
    scheduleListeningHistoryCapture()
    scheduleRecentFrequencyCapture()
  }

  func selectFMDXQuickBand(_ band: FMDXQuickBand) {
    guard activeBackend == .fmDxWebserver else { return }

    if band.isAM && hasFMDXCapabilitySnapshot && !fmdxCapabilities.supportsAM {
      setMode(.am)
      return
    }

    let targetFrequencyHz = preferredFMDXFrequency(for: band)
    guard settings.mode != band.mode || currentFMDXQuickBand != band || settings.frequencyHz != targetFrequencyHz else {
      return
    }

    noteSelectedFMDXQuickBand(band)
    Diagnostics.log(
      category: "FMDX",
      message: "Quick band selected: band=\(band.rawValue) mode=\(band.mode.rawValue) target_frequency_hz=\(targetFrequencyHz)"
    )

    if settings.mode != band.mode {
      setMode(band.mode)
    }

    if settings.frequencyHz != targetFrequencyHz {
      setFrequencyHz(targetFrequencyHz)
    }
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

  func setMixWithOtherAudioApps(_ enabled: Bool) {
    settings.mixWithOtherAudioApps = enabled
    SharedAudioOutput.engine.setMixWithOtherAudioApps(enabled)
    FMDXMP3AudioPlayer.shared.setMixWithOtherAudioApps(enabled)
    persistSettings()
  }

  func toggleAudioMuted() {
    setAudioMuted(!settings.audioMuted)
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

  func setFMDXAudioMode(_ mode: FMDXAudioMode) {
    guard activeBackend == .fmDxWebserver else { return }
    pendingFMDXAudioModeIsStereo = mode.isStereo
    pendingFMDXAudioModeDeadline = Date().addingTimeInterval(2.5)
    sendFMDXControl(.setFMDXForcedStereo(mode.isStereo))
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
    if activeBackend == .openWebRX, isOpenWebRXSquelchLockedByScanner {
      Diagnostics.log(
        category: "Scanner",
        message: "Ignored OpenWebRX squelch change while channel scanner was running"
      )
      return
    }
    if activeBackend == .kiwiSDR, isKiwiSquelchLockedByScanner {
      Diagnostics.log(
        category: "Scanner",
        message: "Ignored KiwiSDR squelch change while channel scanner was running"
      )
      return
    }
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

  func setKiwiNoiseBlankerAlgorithm(_ algorithm: KiwiNoiseBlankerAlgorithm) {
    settings.kiwiNoiseBlankerAlgorithm = algorithm
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiNoiseBlankerGate(_ value: Int) {
    settings.kiwiNoiseBlankerGate = RadioSessionSettings.clampedKiwiNoiseBlankerGate(value)
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiNoiseBlankerThreshold(_ value: Int) {
    settings.kiwiNoiseBlankerThreshold = RadioSessionSettings.clampedKiwiNoiseBlankerThreshold(value)
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiNoiseBlankerWildThreshold(_ value: Double) {
    settings.kiwiNoiseBlankerWildThreshold = RadioSessionSettings.clampedKiwiNoiseBlankerWildThreshold(value)
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiNoiseBlankerWildTaps(_ value: Int) {
    settings.kiwiNoiseBlankerWildTaps = RadioSessionSettings.clampedKiwiNoiseBlankerWildTaps(value)
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiNoiseBlankerWildImpulseSamples(_ value: Int) {
    settings.kiwiNoiseBlankerWildImpulseSamples = RadioSessionSettings.clampedKiwiNoiseBlankerWildImpulseSamples(value)
    persistSettings()
    sendKiwiNoiseControl()
  }

  func resetKiwiNoiseBlanker() {
    settings.resetKiwiNoiseBlanker()
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiNoiseFilterAlgorithm(_ algorithm: KiwiNoiseFilterAlgorithm) {
    settings.kiwiNoiseFilterAlgorithm = algorithm
    if algorithm == .spectral {
      settings.kiwiDenoiseEnabled = true
      settings.kiwiAutonotchEnabled = false
    } else if (algorithm == .wdsp || algorithm == .original),
      settings.kiwiDenoiseEnabled == false,
      settings.kiwiAutonotchEnabled == false {
      settings.kiwiDenoiseEnabled = true
    }
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiDenoiseEnabled(_ enabled: Bool) {
    settings.kiwiDenoiseEnabled = enabled
    if settings.kiwiNoiseFilterAlgorithm == .spectral {
      settings.kiwiDenoiseEnabled = true
    }
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiAutonotchEnabled(_ enabled: Bool) {
    if settings.kiwiNoiseFilterAlgorithm == .spectral {
      settings.kiwiAutonotchEnabled = false
    } else {
      settings.kiwiAutonotchEnabled = enabled
    }
    persistSettings()
    sendKiwiNoiseControl()
  }

  func resetKiwiNoiseFilter() {
    settings.resetKiwiNoiseFilter()
    persistSettings()
    sendKiwiNoiseControl()
  }

  func setKiwiPassbandLowCut(_ value: Int) {
    let current = currentKiwiPassband
    let limitHz = kiwiPassbandLimitHz
    let minWidth = RadioSessionSettings.kiwiMinimumPassbandHz
    let lowCut = min(max(value, -limitHz), current.highCut - minWidth)
    settings.setKiwiPassband(
      ReceiverBandpass(lowCut: lowCut, highCut: current.highCut),
      for: settings.mode,
      sampleRateHz: kiwiTelemetry?.sampleRateHz
    )
    persistSettings()
    sendKiwiPassbandControl()
  }

  func setKiwiPassbandHighCut(_ value: Int) {
    let current = currentKiwiPassband
    let limitHz = kiwiPassbandLimitHz
    let minWidth = RadioSessionSettings.kiwiMinimumPassbandHz
    let highCut = max(min(value, limitHz), current.lowCut + minWidth)
    settings.setKiwiPassband(
      ReceiverBandpass(lowCut: current.lowCut, highCut: highCut),
      for: settings.mode,
      sampleRateHz: kiwiTelemetry?.sampleRateHz
    )
    persistSettings()
    sendKiwiPassbandControl()
  }

  func resetKiwiPassband() {
    settings.resetKiwiPassband(for: settings.mode)
    persistSettings()
    sendKiwiPassbandControl()
  }

  func setKiwiWaterfallSpeed(_ value: Int) {
    settings.kiwiWaterfallSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(value)
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallWindowFunction(_ value: Int) {
    settings.kiwiWaterfallWindowFunction = RadioSessionSettings.normalizedKiwiWaterfallWindowFunction(value)
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallInterpolation(_ value: Int) {
    settings.kiwiWaterfallInterpolation = RadioSessionSettings.normalizedKiwiWaterfallInterpolation(value)
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallCICCompensation(_ enabled: Bool) {
    settings.kiwiWaterfallCICCompensation = enabled
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func setKiwiWaterfallZoom(_ value: Int) {
    settings.kiwiWaterfallZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(value)
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func panKiwiWaterfallLeft() {
    guard let step = kiwiWaterfallPanStepBins() else { return }
    settings.kiwiWaterfallPanOffsetBins = RadioSessionSettings.clampedKiwiWaterfallPanOffsetBins(
      settings.kiwiWaterfallPanOffsetBins - step
    )
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func panKiwiWaterfallRight() {
    guard let step = kiwiWaterfallPanStepBins() else { return }
    settings.kiwiWaterfallPanOffsetBins = RadioSessionSettings.clampedKiwiWaterfallPanOffsetBins(
      settings.kiwiWaterfallPanOffsetBins + step
    )
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func centerKiwiWaterfall() {
    guard settings.kiwiWaterfallPanOffsetBins != 0 else { return }
    settings.kiwiWaterfallPanOffsetBins = 0
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

  func applyKiwiWaterfallSettings(
    speed: Int,
    zoom: Int,
    minDB: Int,
    maxDB: Int
  ) {
    settings.kiwiWaterfallSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(speed)
    settings.kiwiWaterfallZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(zoom)
    settings.kiwiWaterfallMinDB = RadioSessionSettings.clampedKiwiWaterfallMinDB(minDB)
    settings.kiwiWaterfallMaxDB = RadioSessionSettings.clampedKiwiWaterfallMaxDB(maxDB)
    if settings.kiwiWaterfallMaxDB <= settings.kiwiWaterfallMinDB {
      settings.kiwiWaterfallMaxDB = min(30, settings.kiwiWaterfallMinDB + 10)
    }
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func resetKiwiWaterfallFFT() {
    settings.kiwiWaterfallWindowFunction = RadioSessionSettings.default.kiwiWaterfallWindowFunction
    settings.kiwiWaterfallInterpolation = RadioSessionSettings.default.kiwiWaterfallInterpolation
    settings.kiwiWaterfallCICCompensation = RadioSessionSettings.default.kiwiWaterfallCICCompensation
    persistSettings()
    sendKiwiWaterfallControl()
  }

  func applyKiwiSignalPreset(
    agcEnabled: Bool,
    rfGain: Double
  ) {
    settings.agcEnabled = agcEnabled
    settings.rfGain = min(max(rfGain, 0), 100)
    persistSettings()
    applyIfConnected()
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

  func setSaveChannelScannerResultsEnabled(_ enabled: Bool) {
    settings.saveChannelScannerResultsEnabled = enabled
    persistSettings()
  }

  func setPlayDetectedChannelScannerSignalsEnabled(_ enabled: Bool) {
    settings.playDetectedChannelScannerSignalsEnabled = enabled
    applyChannelScannerPlaybackMute()
    persistSettings()
  }

  func setStopChannelScannerOnSignal(_ enabled: Bool) {
    settings.stopChannelScannerOnSignal = enabled
    persistSettings()
  }

  func setFilterChannelScannerInterferenceEnabled(_ enabled: Bool) {
    settings.filterChannelScannerInterferenceEnabled = enabled
    persistSettings()
  }

  func setChannelScannerInterferenceFilterProfile(
    _ profile: ChannelScannerInterferenceFilterProfile
  ) {
    settings.channelScannerInterferenceFilterProfile = profile
    persistSettings()
  }

  func setSaveFMDXScannerResultsEnabled(_ enabled: Bool) {
    settings.saveFMDXScannerResultsEnabled = enabled
    persistSettings()
  }

  func setFMDXBandScanStartBehavior(_ behavior: FMDXBandScanStartBehavior) {
    settings.fmdxBandScanStartBehavior = behavior
    persistSettings()
  }

  func setFMDXBandScanHitBehavior(_ behavior: FMDXBandScanHitBehavior) {
    settings.fmdxBandScanHitBehavior = behavior
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

  func setFMDXCustomScanSettleSeconds(_ value: Double) {
    settings.fmdxCustomScanSettleSeconds = RadioSessionSettings.clampedFMDXCustomScanSettleSeconds(value)
    persistSettings()
  }

  func setFMDXCustomScanMetadataWindowSeconds(_ value: Double) {
    settings.fmdxCustomScanMetadataWindowSeconds = RadioSessionSettings.clampedFMDXCustomScanMetadataWindowSeconds(value)
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
    refreshFMDXAudioAnalysis(forceLog: false)
  }

  func setFMDXAudioMaxLatencySeconds(_ value: Double) {
    settings.fmdxAudioMaxLatencySeconds = RadioSessionSettings.clampedFMDXAudioMaxLatencySeconds(
      value,
      startupBufferSeconds: settings.fmdxAudioStartupBufferSeconds
    )
    persistSettings()
    applyFMDXAudioTuning()
    refreshFMDXAudioAnalysis(forceLog: false)
  }

  func setFMDXAudioPacketHoldSeconds(_ value: Double) {
    settings.fmdxAudioPacketHoldSeconds = RadioSessionSettings.clampedFMDXAudioPacketHoldSeconds(value)
    persistSettings()
    applyFMDXAudioTuning()
    refreshFMDXAudioAnalysis(forceLog: false)
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
    refreshFMDXAudioAnalysis(forceLog: false)
    Diagnostics.log(
      category: "Audio Suggestion",
      message: L10n.text("settings.audio.suggestion.log.applied", preset.localizedTitle)
    )
  }

  func setAudioSuggestionScope(_ scope: AudioSuggestionScope) {
    settings.audioSuggestionScope = scope
    persistSettings()
    refreshFMDXAudioAnalysis(forceLog: false)
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
    settings.kiwiNoiseBlankerAlgorithm = RadioSessionSettings.default.kiwiNoiseBlankerAlgorithm
    settings.kiwiNoiseBlankerGate = RadioSessionSettings.default.kiwiNoiseBlankerGate
    settings.kiwiNoiseBlankerThreshold = RadioSessionSettings.default.kiwiNoiseBlankerThreshold
    settings.kiwiNoiseBlankerWildThreshold = RadioSessionSettings.default.kiwiNoiseBlankerWildThreshold
    settings.kiwiNoiseBlankerWildTaps = RadioSessionSettings.default.kiwiNoiseBlankerWildTaps
    settings.kiwiNoiseBlankerWildImpulseSamples = RadioSessionSettings.default.kiwiNoiseBlankerWildImpulseSamples
    settings.kiwiNoiseFilterAlgorithm = RadioSessionSettings.default.kiwiNoiseFilterAlgorithm
    settings.kiwiDenoiseEnabled = RadioSessionSettings.default.kiwiDenoiseEnabled
    settings.kiwiAutonotchEnabled = RadioSessionSettings.default.kiwiAutonotchEnabled
    settings.kiwiPassbandsByMode = [:]
    settings.kiwiWaterfallSpeed = RadioSessionSettings.default.kiwiWaterfallSpeed
    settings.kiwiWaterfallWindowFunction = RadioSessionSettings.default.kiwiWaterfallWindowFunction
    settings.kiwiWaterfallInterpolation = RadioSessionSettings.default.kiwiWaterfallInterpolation
    settings.kiwiWaterfallCICCompensation = RadioSessionSettings.default.kiwiWaterfallCICCompensation
    settings.kiwiWaterfallZoom = RadioSessionSettings.default.kiwiWaterfallZoom
    settings.kiwiWaterfallPanOffsetBins = RadioSessionSettings.default.kiwiWaterfallPanOffsetBins
    settings.kiwiWaterfallMinDB = RadioSessionSettings.default.kiwiWaterfallMinDB
    settings.kiwiWaterfallMaxDB = RadioSessionSettings.default.kiwiWaterfallMaxDB
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
      updateBackendStatusText(L10n.text("session.status.sync_tuning"))
      return
    }
    let snapshot = OpenWebRXScannerSquelchPolicy.applyingOverride(
      to: settings,
      backend: activeBackend,
      isLockedByScanner: isOpenWebRXSquelchLockedByScanner
    )
    let effectiveSnapshot = KiwiScannerSquelchPolicy.applyingOverride(
      to: snapshot,
      backend: activeBackend,
      isLockedByScanner: isKiwiSquelchLockedByScanner
    )

    Task {
      do {
        try await client.apply(settings: effectiveSnapshot)
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
    guard runtimePolicy.allowsVisualTelemetry else { return }
    let speed = settings.kiwiWaterfallSpeed
    let zoom = settings.kiwiWaterfallZoom
    let minDB = settings.kiwiWaterfallMinDB
    let maxDB = settings.kiwiWaterfallMaxDB
    let centerFrequencyHz = settings.frequencyHz
    let panOffsetBins = settings.kiwiWaterfallPanOffsetBins
    let windowFunction = settings.kiwiWaterfallWindowFunction
    let interpolation = settings.kiwiWaterfallInterpolation
    let cicCompensation = settings.kiwiWaterfallCICCompensation

    Task {
      do {
        try await client.sendControl(
          .setKiwiWaterfall(
            speed: speed,
            zoom: zoom,
            minDB: minDB,
            maxDB: maxDB,
            centerFrequencyHz: centerFrequencyHz,
            panOffsetBins: panOffsetBins,
            windowFunction: windowFunction,
            interpolation: interpolation,
            cicCompensation: cicCompensation
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

  private func kiwiWaterfallViewportContext() -> KiwiWaterfallViewportContext? {
    guard
      let telemetry = kiwiTelemetry,
      let bandwidthHz = telemetry.bandwidthHz,
      let waterfallFFTSize = telemetry.waterfallFFTSize,
      let zoomMax = telemetry.zoomMax
    else {
      return nil
    }

    let context = KiwiWaterfallViewportContext(
      bandwidthHz: bandwidthHz,
      fftSize: waterfallFFTSize,
      zoomMax: zoomMax
    )
    return context.isValid ? context : nil
  }

  private func kiwiWaterfallPanStepBins() -> Int? {
    kiwiWaterfallViewportContext()?.recommendedPanStepBins(at: settings.kiwiWaterfallZoom)
  }

  private func sendKiwiPassbandControl() {
    guard state == .connected, activeBackend == .kiwiSDR, let client else { return }
    if isWaitingForInitialServerTuningSync() {
      updateBackendStatusText(L10n.text("session.status.sync_tuning"))
      return
    }

    kiwiPassbandDebounceTask?.cancel()
    let snapshotMode = settings.mode
    let snapshotFrequencyHz = settings.frequencyHz
    let snapshotPassband = currentKiwiPassband

    kiwiPassbandDebounceTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 120_000_000)
      if Task.isCancelled { return }
      do {
        try await client.sendControl(
          .setKiwiPassband(
            lowCut: snapshotPassband.lowCut,
            highCut: snapshotPassband.highCut,
            frequencyHz: snapshotFrequencyHz,
            mode: snapshotMode
          )
        )
      } catch {
        await MainActor.run {
          self?.lastError = error.localizedDescription
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "Kiwi passband update failed: \(error.localizedDescription)"
        )
      }
    }
  }

  private func sendKiwiNoiseControl() {
    guard state == .connected, activeBackend == .kiwiSDR, let client else { return }
    if isWaitingForInitialServerTuningSync() {
      updateBackendStatusText(L10n.text("session.status.sync_tuning"))
      return
    }

    kiwiNoiseDebounceTask?.cancel()
    let blankerAlgorithm = settings.kiwiNoiseBlankerAlgorithm
    let blankerGate = settings.kiwiNoiseBlankerGate
    let blankerThreshold = settings.kiwiNoiseBlankerThreshold
    let blankerWildThreshold = settings.kiwiNoiseBlankerWildThreshold
    let blankerWildTaps = settings.kiwiNoiseBlankerWildTaps
    let blankerWildImpulseSamples = settings.kiwiNoiseBlankerWildImpulseSamples
    let filterAlgorithm = settings.kiwiNoiseFilterAlgorithm
    let denoiseEnabled = settings.kiwiDenoiseEnabled
    let autonotchEnabled = settings.kiwiAutonotchEnabled

    kiwiNoiseDebounceTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 120_000_000)
      if Task.isCancelled { return }
      do {
        try await client.sendControl(
          .setKiwiNoiseBlanker(
            algorithm: blankerAlgorithm,
            gate: blankerGate,
            threshold: blankerThreshold,
            wildThreshold: blankerWildThreshold,
            wildTaps: blankerWildTaps,
            wildImpulseSamples: blankerWildImpulseSamples
          )
        )
        try await client.sendControl(
          .setKiwiNoiseFilter(
            algorithm: filterAlgorithm,
            denoiseEnabled: denoiseEnabled,
            autonotchEnabled: autonotchEnabled
          )
        )
      } catch {
        await MainActor.run {
          self?.lastError = error.localizedDescription
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "Kiwi noise processing update failed: \(error.localizedDescription)"
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

  private func sendFMDXFrequencyNow(
    _ frequencyHz: Int,
    scheduleConfirmation: Bool = true
  ) {
    clearActiveFMDXTuneConfirmationWarning()
    Diagnostics.log(
      category: "FMDX",
      message: "Sending tune request: frequency_hz=\(frequencyHz) mode=\(settings.mode.rawValue)"
    )
    sendFMDXControl(.setFMDXFrequencyHz(frequencyHz))

    if scheduleConfirmation {
      pendingFMDXTuneFrequencyHz = frequencyHz
      scheduleFMDXTuneConfirmation(for: frequencyHz)
    } else {
      pendingFMDXTuneFrequencyHz = nil
      fmDxTuneConfirmTask?.cancel()
      fmDxTuneConfirmTask = nil
    }
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
          let actualHz = self.normalizeFMDXReportedFrequencyHz(fromMHz: actualMHz)
          let actualText = FrequencyFormatter.mhzText(fromHz: actualHz)
          if abs(actualHz - frequencyHz) >= 1_000 {
            Diagnostics.log(
              severity: .warning,
              category: "FMDX",
              message: "Tune mismatch: requested=\(requestedText) actual=\(actualText)"
            )
            self.showFMDXTuneConfirmationWarning(
              L10n.text("fmdx.tune_warning_mismatch", requestedText, actualText)
            )
          }
        } else {
          Diagnostics.log(
            severity: .warning,
            category: "FMDX",
            message: "No tune confirmation received for \(requestedText)"
          )
          self.showFMDXTuneConfirmationWarning(
            L10n.text("fmdx.tune_warning_no_confirmation", requestedText)
          )
        }
      }
    }
  }

  private func clearFMDXTuneConfirmationState() {
    pendingFMDXTuneFrequencyHz = nil
    fmDxTuneConfirmTask?.cancel()
    fmDxTuneConfirmTask = nil
    clearActiveFMDXTuneConfirmationWarning()
  }

  private func showFMDXTuneConfirmationWarning(_ text: String) {
    isShowingFMDXTuneConfirmationWarning = true
    guard settings.fmdxTuneConfirmationWarningsEnabled else {
      fmdxTuneWarningText = nil
      return
    }
    fmdxTuneWarningText = text
  }

  private func clearActiveFMDXTuneConfirmationWarning() {
    guard isShowingFMDXTuneConfirmationWarning else { return }
    isShowingFMDXTuneConfirmationWarning = false
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
    settings.kiwiWaterfallPanOffsetBins = 0
    if activeBackend == .fmDxWebserver {
      settings.mode = .fm
      settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.preferredTuneStepHz, mode: .fm)
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
    merged.preferredTuneStepHz = RadioSessionSettings.normalizedTuneStep(merged.preferredTuneStepHz)
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
    SharedAudioOutput.engine.setMixWithOtherAudioApps(settings.mixWithOtherAudioApps)
    FMDXMP3AudioPlayer.shared.setMixWithOtherAudioApps(settings.mixWithOtherAudioApps)
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

      let normalizedStep = normalizeFMDXTuneStepHz(settings.preferredTuneStepHz, mode: settings.mode)
      if settings.tuneStepHz != normalizedStep {
        settings.tuneStepHz = normalizedStep
        changed = true
      }

      let targetRange = fmdxFrequencyRange(for: settings.mode)
      if !targetRange.contains(settings.frequencyHz) {
        settings.frequencyHz = preferredFMDXFrequency(for: settings.mode)
        changed = true
      } else {
        let roundedToKHz = Int((Double(settings.frequencyHz) / 1_000.0).rounded()) * 1_000
        if roundedToKHz != settings.frequencyHz {
          settings.frequencyHz = roundedToKHz
          changed = true
        }
      }
      rememberFMDXFrequency(settings.frequencyHz, mode: settings.mode)

    case .kiwiSDR:
      let normalizedMode = normalizeMode(settings.mode, for: .kiwiSDR)
      if settings.mode != normalizedMode {
        settings.mode = normalizedMode
        changed = true
      }

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

      let kiwiWindowFunction = RadioSessionSettings.normalizedKiwiWaterfallWindowFunction(
        settings.kiwiWaterfallWindowFunction
      )
      if settings.kiwiWaterfallWindowFunction != kiwiWindowFunction {
        settings.kiwiWaterfallWindowFunction = kiwiWindowFunction
        changed = true
      }

      let kiwiInterpolation = RadioSessionSettings.normalizedKiwiWaterfallInterpolation(
        settings.kiwiWaterfallInterpolation
      )
      if settings.kiwiWaterfallInterpolation != kiwiInterpolation {
        settings.kiwiWaterfallInterpolation = kiwiInterpolation
        changed = true
      }

      let kiwiZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(settings.kiwiWaterfallZoom)
      if settings.kiwiWaterfallZoom != kiwiZoom {
        settings.kiwiWaterfallZoom = kiwiZoom
        changed = true
      }

      let kiwiPanOffsetBins = RadioSessionSettings.clampedKiwiWaterfallPanOffsetBins(
        settings.kiwiWaterfallPanOffsetBins
      )
      if settings.kiwiWaterfallPanOffsetBins != kiwiPanOffsetBins {
        settings.kiwiWaterfallPanOffsetBins = kiwiPanOffsetBins
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
      let normalizedMode = normalizeMode(settings.mode, for: .openWebRX)
      if settings.mode != normalizedMode {
        settings.mode = normalizedMode
        changed = true
      }

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

    let resolvedTuneStep = resolvedTuneStepHz(
      forPreferred: settings.preferredTuneStepHz,
      preferenceMode: settings.tuneStepPreferenceMode,
      backend: backend
    )
    if settings.tuneStepHz != resolvedTuneStep {
      settings.tuneStepHz = resolvedTuneStep
      changed = true
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
    return resolvedTuneStepHz(
      value,
      preferenceMode: settings.tuneStepPreferenceMode,
      using: profile
    )
  }

  private func normalizeMode(_ mode: DemodulationMode, for backend: SDRBackend) -> DemodulationMode {
    mode.normalized(for: backend)
  }

  func normalizeFMDXReportedFrequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    let roundedToKHz = Int((Double(hz) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, fmDxOverallFrequencyRangeHz.lowerBound), fmDxOverallFrequencyRangeHz.upperBound)
  }

  func inferredFMDXMode(for frequencyHz: Int) -> DemodulationMode {
    fmdxFrequencyRange(for: .am).contains(frequencyHz) ? .am : .fm
  }

  func fmdxQuickBand(for frequencyHz: Int, mode: DemodulationMode) -> FMDXQuickBand {
    FMDXQuickBand.resolve(frequencyHz: frequencyHz, mode: mode)
  }

  func fmdxFrequencyRange(for mode: DemodulationMode) -> ClosedRange<Int> {
    switch mode {
    case .am:
      return fmDxAMMinFrequencyHz...fmDxAMMaxFrequencyHz
    default:
      return fmDxFMMinFrequencyHz...fmDxFMMaxFrequencyHz
    }
  }

  func normalizedFMDXFrequencyHz(_ value: Int, mode: DemodulationMode) -> Int {
    let range = fmdxFrequencyRange(for: mode)
    let roundedToKHz = Int((Double(value) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, range.lowerBound), range.upperBound)
  }

  private func frequencyRange(for backend: SDRBackend?) -> ClosedRange<Int> {
    switch backend {
    case .fmDxWebserver:
      return currentFMDXFrequencyRangeHz
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
    profile: SDRConnectionProfile,
    client: any SDRBackendClient
  ) {
    statusMonitorTask?.cancel()

    statusMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: statusMonitorIntervalNanoseconds())
        if Task.isCancelled {
          return
        }

        let isAlive = await client.isConnected()
        if !isAlive {
          Diagnostics.log(
            severity: .warning,
            category: "Session",
            message: "Connection lost for \(profile.name)"
          )
          await MainActor.run {
            guard self.connectedProfileID == profile.id else { return }
            self.beginAutomaticRecovery(for: profile, from: client)
          }
          return
        }

        if let backendError = await client.consumeServerError() {
          await client.disconnect()
          Diagnostics.log(
            severity: .error,
            category: "Session",
            message: "Server error on \(profile.name): \(backendError)"
          )
          await MainActor.run {
            guard self.connectedProfileID == profile.id else { return }
            self.client = nil
            self.connectedProfileID = nil
            self.activeBackend = nil
            self.activeProfileCacheKey = nil
            self.currentConnectedProfile = nil
            self.state = .failed
            self.statusText = L10n.text("session.status.server_error_on", profile.name)
            self.backendStatusText = nil
            self.lastError = backendError
            self.listeningHistoryCaptureTask?.cancel()
            self.listeningHistoryCaptureTask = nil
            self.deferredRestoreTask?.cancel()
            self.deferredRestoreTask = nil
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
            guard self.connectedProfileID == profile.id else { return }
            self.updateBackendStatusText(latestBackendStatus)
          }
        }

        var telemetryEvents: [BackendTelemetryEvent] = []
        while let telemetryEvent = await client.consumeTelemetryUpdate() {
          telemetryEvents.append(telemetryEvent)
        }
        if !telemetryEvents.isEmpty {
          await MainActor.run {
            guard self.connectedProfileID == profile.id else { return }
            for telemetryEvent in telemetryEvents {
              self.apply(telemetryEvent: telemetryEvent)
            }
          }
        }

        await MainActor.run {
          guard self.connectedProfileID == profile.id else { return }
          self.captureAudioDiagnosticsSampleIfNeeded()
        }

        if shouldRefreshLiveAudioAnalysis() {
          await MainActor.run {
            guard self.connectedProfileID == profile.id else { return }
            self.refreshFMDXAudioAnalysis(forceLog: false)
          }
        }
      }
    }
  }

  private func beginAutomaticRecovery(
    for profile: SDRConnectionProfile,
    from client: any SDRBackendClient
  ) {
    guard sessionRecoveryTask == nil else { return }

    cancelSessionTransientTasks(resetScannerState: true)
    self.client = nil
    activeBackend = profile.backend
    activeProfileCacheKey = ReceiverIdentity.key(for: profile)
    currentConnectedProfile = nil
    state = .connecting
    statusText = L10n.text("session.status.reconnecting_to", profile.name)
    updateBackendStatusText(L10n.text("session.status.reconnecting_wait"))
    lastError = nil

    sessionRecoveryTask = Task {
      defer { self.sessionRecoveryTask = nil }

      await client.disconnect()

      let startedAt = Date()
      var attempt = 0

      while !Task.isCancelled {
        let delaySeconds = autoReconnectDelaySeconds[min(attempt, autoReconnectDelaySeconds.count - 1)]
        attempt += 1
        await MainActor.run {
          self.automaticReconnectAttempts += 1
        }

        if delaySeconds > 0 {
          try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        }
        if Task.isCancelled { return }

        do {
          let newClient = makeClient(for: profile.backend)
          try await newClient.connect(profile: profile)
          await newClient.setRuntimePolicy(self.runtimePolicy)
          if Task.isCancelled {
            await newClient.disconnect()
            return
          }

          await MainActor.run {
            guard self.state == .connecting else { return }
            self.client = newClient
            self.connectedProfileID = profile.id
            self.activeBackend = profile.backend
            self.activeProfileCacheKey = ReceiverIdentity.key(for: profile)
            self.currentConnectedProfile = profile
            self.historyStore.recordReceiver(profile)
            NowPlayingMetadataController.shared.setReceiverName(profile.name)
            NowPlayingMetadataController.shared.setTitle(nil)
            self.hasInitialServerTuningSync = false
            self.initialServerTuningSyncDeadline = Date().addingTimeInterval(4.0)
            self.state = .connected
            if self.connectedSince == .distantPast {
              self.connectedSince = Date()
            }
            self.statusText = L10n.text("session.status.connected_to", profile.name)
            self.updateBackendStatusText(
              (profile.backend == .openWebRX || profile.backend == .kiwiSDR)
                ? L10n.text("session.status.sync_tuning")
                : nil
            )
            self.lastError = nil
            self.startStatusMonitor(profile: profile, client: newClient)
            self.scheduleInitialTuningFallbackAfterConnection(profileID: profile.id)
            self.scheduleListeningHistoryCapture()
          }
          Diagnostics.log(
            category: "Session",
            message: "Connection restored for \(profile.name) on attempt \(attempt)"
          )
          await MainActor.run {
            self.automaticReconnectSuccesses += 1
          }
          return
        } catch {
          Diagnostics.log(
            severity: .warning,
            category: "Session",
            message: "Reconnect attempt \(attempt) failed for \(profile.name): \(error.localizedDescription)"
          )

          if Date().timeIntervalSince(startedAt) >= autoReconnectWindowSeconds {
            break
          }
        }
      }

      if Task.isCancelled { return }

      await MainActor.run {
        guard self.connectedProfileID == profile.id || self.state == .connecting else { return }
        self.client = nil
        self.connectedProfileID = nil
        self.activeBackend = nil
        self.activeProfileCacheKey = nil
        self.currentConnectedProfile = nil
        self.state = .failed
        self.statusText = L10n.text("session.status.connection_lost")
        self.backendStatusText = nil
        self.lastError = L10n.text("session.status.reconnect_exhausted")
        self.resetRuntimeState(for: nil)
      }
      Diagnostics.log(
        severity: .error,
        category: "Session",
        message: "Automatic reconnect exhausted for \(profile.name)"
      )
    }
  }

  private func cancelAutomaticRecovery() {
    sessionRecoveryTask?.cancel()
    sessionRecoveryTask = nil
  }

  private func cancelSessionTransientTasks(resetScannerState: Bool) {
    statusMonitorTask?.cancel()
    statusMonitorTask = nil
    scannerTask?.cancel()
    scannerTask = nil
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    fmDxTuneConfirmTask?.cancel()
    fmDxTuneConfirmTask = nil
    kiwiPassbandDebounceTask?.cancel()
    kiwiPassbandDebounceTask = nil
    kiwiNoiseDebounceTask?.cancel()
    kiwiNoiseDebounceTask = nil
    listeningHistoryCaptureTask?.cancel()
    listeningHistoryCaptureTask = nil
    recentFrequencyCaptureTask?.cancel()
    recentFrequencyCaptureTask = nil
    deferredRestoreTask?.cancel()
    deferredRestoreTask = nil
    initialTuningFallbackTask?.cancel()
    initialTuningFallbackTask = nil
    pendingFMDXTuneFrequencyHz = nil
    clearPendingFMDXAudioModeState()

    if resetScannerState {
      isScannerRunning = false
      scannerStatusText = nil
      setOpenWebRXScannerSquelchLock(false)
      setKiwiScannerSquelchLock(false)
      setChannelScannerSignalPreviewActive(false)
    }
  }

  private func setOpenWebRXScannerSquelchLock(_ isLocked: Bool) {
    guard isOpenWebRXSquelchLockedByScanner != isLocked else { return }
    isOpenWebRXSquelchLockedByScanner = isLocked

    guard state == .connected, activeBackend == .openWebRX else { return }
    applyIfConnected()

    Diagnostics.log(
      category: "Scanner",
      message: isLocked
        ? "OpenWebRX squelch forced off for channel scanner"
        : "OpenWebRX squelch lock released after channel scanner"
    )
  }

  private func setKiwiScannerSquelchLock(_ isLocked: Bool) {
    guard isKiwiSquelchLockedByScanner != isLocked else { return }
    isKiwiSquelchLockedByScanner = isLocked

    guard state == .connected, activeBackend == .kiwiSDR else { return }
    applyIfConnected()

    Diagnostics.log(
      category: "Scanner",
      message: isLocked
        ? "KiwiSDR squelch forced off for channel scanner"
        : "KiwiSDR squelch lock released after channel scanner"
    )
  }

  private func setChannelScannerSignalPreviewActive(_ isActive: Bool, for backend: SDRBackend? = nil) {
    guard channelScannerSignalPreviewActive != isActive else {
      applyChannelScannerPlaybackMute(for: backend)
      return
    }

    channelScannerSignalPreviewActive = isActive
    applyChannelScannerPlaybackMute(for: backend)
  }

  private func applyChannelScannerPlaybackMute(for backend: SDRBackend? = nil) {
    let effectiveBackend = backend ?? activeBackend
    let shouldManagePlayback: Bool = {
      guard settings.playDetectedChannelScannerSignalsEnabled else { return false }
      guard isScannerRunning else { return false }
      guard case .channelList = activeScannerKind else { return false }
      return effectiveBackend == .openWebRX || effectiveBackend == .kiwiSDR
    }()

    SharedAudioOutput.engine.setScannerPlaybackMuted(
      shouldManagePlayback ? !channelScannerSignalPreviewActive : false
    )
  }

  private func applyRuntimePolicyToConnectedClient() {
    guard let client else { return }
    let runtimePolicy = runtimePolicy
    Task {
      await client.setRuntimePolicy(runtimePolicy)
    }
  }

  private func statusMonitorIntervalNanoseconds() -> UInt64 {
    switch runtimePolicy {
    case .interactive:
      return 1_300_000_000
    case .passive:
      return 2_500_000_000
    case .background:
      return 6_000_000_000
    }
  }

  private func shouldRefreshLiveAudioAnalysis() -> Bool {
    let now = Date()
    switch runtimePolicy {
    case .interactive:
      return true
    case .passive:
      guard now.timeIntervalSince(lastReducedActivityAudioAnalysisAt) >= 3 else { return false }
    case .background:
      guard now.timeIntervalSince(lastReducedActivityAudioAnalysisAt) >= 10 else { return false }
    }

    lastReducedActivityAudioAnalysisAt = now
    return true
  }

  private func apply(telemetryEvent: BackendTelemetryEvent) {
    switch telemetryEvent {
    case .openWebRXProfiles(let profiles, let selectedID):
      openWebRXProfiles = profiles
      let preferredID: String?
      if let currentPreferred = selectedOpenWebRXProfileID,
        profiles.contains(where: { $0.id == currentPreferred }) {
        preferredID = currentPreferred
      } else {
        preferredID = selectedID
      }
      selectedOpenWebRXProfileID = preferredID
      persistCachedReceiverData { cached in
        cached.openWebRXProfiles = profiles
        cached.selectedOpenWebRXProfileID = preferredID
      }
      if state == .connected,
        let preferredID,
        preferredID != selectedID {
        selectOpenWebRXProfile(preferredID)
      }

    case .openWebRXBookmarks(let bookmarks):
      serverBookmarks = bookmarks
      persistCachedReceiverData { cached in
        cached.serverBookmarks = bookmarks
      }
      if activeBackend == .openWebRX, state == .connected {
        recordCurrentListeningHistory()
      }

    case .openWebRXBandPlan(let bands):
      openWebRXBandPlan = bands
      persistCachedReceiverData { cached in
        cached.openWebRXBandPlan = bands
      }
      if syncTuneStepToCurrentBandIfNeeded() {
        persistSettings()
      }
      if activeBackend == .openWebRX {
        updateBackendStatusText(openWebRXStatusSummary(frequencyHz: settings.frequencyHz, mode: settings.mode))
      }

    case .openWebRXTuning(let frequencyHz, let mode):
      initialTuningFallbackTask?.cancel()
      initialTuningFallbackTask = nil
      hasInitialServerTuningSync = true
      NowPlayingMetadataController.shared.setTitle(nil)
      var changed = false
      let clamped = min(max(frequencyHz, openWebRXFrequencyRangeHz.lowerBound), openWebRXFrequencyRangeHz.upperBound)
      if settings.frequencyHz != clamped {
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
      updateBackendStatusText(openWebRXStatusSummary(frequencyHz: clamped, mode: mode))
      scheduleListeningHistoryCapture()

    case .kiwiTuning(let frequencyHz, let mode, let bandName, let passband):
      initialTuningFallbackTask?.cancel()
      initialTuningFallbackTask = nil
      hasInitialServerTuningSync = true
      NowPlayingMetadataController.shared.setTitle(nil)
      var changed = false
      let clamped = min(max(frequencyHz, kiwiFrequencyRangeHz.lowerBound), kiwiFrequencyRangeHz.upperBound)
      if settings.frequencyHz != clamped {
        settings.frequencyHz = clamped
        changed = true
      }
      if let mode, settings.mode != mode {
        settings.mode = mode
        changed = true
      }
      let activeMode = mode ?? settings.mode
      if let passband {
        let normalizedPassband = RadioSessionSettings.normalizedKiwiBandpass(
          passband,
          mode: activeMode,
          sampleRateHz: kiwiTelemetry?.sampleRateHz
        )
        if settings.kiwiPassband(for: activeMode, sampleRateHz: kiwiTelemetry?.sampleRateHz) != normalizedPassband {
          settings.setKiwiPassband(
            normalizedPassband,
            for: activeMode,
            sampleRateHz: kiwiTelemetry?.sampleRateHz
          )
          changed = true
        }
      }
      currentKiwiBandName = normalizedBandName(bandName)
      if syncTuneStepToCurrentBandIfNeeded() {
        changed = true
      }
      if changed {
        persistSettings()
      }
      updateBackendStatusText(kiwiStatusSummary(frequencyHz: clamped, mode: mode, reportedBandName: bandName))
      scheduleListeningHistoryCapture()
      if activeBackend == .kiwiSDR, state == .connected {
        sendKiwiWaterfallControl()
      }

    case .fmdxCapabilities(let capabilities):
      fmdxCapabilities = capabilities
      hasFMDXCapabilitySnapshot = true
      if settings.mode == .am && !capabilities.supportsAM {
        settings.mode = .fm
        settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.preferredTuneStepHz, mode: .fm)
        isShowingFMDXTuneConfirmationWarning = false
        fmdxTuneWarningText = L10n.text("fmdx.band.am_not_supported")
        persistSettings()
      }
      if activeBackend == .fmDxWebserver, state == .connected {
        applyCurrentSettingsToConnectedBackend()
      }

    case .fmdxPresets(let presets, let source):
      fmdxServerPresets = presets
      fmdxPresetSourceDescription = source
      persistCachedReceiverData { cached in
        cached.fmdxServerPresets = presets
      }
      if activeBackend == .fmDxWebserver {
        serverBookmarks = presets
      }

    case .fmdx(let telemetry):
      let previousTelemetry = fmdxTelemetry
      let previousStationTitle = preferredHistoryStationTitle(
        backend: .fmDxWebserver,
        telemetry: previousTelemetry
      )
      fmdxTelemetry = telemetry
      lastFMDXTelemetryAppliedAt = Date()
      lastFMDXTelemetryRevision &+= 1
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
      reconcilePendingFMDXAudioModeState(with: telemetry)
      logFMDXAudioModeChangeIfNeeded(previous: previousTelemetry, current: telemetry)
      if let frequencyMHz = telemetry.frequencyMHz {
        let backendFrequencyHz = normalizeFMDXReportedFrequencyHz(fromMHz: frequencyMHz)
        let backendMode = inferredFMDXMode(for: backendFrequencyHz)
        if let pending = pendingFMDXTuneFrequencyHz,
          abs(backendFrequencyHz - pending) < 1_000 {
          clearFMDXTuneConfirmationState()
        }
        if settings.mode != backendMode {
          Diagnostics.log(
            category: "FMDX",
            message: "Band synchronized from telemetry: previous_mode=\(settings.mode.rawValue) resolved_mode=\(backendMode.rawValue) reported_frequency_hz=\(backendFrequencyHz)"
          )
          settings.mode = backendMode
          settings.tuneStepHz = normalizeFMDXTuneStepHz(settings.preferredTuneStepHz, mode: backendMode)
          changedSettings = true
        }
        if abs(backendFrequencyHz - settings.frequencyHz) >= 1_000 {
          settings.frequencyHz = backendFrequencyHz
          changedSettings = true
        }
        rememberFMDXFrequency(backendFrequencyHz, mode: backendMode)
      }
      if changedSettings {
        persistSettings()
        scheduleListeningHistoryCapture()
      }
      announceRDSChangeIfNeeded(previous: previousTelemetry, current: telemetry)
      let currentStationTitle = preferredHistoryStationTitle(
        backend: .fmDxWebserver,
        telemetry: telemetry
      )
      if !isScannerRunning, currentStationTitle != previousStationTitle, currentStationTitle != nil {
        recordCurrentListeningHistory()
      }
      evaluateAutoFMDXFilterProfile(using: telemetry)

    case .kiwi(let telemetry):
      let previousViewportContext = kiwiWaterfallViewportContext()
      kiwiTelemetry = telemetry
      let normalizedPassband = RadioSessionSettings.normalizedKiwiBandpass(
        telemetry.passband ?? settings.kiwiPassband(for: settings.mode, sampleRateHz: telemetry.sampleRateHz),
        mode: settings.mode,
        sampleRateHz: telemetry.sampleRateHz
      )
      if settings.kiwiPassband(for: settings.mode, sampleRateHz: telemetry.sampleRateHz) != normalizedPassband {
        settings.setKiwiPassband(
          normalizedPassband,
          for: settings.mode,
          sampleRateHz: telemetry.sampleRateHz
        )
        persistSettings()
      }
      if previousViewportContext != kiwiWaterfallViewportContext(),
        activeBackend == .kiwiSDR,
        state == .connected {
        sendKiwiWaterfallControl()
      }
      NowPlayingMetadataController.shared.setTitle(nil)
    }
  }

  private func currentChannelScannerSignalProbe(for backend: SDRBackend?) -> ChannelScannerSignalProbe {
    switch backend {
    case .fmDxWebserver:
      if let signal = fmdxTelemetry?.signal {
        return ChannelScannerSignalProbe(
          signal: signal,
          rawSignal: signal,
          state: "fmdx-telemetry",
          filterState: nil
        )
      }
      return ChannelScannerSignalProbe(
        signal: nil,
        rawSignal: nil,
        state: "missing-fmdx-telemetry",
        filterState: nil
      )

    case .kiwiSDR:
      if let signal = kiwiTelemetry?.rssiDBm {
        let filterState = channelScannerInterferenceFilterState(for: .kiwiSDR)
        return ChannelScannerSignalProbe(
          signal: filterState?.hasPrefix("filter=rejected:") == true ? nil : signal,
          rawSignal: signal,
          state: "kiwi-rssi",
          filterState: filterState
        )
      }
      return ChannelScannerSignalProbe(
        signal: nil,
        rawSignal: nil,
        state: "missing-kiwi-rssi",
        filterState: nil
      )

    case .openWebRX:
      let snapshot = SharedAudioOutput.engine.runtimeSnapshot()
      guard let level = snapshot.recentLevelDBFS else {
        return ChannelScannerSignalProbe(
          signal: nil,
          rawSignal: nil,
          state: "missing-audio-level",
          filterState: nil
        )
      }
      guard let age = snapshot.secondsSinceLastLevelSample else {
        return ChannelScannerSignalProbe(
          signal: nil,
          rawSignal: level,
          state: "missing-audio-timestamp",
          filterState: nil
        )
      }
      guard age <= 0.8 else {
        return ChannelScannerSignalProbe(
          signal: nil,
          rawSignal: level,
          state: "stale-audio-sample age=\(String(format: "%.2f", age))s",
          filterState: nil
        )
      }
      let filterState = channelScannerInterferenceFilterState(for: .openWebRX)
      return ChannelScannerSignalProbe(
        signal: filterState?.hasPrefix("filter=rejected:") == true ? nil : level,
        rawSignal: level,
        state: "openwebrx-audio",
        filterState: filterState
      )

    case .none:
      return ChannelScannerSignalProbe(
        signal: nil,
        rawSignal: nil,
        state: "no-backend",
        filterState: nil
      )
    }
  }

  private func currentScannerSignal(for backend: SDRBackend?) -> Double? {
    currentChannelScannerSignalProbe(for: backend).signal
  }

  private func channelScannerInterferenceFilterState(for backend: SDRBackend) -> String? {
    guard settings.filterChannelScannerInterferenceEnabled else { return nil }
    guard backend == .kiwiSDR || backend == .openWebRX else { return nil }

    let filterProfile = settings.channelScannerInterferenceFilterProfile
    let thresholds = channelScannerInterferenceFilterThresholds(for: filterProfile)
    let snapshot = SharedAudioOutput.engine.runtimeSnapshot()
    guard let age = snapshot.secondsSinceLastLevelSample, age <= thresholds.maximumSampleAgeSeconds else {
      return nil
    }
    guard snapshot.recentAnalysisBufferCount >= thresholds.minimumAnalysisBuffers else {
      return nil
    }
    guard
      let envelopeVariation = snapshot.recentEnvelopeVariation,
      let zeroCrossingRate = snapshot.recentZeroCrossingRate,
      let spectralActivity = snapshot.recentSpectralActivity,
      let levelStdDB = snapshot.recentLevelStdDB
    else {
      return nil
    }

    let metrics =
      "profile=\(filterProfile.rawValue),std=\(formattedScannerMetric(levelStdDB)),env=\(formattedScannerMetric(envelopeVariation)),zcr=\(formattedScannerMetric(zeroCrossingRate)),texture=\(formattedScannerMetric(spectralActivity)),buffers=\(snapshot.recentAnalysisBufferCount)"

    if levelStdDB <= thresholds.stationaryEnvelopeLevelStdDB,
      envelopeVariation <= thresholds.stationaryEnvelopeVariation {
      return "filter=rejected:stationary-envelope,\(metrics)"
    }

    if levelStdDB <= thresholds.lowFrequencyHumLevelStdDB,
      zeroCrossingRate <= thresholds.lowFrequencyHumZeroCrossingRate,
      spectralActivity <= thresholds.lowFrequencyHumSpectralActivity {
      return "filter=rejected:low-frequency-hum,\(metrics)"
    }

    if levelStdDB <= thresholds.widebandStaticLevelStdDB,
      envelopeVariation <= thresholds.widebandStaticEnvelopeVariation,
      zeroCrossingRate >= thresholds.widebandStaticMinimumZeroCrossingRate,
      spectralActivity >= thresholds.widebandStaticMinimumSpectralActivity {
      return "filter=rejected:wideband-static,\(metrics)"
    }

    return nil
  }

  private func channelScannerInterferenceFilterThresholds(
    for profile: ChannelScannerInterferenceFilterProfile
  ) -> ChannelScannerInterferenceFilterThresholds {
    switch profile {
    case .gentle:
      return ChannelScannerInterferenceFilterThresholds(
        minimumAnalysisBuffers: 4,
        maximumSampleAgeSeconds: 0.8,
        stationaryEnvelopeLevelStdDB: 0.70,
        stationaryEnvelopeVariation: 0.18,
        lowFrequencyHumLevelStdDB: 0.95,
        lowFrequencyHumZeroCrossingRate: 0.028,
        lowFrequencyHumSpectralActivity: 0.18,
        widebandStaticLevelStdDB: 0.60,
        widebandStaticEnvelopeVariation: 0.30,
        widebandStaticMinimumZeroCrossingRate: 0.23,
        widebandStaticMinimumSpectralActivity: 1.65
      )
    case .standard:
      return ChannelScannerInterferenceFilterThresholds(
        minimumAnalysisBuffers: 3,
        maximumSampleAgeSeconds: 0.8,
        stationaryEnvelopeLevelStdDB: 0.90,
        stationaryEnvelopeVariation: 0.24,
        lowFrequencyHumLevelStdDB: 1.20,
        lowFrequencyHumZeroCrossingRate: 0.035,
        lowFrequencyHumSpectralActivity: 0.25,
        widebandStaticLevelStdDB: 0.75,
        widebandStaticEnvelopeVariation: 0.42,
        widebandStaticMinimumZeroCrossingRate: 0.18,
        widebandStaticMinimumSpectralActivity: 1.35
      )
    case .strong:
      return ChannelScannerInterferenceFilterThresholds(
        minimumAnalysisBuffers: 3,
        maximumSampleAgeSeconds: 0.8,
        stationaryEnvelopeLevelStdDB: 1.10,
        stationaryEnvelopeVariation: 0.30,
        lowFrequencyHumLevelStdDB: 1.45,
        lowFrequencyHumZeroCrossingRate: 0.045,
        lowFrequencyHumSpectralActivity: 0.33,
        widebandStaticLevelStdDB: 0.95,
        widebandStaticEnvelopeVariation: 0.50,
        widebandStaticMinimumZeroCrossingRate: 0.15,
        widebandStaticMinimumSpectralActivity: 1.15
      )
    }
  }

  private func isFMDXTuned(to frequencyHz: Int) -> Bool {
    guard let frequencyMHz = fmdxTelemetry?.frequencyMHz else { return false }
    let reportedHz = normalizeFMDXReportedFrequencyHz(fromMHz: frequencyMHz)
    return abs(reportedHz - frequencyHz) <= 2_000
  }

  private func defaultScannerThreshold(for backend: SDRBackend) -> Double {
    switch backend {
    case .fmDxWebserver:
      return 20
    case .kiwiSDR:
      return -95
    case .openWebRX:
      return -42
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

  private func updateBackendStatusText(_ value: String?) {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalValue = (normalized?.isEmpty == false) ? normalized : nil
    guard backendStatusText != finalValue else { return }
    backendStatusText = finalValue
  }

  private func scheduleRestoreAfterConnection(
    profileID: UUID,
    frequencyHz: Int?,
    mode: DemodulationMode?
  ) {
    guard frequencyHz != nil || mode != nil else { return }

    deferredRestoreTask?.cancel()
    deferredRestoreTask = Task { [weak self] in
      guard let self else { return }
      let deadline = Date().addingTimeInterval(10)

      while !Task.isCancelled && Date() < deadline {
        if self.state == .connected,
          self.connectedProfileID == profileID,
          !self.isWaitingForInitialServerTuningSync() {
          if let mode {
            self.setMode(mode)
          }
          if let frequencyHz {
            self.setFrequencyHz(frequencyHz)
          }
          return
        }

        try? await Task.sleep(nanoseconds: deferredRestorePollNanoseconds)
      }
    }
  }

  private func scheduleInitialTuningFallbackAfterConnection(profileID: UUID) {
    initialTuningFallbackTask?.cancel()

    initialTuningFallbackTask = Task { [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        if Date() >= self.initialServerTuningSyncDeadline {
          break
        }
        try? await Task.sleep(nanoseconds: self.deferredRestorePollNanoseconds)
      }

      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard self.state == .connected else { return }
        guard self.connectedProfileID == profileID else { return }
        guard self.activeBackend == .kiwiSDR || self.activeBackend == .openWebRX else { return }
        guard !self.hasInitialServerTuningSync else { return }
        guard Date() >= self.initialServerTuningSyncDeadline else { return }

        Diagnostics.log(
          category: "Session",
          message: "Initial server tuning sync timed out; applying local tuning fallback."
        )
        self.applyCurrentSettingsToConnectedBackend()
      }
    }
  }

  private func scheduleListeningHistoryCapture(delaySeconds: TimeInterval = 4.0) {
    guard state == .connected else { return }
    guard currentConnectedProfile != nil else { return }
    guard !isScannerRunning else { return }

    listeningHistoryCaptureTask?.cancel()
    listeningHistoryCaptureTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
      if Task.isCancelled { return }
      await MainActor.run {
        self?.recordCurrentListeningHistory()
      }
    }
  }

  private func scheduleRecentFrequencyCapture(delaySeconds: TimeInterval = 0.45) {
    guard state == .connected else { return }
    guard currentConnectedProfile != nil else { return }
    guard !isScannerRunning else { return }
    guard settings.showRecentFrequencies else { return }
    guard !isWaitingForInitialServerTuningSync() else { return }

    recentFrequencyCaptureTask?.cancel()
    recentFrequencyCaptureTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
      if Task.isCancelled { return }
      await MainActor.run {
        self?.recordCurrentRecentFrequency()
      }
    }
  }

  private func recordCurrentListeningHistory() {
    guard state == .connected else { return }
    guard !isScannerRunning else { return }
    guard let profile = currentConnectedProfile else { return }
    guard connectedProfileID == profile.id else { return }
    guard !isWaitingForInitialServerTuningSync() else { return }

    historyStore.recordListening(
      profile: profile,
      frequencyHz: settings.frequencyHz,
      mode: settings.mode,
      stationTitle: preferredHistoryStationTitle(
        backend: profile.backend,
        telemetry: fmdxTelemetry
      )
    )
  }

  private func recordCurrentRecentFrequency() {
    guard state == .connected else { return }
    guard !isScannerRunning else { return }
    guard let profile = currentConnectedProfile else { return }
    guard connectedProfileID == profile.id else { return }
    guard !isWaitingForInitialServerTuningSync() else { return }

    historyStore.recordRecentFrequency(
      profile: profile,
      frequencyHz: settings.frequencyHz,
      mode: settings.mode,
      stationTitle: preferredRecentFrequencyStationTitle(
        backend: profile.backend,
        telemetry: fmdxTelemetry
      )
    )
  }

  private func preferredHistoryStationTitle(
    backend: SDRBackend,
    telemetry: FMDXTelemetry?
  ) -> String? {
    switch backend {
    case .fmDxWebserver:
      return preferredRDSStationName(from: telemetry) ?? stableRDSRadioText(from: telemetry)

    case .openWebRX:
      if let bookmark = serverBookmarks.first(where: { $0.frequencyHz == settings.frequencyHz }) {
        return bookmark.name
      }
      return openWebRXBandEntry(for: settings.frequencyHz)?.name

    case .kiwiSDR:
      return currentKiwiBandName
    }
  }

  private func preferredRecentFrequencyStationTitle(
    backend: SDRBackend,
    telemetry: FMDXTelemetry?
  ) -> String? {
    switch backend {
    case .fmDxWebserver:
      guard isFMDXTelemetryAlignedWithCurrentFrequency(telemetry) else { return nil }
      return preferredRDSStationName(from: telemetry) ?? stableRDSRadioText(from: telemetry)

    case .openWebRX, .kiwiSDR:
      return preferredHistoryStationTitle(backend: backend, telemetry: telemetry)
    }
  }

  private func isFMDXTelemetryAlignedWithCurrentFrequency(_ telemetry: FMDXTelemetry?) -> Bool {
    guard let telemetryFrequencyMHz = telemetry?.frequencyMHz else { return false }
    let telemetryFrequencyHz = Int((telemetryFrequencyMHz * 1_000_000.0).rounded())
    return abs(telemetryFrequencyHz - settings.frequencyHz) <= 50_000
  }

  private func hydrateCachedReceiverData(for profile: SDRConnectionProfile) {
    guard let cached = receiverDataCache.cachedData(for: ReceiverIdentity.key(for: profile)) else {
      return
    }

    channelScannerResults = cached.savedChannelScannerResults

    switch profile.backend {
    case .openWebRX:
      openWebRXProfiles = cached.openWebRXProfiles
      selectedOpenWebRXProfileID = cached.selectedOpenWebRXProfileID
      lastOpenWebRXBookmark = cached.lastOpenWebRXBookmark
      serverBookmarks = cached.serverBookmarks
      openWebRXBandPlan = cached.openWebRXBandPlan

    case .fmDxWebserver:
      fmdxServerPresets = cached.fmdxServerPresets

    case .kiwiSDR:
      break
    }
  }

  private func persistCachedReceiverData(_ mutate: (inout CachedReceiverData) -> Void) {
    guard let activeProfileCacheKey else { return }
    receiverDataCache.update(receiverID: activeProfileCacheKey, mutate: mutate)
  }

  private func rememberOpenWebRXBookmark(_ bookmark: SDRServerBookmark) {
    lastOpenWebRXBookmark = bookmark
    persistCachedReceiverData { cached in
      cached.lastOpenWebRXBookmark = bookmark
    }
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

  private var fmDxOverallFrequencyRangeHz: ClosedRange<Int> {
    fmDxAMMinFrequencyHz...fmDxFMMaxFrequencyHz
  }

  private func preferredFMDXFrequency(for mode: DemodulationMode) -> Int {
    switch mode {
    case .am:
      return preferredFMDXFrequency(for: preferredFMDXQuickBand(for: .am))
    default:
      return preferredFMDXFrequency(for: preferredFMDXQuickBand(for: .fm))
    }
  }

  private func preferredFMDXFrequency(for band: FMDXQuickBand) -> Int {
    let preferred: Int
    switch band {
    case .lw:
      preferred = lastFMDXLWFrequencyHz
    case .mw:
      preferred = lastFMDXMWFrequencyHz
    case .sw:
      preferred = lastFMDXSWFrequencyHz
    case .oirt:
      preferred = lastFMDXOIRTFrequencyHz
    case .fm:
      preferred = lastFMDXBroadcastFMFrequencyHz
    }

    return band.rangeHz.contains(preferred) ? preferred : band.defaultFrequencyHz
  }

  private func preferredFMDXQuickBand(for mode: DemodulationMode) -> FMDXQuickBand {
    switch mode {
    case .am:
      return lastSelectedFMDXAMQuickBand.isAM ? lastSelectedFMDXAMQuickBand : .mw
    default:
      return lastSelectedFMDXFMQuickBand.isAM ? .fm : lastSelectedFMDXFMQuickBand
    }
  }

  private func noteSelectedFMDXQuickBand(_ band: FMDXQuickBand) {
    switch band.mode {
    case .am:
      lastSelectedFMDXAMQuickBand = band
    default:
      lastSelectedFMDXFMQuickBand = band
    }
  }

  private func rememberFMDXFrequency(_ frequencyHz: Int, mode: DemodulationMode) {
    let band = fmdxQuickBand(for: frequencyHz, mode: mode)

    switch mode {
    case .am:
      guard fmdxFrequencyRange(for: .am).contains(frequencyHz) else { return }
    default:
      guard fmdxFrequencyRange(for: .fm).contains(frequencyHz) else { return }
    }

    switch band {
    case .lw:
      lastFMDXLWFrequencyHz = frequencyHz
    case .mw:
      lastFMDXMWFrequencyHz = frequencyHz
    case .sw:
      lastFMDXSWFrequencyHz = frequencyHz
    case .oirt:
      lastFMDXOIRTFrequencyHz = frequencyHz
    case .fm:
      lastFMDXBroadcastFMFrequencyHz = frequencyHz
    }

    noteSelectedFMDXQuickBand(band)
  }

  private func seedFMDXBandMemory() {
    if fmdxFrequencyRange(for: .am).contains(settings.frequencyHz) {
      rememberFMDXFrequency(settings.frequencyHz, mode: .am)
    }
    if fmdxFrequencyRange(for: .fm).contains(settings.frequencyHz) {
      rememberFMDXFrequency(settings.frequencyHz, mode: .fm)
    }
  }

  private func resetSessionDiagnostics() {
    connectedSince = .distantPast
    automaticReconnectAttempts = 0
    automaticReconnectSuccesses = 0
    sharedAudioSampleCount = 0
    sharedAudioPeakQueuedBuffers = 0
    sharedAudioPeakEnqueueGapSeconds = 0
    lastSharedAudioBufferLogAt = .distantPast
    lastSharedAudioLoggedQueue = -1
    lastSharedAudioLoggedGapSeconds = -1
    lastSharedAudioLoggedRunning = false
    lastSharedAudioLoggedStartError = nil
    fmdxAudioSampleCount = 0
    fmdxPeakQueuedDurationSeconds = 0
    fmdxPeakQueuedBuffers = 0
    fmdxPeakOutputGapSeconds = 0
    fmdxLatencyTrimEvents = 0
    lastFMDXLatencyTrimLoggedAt = .distantPast
    lastFMDXBufferLogAt = .distantPast
    lastFMDXLoggedQueueStarted = false
    lastFMDXLoggedQueuedDurationSeconds = -1
    lastFMDXLoggedQueuedBuffers = -1
    lastFMDXLoggedOutputGapSeconds = -1
  }

  private func captureAudioDiagnosticsSampleIfNeeded() {
    switch activeBackend {
    case .fmDxWebserver:
      captureFMDXAudioDiagnosticsSample()
    case .openWebRX, .kiwiSDR:
      captureSharedAudioDiagnosticsSample()
    case .none:
      break
    }
  }

  private func captureSharedAudioDiagnosticsSample() {
    let snapshot = SharedAudioOutput.engine.runtimeSnapshot()
    sharedAudioSampleCount += 1
    sharedAudioPeakQueuedBuffers = max(sharedAudioPeakQueuedBuffers, snapshot.queuedBuffers)
    if let secondsSinceLastEnqueue = snapshot.secondsSinceLastEnqueue {
      sharedAudioPeakEnqueueGapSeconds = max(sharedAudioPeakEnqueueGapSeconds, secondsSinceLastEnqueue)
    }

    let now = Date()
    let enqueueGapSeconds = snapshot.secondsSinceLastEnqueue ?? 0
    let logIntervalSeconds: TimeInterval
    switch runtimePolicy {
    case .interactive:
      logIntervalSeconds = 15
    case .passive:
      logIntervalSeconds = 25
    case .background:
      logIntervalSeconds = 45
    }

    let queueChangedSignificantly = abs(snapshot.queuedBuffers - lastSharedAudioLoggedQueue) >= 2
    let gapChangedSignificantly = abs(enqueueGapSeconds - lastSharedAudioLoggedGapSeconds) >= 0.35
    let engineChanged = sharedAudioSampleCount == 1 || snapshot.engineRunning != lastSharedAudioLoggedRunning
    let queueGapAlert = enqueueGapSeconds >= 0.8
    let shouldLog = engineChanged
      || queueChangedSignificantly
      || queueGapAlert
      || (gapChangedSignificantly && enqueueGapSeconds >= 0.35)
      || snapshot.lastStartError != lastSharedAudioLoggedStartError
      || now.timeIntervalSince(lastSharedAudioBufferLogAt) >= logIntervalSeconds

    guard shouldLog else { return }

    Diagnostics.log(
      category: "Shared Audio",
      message: String(
        format: "Buffer snapshot: running=%@ queued=%.2fs/%d enqueue_gap=%.2fs in=%@Hz out=%dHz session=%@ peak_buffers=%d peak_gap=%.2fs",
        snapshot.engineRunning ? "true" : "false",
        snapshot.queuedDurationSeconds,
        snapshot.queuedBuffers,
        enqueueGapSeconds,
        snapshot.lastInputSampleRateHz.map(String.init) ?? "n/a",
        snapshot.outputSampleRateHz,
        snapshot.sessionConfigured ? "true" : "false",
        sharedAudioPeakQueuedBuffers,
        sharedAudioPeakEnqueueGapSeconds
      )
    )
    if let lastStartError = snapshot.lastStartError,
      !lastStartError.isEmpty,
      lastStartError != lastSharedAudioLoggedStartError {
      Diagnostics.log(
        severity: .warning,
        category: "Shared Audio",
        message: "Last start error snapshot: \(lastStartError)"
      )
    }

    lastSharedAudioBufferLogAt = now
    lastSharedAudioLoggedQueue = snapshot.queuedBuffers
    lastSharedAudioLoggedGapSeconds = enqueueGapSeconds
    lastSharedAudioLoggedRunning = snapshot.engineRunning
    lastSharedAudioLoggedStartError = snapshot.lastStartError
  }

  private func captureFMDXAudioDiagnosticsSample() {
    let snapshot = FMDXMP3AudioPlayer.shared.runtimeSnapshot()
    fmdxAudioSampleCount += 1
    fmdxPeakQueuedDurationSeconds = max(fmdxPeakQueuedDurationSeconds, snapshot.queuedDurationSeconds)
    fmdxPeakQueuedBuffers = max(fmdxPeakQueuedBuffers, snapshot.queuedBufferCount)
    fmdxPeakOutputGapSeconds = max(fmdxPeakOutputGapSeconds, snapshot.secondsSinceLastAudioOutput)

    let now = Date()
    if let trimAge = snapshot.secondsSinceLastLatencyTrim,
      trimAge <= 1.5,
      now.timeIntervalSince(lastFMDXLatencyTrimLoggedAt) >= 4 {
      fmdxLatencyTrimEvents += 1
      lastFMDXLatencyTrimLoggedAt = now
    }

    let logIntervalSeconds: TimeInterval
    switch runtimePolicy {
    case .interactive:
      logIntervalSeconds = 15
    case .passive:
      logIntervalSeconds = 25
    case .background:
      logIntervalSeconds = 45
    }

    let queueChangedSignificantly = abs(snapshot.queuedBufferCount - lastFMDXLoggedQueuedBuffers) >= 2
    let durationChangedSignificantly = abs(snapshot.queuedDurationSeconds - lastFMDXLoggedQueuedDurationSeconds) >= 0.25
    let gapChangedSignificantly = abs(snapshot.secondsSinceLastAudioOutput - lastFMDXLoggedOutputGapSeconds) >= 0.25
    let queueGapAlert = snapshot.secondsSinceLastAudioOutput >= 0.9
      || snapshot.queuedDurationSeconds >= 0.9
      || snapshot.queuedBufferCount >= 6
      || (snapshot.secondsSinceLastLatencyTrim ?? 999) <= 2
    let shouldLog = fmdxAudioSampleCount == 1
      || snapshot.queueStarted != lastFMDXLoggedQueueStarted
      || queueChangedSignificantly
      || durationChangedSignificantly
      || (gapChangedSignificantly && snapshot.secondsSinceLastAudioOutput >= 0.4)
      || queueGapAlert
      || now.timeIntervalSince(lastFMDXBufferLogAt) >= logIntervalSeconds

    guard shouldLog else { return }

    let trimText = snapshot.secondsSinceLastLatencyTrim.map {
      String(format: "%.2fs", $0)
    } ?? "n/a"
    let qualityText = fmdxAudioQualityReport.map {
      "\($0.score)/100"
    } ?? "n/a"
    Diagnostics.log(
      category: "FM-DX Audio",
      message: String(
        format: "Buffer snapshot: started=%@ queued=%.2fs buffers=%d gap=%.2fs trim_age=%@ quality=%@ peak_queue=%.2fs peak_buffers=%d peak_gap=%.2fs trims=%d",
        snapshot.queueStarted ? "true" : "false",
        snapshot.queuedDurationSeconds,
        snapshot.queuedBufferCount,
        snapshot.secondsSinceLastAudioOutput,
        trimText,
        qualityText,
        fmdxPeakQueuedDurationSeconds,
        fmdxPeakQueuedBuffers,
        fmdxPeakOutputGapSeconds,
        fmdxLatencyTrimEvents
      )
    )

    lastFMDXBufferLogAt = now
    lastFMDXLoggedQueueStarted = snapshot.queueStarted
    lastFMDXLoggedQueuedDurationSeconds = snapshot.queuedDurationSeconds
    lastFMDXLoggedQueuedBuffers = snapshot.queuedBufferCount
    lastFMDXLoggedOutputGapSeconds = snapshot.secondsSinceLastAudioOutput
  }

  private func resetRuntimeState(for backend: SDRBackend?) {
    resetSessionDiagnostics()
    _ = backend
    openWebRXProfiles = []
    selectedOpenWebRXProfileID = nil
    lastOpenWebRXBookmark = nil
    serverBookmarks = []
    openWebRXBandPlan = []
    currentKiwiBandName = nil
    channelScannerResults = []
    fmdxTelemetry = nil
    lastFMDXTelemetryAppliedAt = .distantPast
    lastFMDXTelemetryRevision = 0
    clearPendingFMDXAudioModeState()
    fmdxCapabilities = .empty
    hasFMDXCapabilitySnapshot = false
    fmdxServerPresets = []
    fmdxPresetSourceDescription = nil
    selectedFMDXAntennaID = nil
    selectedFMDXBandwidthID = nil
    kiwiTelemetry = nil
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    clearFMDXTuneConfirmationState()
    kiwiPassbandDebounceTask?.cancel()
    kiwiPassbandDebounceTask = nil
    kiwiNoiseDebounceTask?.cancel()
    kiwiNoiseDebounceTask = nil
    initialTuningFallbackTask?.cancel()
    initialTuningFallbackTask = nil
    autoFilterPendingProfile = nil
    autoFilterStableSamples = 0
    suppressAutoFilterUntil = Date.distantPast
    hasInitialServerTuningSync = false
    initialServerTuningSyncDeadline = Date.distantPast
    lastRDSAnnouncementText = nil
    lastRDSAnnouncementAt = Date.distantPast
    lastRDSAnnouncementKind = nil
    fmdxAudioQualityReport = nil
    fmdxAudioQualityTrend = []
    audioPresetSuggestion = nil
    lastLoggedAudioSuggestionPreset = nil
    lastLoggedFMDXAudioQualityLevel = nil
    lastFMDXAudioQualitySampleAt = .distantPast
    if backend != .fmDxWebserver {
      NowPlayingMetadataController.shared.setTitle(nil)
    }
  }

  private func reconcilePendingFMDXAudioModeState(with telemetry: FMDXTelemetry) {
    guard let pendingFMDXAudioModeIsStereo else { return }

    if telemetry.audioMode?.isStereo == pendingFMDXAudioModeIsStereo || Date() >= pendingFMDXAudioModeDeadline {
      clearPendingFMDXAudioModeState()
    }
  }

  private func clearPendingFMDXAudioModeState() {
    pendingFMDXAudioModeIsStereo = nil
    pendingFMDXAudioModeDeadline = .distantPast
  }

  private func logFMDXAudioModeChangeIfNeeded(previous: FMDXTelemetry?, current: FMDXTelemetry) {
    guard previous?.audioMode != current.audioMode || previous?.isForcedStereo != current.isForcedStereo else {
      return
    }

    guard let mode = current.audioMode else { return }

    let forcedState = (current.isForcedStereo ?? false) ? "forced" : "auto"
    Diagnostics.log(
      category: "FM-DX",
      message: "Audio mode confirmed by server: \(mode.rawValue) (\(forcedState))"
    )
  }

  private func refreshFMDXAudioAnalysis(forceLog: Bool) {
    let qualityReport = makeFMDXAudioQualityReport()
    fmdxAudioQualityReport = qualityReport
    updateFMDXAudioQualityTrend(with: qualityReport)
    logFMDXAudioQualityTransitionIfNeeded(qualityReport, forceLog: forceLog)

    let suggestion = makeFMDXAudioPresetSuggestion(from: qualityReport)
    audioPresetSuggestion = suggestion

    guard let suggestion else {
      lastLoggedAudioSuggestionPreset = nil
      return
    }

    guard forceLog || lastLoggedAudioSuggestionPreset != suggestion.preset else { return }
    lastLoggedAudioSuggestionPreset = suggestion.preset
    Diagnostics.log(
      category: "Audio Suggestion",
      message: L10n.text(
        "settings.audio.suggestion.log.recommended",
        suggestion.preset.localizedTitle,
        suggestion.localizedReason
      )
    )
  }

  private func makeFMDXAudioQualityReport() -> FMDXAudioQualityReport? {
    guard state == .connected else { return nil }
    guard activeBackend == .fmDxWebserver else { return nil }

    let snapshot = FMDXMP3AudioPlayer.shared.runtimeSnapshot()
    guard snapshot.queueStarted || snapshot.secondsSinceLastAudioOutput < 12 else { return nil }

    var score = 100
    let outputGap = snapshot.secondsSinceLastAudioOutput
    let queuedDuration = snapshot.queuedDurationSeconds
    let queuedBuffers = snapshot.queuedBufferCount
    let signal = fmdxTelemetry?.signal

    if outputGap > 3.0 {
      score -= 55
    } else if outputGap > 1.8 {
      score -= 30
    } else if outputGap > 0.9 {
      score -= 12
    }

    if let trimAge = snapshot.secondsSinceLastLatencyTrim {
      if trimAge < 12 {
        score -= 28
      } else if trimAge < 25 {
        score -= 14
      }
    }

    if queuedDuration >= 1.40 || queuedBuffers >= 9 {
      score -= 24
    } else if queuedDuration >= 1.00 || queuedBuffers >= 7 {
      score -= 14
    } else if queuedDuration >= 0.70 || queuedBuffers >= 5 {
      score -= 6
    }

    if let signal {
      if signal < 12 {
        score -= 16
      } else if signal < 22 {
        score -= 8
      } else if signal > 50 {
        score += 3
      }
    }

    score = min(100, max(0, score))

    let level: FMDXAudioQualityLevel
    let summaryKey: String
    switch score {
    case 90...100:
      level = .excellent
      summaryKey = "diagnostics.audio_quality.summary.excellent"
    case 75...89:
      level = .good
      summaryKey = "diagnostics.audio_quality.summary.good"
    case 55...74:
      level = .fair
      summaryKey = "diagnostics.audio_quality.summary.fair"
    case 35...54:
      level = .poor
      summaryKey = "diagnostics.audio_quality.summary.poor"
    default:
      level = .critical
      summaryKey = "diagnostics.audio_quality.summary.critical"
    }

    return FMDXAudioQualityReport(
      score: score,
      level: level,
      summaryKey: summaryKey,
      queuedDurationSeconds: queuedDuration,
      queuedBufferCount: queuedBuffers,
      outputGapSeconds: outputGap,
      latencyTrimAgeSeconds: snapshot.secondsSinceLastLatencyTrim,
      signalDBf: signal
    )
  }

  private func logFMDXAudioQualityTransitionIfNeeded(
    _ qualityReport: FMDXAudioQualityReport?,
    forceLog: Bool
  ) {
    guard let qualityReport else {
      lastLoggedFMDXAudioQualityLevel = nil
      return
    }

    guard let previousLevel = lastLoggedFMDXAudioQualityLevel else {
      lastLoggedFMDXAudioQualityLevel = qualityReport.level
      return
    }

    guard forceLog || previousLevel != qualityReport.level else { return }

    Diagnostics.log(
      category: "Audio Quality",
      message: L10n.text(
        "diagnostics.audio_quality.log.changed",
        previousLevel.localizedTitle,
        qualityReport.level.localizedTitle,
        qualityReport.score
      )
    )
    lastLoggedFMDXAudioQualityLevel = qualityReport.level
  }

  private func updateFMDXAudioQualityTrend(with qualityReport: FMDXAudioQualityReport?) {
    let cutoffDate = Date().addingTimeInterval(-fmdxAudioQualityTrendWindowSeconds)
    fmdxAudioQualityTrend.removeAll { $0.date < cutoffDate }

    guard let qualityReport else { return }

    let now = Date()
    let shouldAppend: Bool
    if let lastSample = fmdxAudioQualityTrend.last {
      let enoughTimePassed = now.timeIntervalSince(lastFMDXAudioQualitySampleAt) >= fmdxAudioQualitySampleIntervalSeconds
      let scoreChanged = abs(lastSample.score - qualityReport.score) >= 5
      let levelChanged = lastSample.level != qualityReport.level
      shouldAppend = enoughTimePassed || scoreChanged || levelChanged
    } else {
      shouldAppend = true
    }

    guard shouldAppend else { return }

    fmdxAudioQualityTrend.append(
      FMDXAudioQualitySample(
        id: UUID(),
        date: now,
        score: qualityReport.score,
        level: qualityReport.level
      )
    )
    lastFMDXAudioQualitySampleAt = now
  }

  private func makeFMDXAudioPresetSuggestion(from qualityReport: FMDXAudioQualityReport?) -> FMDXAudioPresetSuggestion? {
    guard settings.audioSuggestionScope != .off else { return nil }
    guard state == .connected else { return nil }

    switch settings.audioSuggestionScope {
    case .off:
      return nil
    case .fmDxOnly, .allSupportedBackends:
      guard activeBackend == .fmDxWebserver else { return nil }
    }

    guard let qualityReport else { return nil }

    if qualityReport.outputGapSeconds > 2.5 || qualityReport.level == .critical {
      return FMDXAudioPresetSuggestion(
        preset: .weakServer,
        reasonKey: "settings.audio.suggestion.reason.output_gaps"
      )
    }

    if let trimAge = qualityReport.latencyTrimAgeSeconds, trimAge < 18 {
      return FMDXAudioPresetSuggestion(
        preset: .lowLatency,
        reasonKey: "settings.audio.suggestion.reason.latency_trim"
      )
    }

    if qualityReport.queuedDurationSeconds >= 1.05 || qualityReport.queuedBufferCount >= 7 || qualityReport.level == .poor {
      return FMDXAudioPresetSuggestion(
        preset: .stable,
        reasonKey: "settings.audio.suggestion.reason.large_queue"
      )
    }

    if qualityReport.queuedDurationSeconds <= 0.40 && qualityReport.queuedBufferCount <= 3 && qualityReport.score >= 80 {
      return FMDXAudioPresetSuggestion(
        preset: .lowLatency,
        reasonKey: "settings.audio.suggestion.reason.short_queue"
      )
    }

    return FMDXAudioPresetSuggestion(
      preset: .balanced,
      reasonKey: "settings.audio.suggestion.reason.balanced"
    )
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
    guard !isScannerRunning else { return }
    guard accessibilityState?.isReceiverTabActive ?? true else { return }

    let now = Date()
    guard let announcement = rdsAnnouncement(previous: previous, current: current) else { return }
    if now.timeIntervalSince(lastRDSAnnouncementAt) < minimumAnnouncementInterval(for: announcement.kind) {
      return
    }
    guard announcement.text != lastRDSAnnouncementText || announcement.kind != lastRDSAnnouncementKind else { return }

    lastRDSAnnouncementText = announcement.text
    lastRDSAnnouncementAt = now
    lastRDSAnnouncementKind = announcement.kind
    AppAccessibilityAnnouncementCenter.post(announcement.text)
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

  private func resolvedTuneStepHz(
    _ preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    using profile: BandTuningProfile
  ) -> Int {
    switch preferenceMode {
    case .automatic:
      return profile.defaultStepHz
    case .manual:
      return profile.stepOptionsHz.min(by: { abs($0 - preferredStepHz) < abs($1 - preferredStepHz) })
        ?? profile.defaultStepHz
    }
  }

  private func resolvedTuneStepHz(
    forPreferred preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    backend: SDRBackend?
  ) -> Int {
    guard let backend else { return RadioSessionSettings.normalizedTuneStep(preferredStepHz) }
    return resolvedTuneStepHz(
      RadioSessionSettings.normalizedTuneStep(preferredStepHz),
      preferenceMode: preferenceMode,
      using: tuningBandProfile(for: backend)
    )
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
    let resolvedStep = resolvedTuneStepHz(
      settings.preferredTuneStepHz,
      preferenceMode: settings.tuneStepPreferenceMode,
      using: profile
    )
    guard settings.tuneStepHz != resolvedStep else { return false }
    settings.tuneStepHz = resolvedStep
    Diagnostics.log(
      category: "Session",
      message: "Tune step adjusted to \(resolvedStep) Hz for band profile \(profile.id) (mode=\(settings.tuneStepPreferenceMode.rawValue))"
    )
    return true
  }
}
