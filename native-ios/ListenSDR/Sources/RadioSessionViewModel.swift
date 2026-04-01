import Foundation
import Combine
import ListenSDRCore
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

private struct PendingWidebandTuneConfirmation: Equatable {
  let backend: SDRBackend
  let frequencyHz: Int
  let mode: DemodulationMode
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
  case stationName
  case programService
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
  private let fmDxFMMaxFrequencyHz = 162_550_000
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
  private var pendingWidebandTuneConfirmation: PendingWidebandTuneConfirmation?
  private var widebandTuneConfirmationTask: Task<Void, Never>?
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
  private let rdsAnnouncementGate = StableAnnouncementGate<RDSAnnouncementKind>(
    stabilityInterval: { kind in
      switch kind {
      case .stationName:
        return 0.30
      case .programService:
        return 0.36
      case .radioText:
        return 0.65
      case .pi:
        return 0.40
      }
    },
    minimumInterval: { kind in
      switch kind {
      case .stationName:
        return 0.9
      case .programService:
        return 1.15
      case .radioText:
        return 1.7
      case .pi:
        return 1.3
      }
    }
  )
  private var pendingRDSAnnouncement: StableAnnouncementCandidate<RDSAnnouncementKind>?
  private var pendingRDSAnnouncementTask: Task<Void, Never>?
  private var lastPostedRDSAnnouncementText: String?
  private var lastPostedRDSAnnouncementAt = Date.distantPast
  private var lastLoggedAudioSuggestionPreset: FMDXAudioTuningPreset?
  private var lastLoggedFMDXAudioQualityLevel: FMDXAudioQualityLevel?
  private var lastFMDXAudioQualitySampleAt = Date.distantPast
  private let fmdxAudioQualityTrendWindowSeconds: TimeInterval = 60
  private let fmdxAudioQualitySampleIntervalSeconds: TimeInterval = 5
  private var fmdxBandMemory = FMDXBandMemory()
  private var channelScannerSignalPreviewActive = false
  private var activeProfileCacheKey: String?
  private var currentConnectedProfile: SDRConnectionProfile?
  private var listeningHistoryCaptureTask: Task<Void, Never>?
  private var recentFrequencyCaptureTask: Task<Void, Never>?
  private var deferredRestoreTask: Task<Void, Never>?
  private var initialTuningFallbackTask: Task<Void, Never>?
  private let manualReconnectDelayNanoseconds: UInt64 = 120_000_000
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
    SharedAudioOutput.engine.setSpeechLoudnessLeveling(
      mode: settings.accessibilitySpeechLoudnessLevelingMode,
      customProfile: speechLoudnessCustomProfile(from: settings)
    )
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
    let newPolicy = BackendRuntimePolicy(
      BackendRuntimePolicyCore.policy(
        isForegroundActive: isForegroundActive,
        isReceiverTabSelected: selectedTab == .receiver
      )
    )

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
    return [.oirt, .fm, .noaa]
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
    RuntimeAdjustedSettingsCore.effectiveSquelchEnabled(
      storedEnabled: settings.squelchEnabled,
      isLockedByScanner: isOpenWebRXSquelchLockedByScanner
    )
  }

  var effectiveKiwiSquelchEnabled: Bool {
    RuntimeAdjustedSettingsCore.effectiveSquelchEnabled(
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

    if enforceConnectionNetworkPolicyIfNeeded(reason: "connect_request", profile: profile) {
      return
    }

    Diagnostics.log(
      category: "Session",
      message: "Connect requested for \(profile.name) (\(profile.backend.displayName))"
    )

    connectTask?.cancel()
    cancelSessionTransientTasks(resetScannerState: true)
    applySessionLifecyclePresentation(
      SessionLifecyclePresentationCore.presentation(for: .connectRequested),
      profileName: profile.name
    )
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

        let newClient = makeClient(for: profile)
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
          self.hasInitialServerTuningSync = !InitialServerTuningSyncCore.requiresInitialServerTuningSync(for: profile.backend)
          self.initialServerTuningSyncDeadline = InitialServerTuningSyncCore.initialSyncDeadlineSeconds(for: profile.backend)
            .map { Date().addingTimeInterval($0) } ?? .distantPast
          self.connectedSince = Date()
          self.applySessionLifecyclePresentation(
            SessionLifecyclePresentationCore.presentation(
              for: .connected,
              backend: profile.backend
            ),
            profileName: profile.name
          )
          self.startStatusMonitor(
            profile: profile,
            client: newClient
          )
          self.scheduleInitialTuningFallbackAfterConnection(profileID: profile.id)
          self.scheduleListeningHistoryCapture()
          self.performConnectedSessionRestore(
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
          self.applySessionLifecyclePresentation(
            SessionLifecyclePresentationCore.presentation(for: .connectionFailed),
            errorMessage: error.localizedDescription
          )
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
        self.applySessionLifecyclePresentation(
          SessionLifecyclePresentationCore.presentation(for: .disconnected)
        )
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
    setFrequencyHz(bookmark.frequencyHz, source: "bookmark", stationTitle: bookmark.name)
  }

  func restoreLastOpenWebRXBookmark() {
    guard let lastOpenWebRXBookmark else { return }
    applyServerBookmark(lastOpenWebRXBookmark)
  }

  func tuneToBand(_ band: SDRBandPlanEntry, using suggestion: SDRBandFrequency? = nil) {
    let targetHz = suggestion?.frequencyHz ?? band.centerFrequencyHz
    setFrequencyHz(targetHz, source: "band_plan", stationTitle: band.name)

    if let suggestionMode = DemodulationMode.fromOpenWebRX(suggestion?.name.lowercased()) {
      setMode(suggestionMode)
    }
  }

  func scannerSignalUnit(for backend: SDRBackend?) -> String {
    ChannelScannerSignalCore.signalUnit(for: backend)
  }

  func tuneStepOptions(for backend: SDRBackend) -> [Int] {
    tuningBandProfile(for: backend).stepOptionsHz
  }

  func effectiveTuneStepHz(for backend: SDRBackend?) -> Int {
    tuneStepState(
      forPreferred: settings.preferredTuneStepHz,
      preferenceMode: settings.tuneStepPreferenceMode,
      backend: backend
    ).tuneStepHz
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
    setFrequencyHz(frequencyHz, source: "scanner_restore")
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
    ChannelScannerSignalCore.formatMetric(value)
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

  func setFrequencyHz(_ value: Int, source: String = "direct", stationTitle: String? = nil) {
    if isWaitingForInitialServerTuningSync() {
      updateBackendStatusText(L10n.text("session.status.sync_tuning"))
      return
    }

    let backend = activeBackend
    let normalizedFrequencyHz: Int
    if activeBackend == .fmDxWebserver {
      normalizedFrequencyHz = SessionFrequencyCore.normalizedFrequencyHz(
        value,
        backend: .fmDxWebserver,
        mode: settings.mode
      )
      settings.frequencyHz = normalizedFrequencyHz
      rememberFMDXFrequency(settings.frequencyHz, mode: settings.mode)
    } else {
      normalizedFrequencyHz = SessionFrequencyCore.normalizedFrequencyHz(
        value,
        backend: backend,
        mode: settings.mode
      )
      settings.frequencyHz = normalizedFrequencyHz
    }
    logTuneRequest(
      source: source,
      backend: backend,
      requestedFrequencyHz: value,
      normalizedFrequencyHz: normalizedFrequencyHz,
      requestedMode: settings.mode,
      normalizedMode: settings.mode,
      stationTitle: stationTitle
    )
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
      scheduleWidebandTuneConfirmationIfNeeded()
      scheduleListeningHistoryCapture()
      scheduleRecentFrequencyCapture()
      return
    }
    queueFMDXFrequencySend(settings.frequencyHz)
    scheduleListeningHistoryCapture()
    scheduleRecentFrequencyCapture()
  }

  private func logTuneRequest(
    source: String,
    backend: SDRBackend?,
    requestedFrequencyHz: Int,
    normalizedFrequencyHz: Int,
    requestedMode: DemodulationMode,
    normalizedMode: DemodulationMode,
    stationTitle: String? = nil
  ) {
    let backendLabel = backend?.rawValue ?? "unknown"
    let stationFragment = stationTitle.map { " station=\($0)" } ?? ""
    Diagnostics.log(
      severity: .info,
      category: "Tuning",
      message: "Tune requested: source=\(source) backend=\(backendLabel) requested=\(requestedFrequencyHz) normalized=\(normalizedFrequencyHz) requested_mode=\(requestedMode.rawValue) normalized_mode=\(normalizedMode.rawValue)\(stationFragment)"
    )
  }

  func setTuneStepHz(_ value: Int) {
    let state = SessionTuningCore.manualTuneStepState(
      requestedStepHz: value,
      context: optionalTuningBandContext(for: activeBackend)
    )
    settings.tuneStepPreferenceMode = state.preferenceMode
    settings.preferredTuneStepHz = state.preferredTuneStepHz
    settings.tuneStepHz = state.tuneStepHz
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Tune step set to \(state.tuneStepHz) Hz (preferred \(state.preferredTuneStepHz) Hz, requested \(value) Hz, mode=manual)"
    )
  }

  func setTuneStepPreferenceMode(_ mode: TuneStepPreferenceMode) {
    guard settings.tuneStepPreferenceMode != mode else { return }
    let state = tuneStepState(
      forPreferred: settings.preferredTuneStepHz,
      preferenceMode: mode,
      backend: activeBackend
    )
    settings.tuneStepPreferenceMode = state.preferenceMode
    settings.preferredTuneStepHz = state.preferredTuneStepHz
    settings.tuneStepHz = state.tuneStepHz
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Tune step preference changed to \(mode.rawValue) with resolved step \(settings.tuneStepHz) Hz"
    )
  }

  func setFrequencyEntryCommitMode(_ mode: FrequencyEntryCommitMode) {
    guard settings.frequencyEntryCommitMode != mode else { return }
    settings.frequencyEntryCommitMode = mode
    persistSettings()
    Diagnostics.log(
      category: "Session",
      message: "Frequency entry commit mode set to \(mode.rawValue)"
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

  func setTuneConfirmationWarningsEnabled(_ enabled: Bool) {
    guard settings.tuneConfirmationWarningsEnabled != enabled else { return }
    settings.tuneConfirmationWarningsEnabled = enabled
    if !enabled {
      clearPendingWidebandTuneConfirmation()
      if isShowingFMDXTuneConfirmationWarning {
        isShowingFMDXTuneConfirmationWarning = false
        fmdxTuneWarningText = nil
      }
    }
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setFMDXTuneConfirmationWarningsEnabled(_ enabled: Bool) {
    setTuneConfirmationWarningsEnabled(enabled)
  }

  func setOpenReceiverAfterHistoryRestore(_ enabled: Bool) {
    guard settings.openReceiverAfterHistoryRestore != enabled else { return }
    settings.openReceiverAfterHistoryRestore = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setShowRecentFrequencies(_ enabled: Bool) {
    guard settings.showRecentFrequencies != enabled else { return }
    settings.showRecentFrequencies = enabled
    if !enabled {
      recentFrequencyCaptureTask?.cancel()
      recentFrequencyCaptureTask = nil
    }
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setIncludeRecentFrequenciesFromOtherReceivers(_ enabled: Bool) {
    guard settings.includeRecentFrequenciesFromOtherReceivers != enabled else { return }
    settings.includeRecentFrequenciesFromOtherReceivers = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setAutoConnectSelectedProfileOnLaunch(_ enabled: Bool) {
    guard settings.autoConnectSelectedProfileOnLaunch != enabled else { return }
    settings.autoConnectSelectedProfileOnLaunch = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setAutoConnectSelectedProfileAfterSelection(_ enabled: Bool) {
    guard settings.autoConnectSelectedProfileAfterSelection != enabled else { return }
    settings.autoConnectSelectedProfileAfterSelection = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setConnectionNetworkPolicy(_ policy: ConnectionNetworkPolicy) {
    guard settings.connectionNetworkPolicy != policy else { return }
    settings.connectionNetworkPolicy = policy
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: true)
    if policy == .wifiOnly {
      _ = enforceConnectionNetworkPolicyIfNeeded(reason: "settings_changed", profile: currentConnectedProfile)
    }
  }

  func restoreCurrentSession(
    frequencyHz: Int?,
    mode: DemodulationMode?
  ) {
    guard state == .connected, let profileID = connectedProfileID else { return }
    performConnectedSessionRestore(
      profileID: profileID,
      frequencyHz: frequencyHz,
      mode: mode
    )
  }

  func tune(byStepCount stepCount: Int) {
    setFrequencyHz(
      SessionFrequencyCore.tunedFrequencyHz(
        currentFrequencyHz: settings.frequencyHz,
        stepCount: stepCount,
        tuneStepHz: settings.tuneStepHz,
        backend: activeBackend,
        mode: settings.mode
      ),
      source: "stepper"
    )
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
    scheduleWidebandTuneConfirmationIfNeeded()
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
    guard settings.audioMuted != muted else { return }
    settings.audioMuted = muted
    SharedAudioOutput.engine.setMuted(muted)
    FMDXMP3AudioPlayer.shared.setMuted(muted)
    NowPlayingMetadataController.shared.setMuted(muted)
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: !muted)
  }

  func setMixWithOtherAudioApps(_ enabled: Bool) {
    guard settings.mixWithOtherAudioApps != enabled else { return }
    settings.mixWithOtherAudioApps = enabled
    SharedAudioOutput.engine.setMixWithOtherAudioApps(enabled)
    FMDXMP3AudioPlayer.shared.setMixWithOtherAudioApps(enabled)
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func toggleAudioMuted() {
    setAudioMuted(!settings.audioMuted)
  }

  func setAGCEnabled(_ enabled: Bool) {
    guard settings.agcEnabled != enabled else { return }
    settings.agcEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
    if activeBackend == .fmDxWebserver {
      guard fmdxCapabilities.supportsAGCControl else { return }
      sendFMDXControl(.setFMDXAGC(enabled))
    } else {
      applyIfConnected()
    }
  }

  func setNoiseReductionEnabled(_ enabled: Bool) {
    guard settings.noiseReductionEnabled != enabled else { return }
    settings.noiseReductionEnabled = enabled
    markAutoFilterManuallyOverridden()
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
    if activeBackend == .fmDxWebserver {
      guard fmdxCapabilities.supportsFilterControls else { return }
      sendFMDXControl(.setFMDXFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled))
    } else {
      applyIfConnected()
    }
  }

  func setIMSEnabled(_ enabled: Bool) {
    guard settings.imsEnabled != enabled else { return }
    settings.imsEnabled = enabled
    markAutoFilterManuallyOverridden()
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
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
    playInteractionFeedbackIfEnabled(isOn: mode.isStereo)
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
    guard settings.squelchEnabled != enabled else { return }
    settings.squelchEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
    if activeBackend == .fmDxWebserver {
      return
    }
    if activeBackend == .openWebRX {
      sendOpenWebRXSquelchControl()
      return
    }
    if activeBackend == .kiwiSDR {
      sendKiwiSquelchControl()
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
    sendKiwiSquelchControl()
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
    let resolvedEnabled = settings.kiwiNoiseFilterAlgorithm == .spectral ? true : enabled
    guard settings.kiwiDenoiseEnabled != resolvedEnabled else { return }
    settings.kiwiDenoiseEnabled = resolvedEnabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: settings.kiwiDenoiseEnabled)
    sendKiwiNoiseControl()
  }

  func setKiwiAutonotchEnabled(_ enabled: Bool) {
    let resolvedEnabled = settings.kiwiNoiseFilterAlgorithm == .spectral ? false : enabled
    guard settings.kiwiAutonotchEnabled != resolvedEnabled else { return }
    settings.kiwiAutonotchEnabled = resolvedEnabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: settings.kiwiAutonotchEnabled)
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
    guard settings.kiwiWaterfallCICCompensation != enabled else { return }
    settings.kiwiWaterfallCICCompensation = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
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
    guard settings.showRdsErrorCounters != enabled else { return }
    settings.showRdsErrorCounters = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setVoiceOverRDSAnnouncementMode(_ mode: VoiceOverRDSAnnouncementMode) {
    settings.voiceOverRDSAnnouncementMode = mode
    rdsAnnouncementGate.reset()
    clearPendingRDSAnnouncement()
    lastPostedRDSAnnouncementText = nil
    lastPostedRDSAnnouncementAt = .distantPast
    persistSettings()
  }

  func currentRDSRotorItems() -> [String] {
    guard activeBackend == .fmDxWebserver else { return [] }
    guard let telemetry = fmdxTelemetry else { return [] }
    return currentRDSAnnouncementCandidates(telemetry).map(\.text)
  }

  func setKeepStationPresetsExpanded(_ enabled: Bool) {
    guard settings.keepStationPresetsExpanded != enabled else { return }
    settings.keepStationPresetsExpanded = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setMagicTapAction(_ action: MagicTapAction) {
    guard settings.magicTapAction != action else { return }
    settings.magicTapAction = action
    persistSettings()
  }

  @discardableResult
  func performMagicTapAction(recordingStore: RecordingStore?) -> Bool {
    switch settings.magicTapAction {
    case .toggleMute:
      guard state == .connected else { return false }
      toggleAudioMuted()
      AppAccessibilityAnnouncementCenter.post(
        L10n.text(
          settings.audioMuted
            ? "accessibility.magic_tap.muted"
            : "accessibility.magic_tap.unmuted"
        )
      )
      return true
    case .disconnect:
      guard state == .connected else { return false }
      disconnect()
      return true
    case .toggleRecording:
      if let recordingStore, recordingStore.isRecording {
        recordingStore.stopRecording()
        return true
      }
      guard let recordingStore, let context = currentRecordingContext else { return false }
      recordingStore.startRecording(
        receiverName: context.receiverName,
        backend: context.backend,
        frequencyHz: context.frequencyHz,
        mode: context.mode
      )
      return true
    }
  }

  func setAccessibilityInteractionSoundsEnabled(_ enabled: Bool) {
    guard settings.accessibilityInteractionSoundsEnabled != enabled else { return }
    AppInteractionFeedbackCenter.playInteractionSoundsToggleTransition(to: enabled)
    settings.accessibilityInteractionSoundsEnabled = enabled
    persistSettings()
  }

  func setAccessibilityInteractionSoundsVolume(_ value: Double) {
    let clampedValue = RadioSessionSettings.clampedAccessibilityInteractionSoundsVolume(value)
    guard settings.accessibilityInteractionSoundsVolume != clampedValue else { return }
    settings.accessibilityInteractionSoundsVolume = clampedValue
    persistSettings()
  }

  func setAccessibilityInteractionSoundsMutedDuringRecording(_ enabled: Bool) {
    guard settings.accessibilityInteractionSoundsMutedDuringRecording != enabled else { return }
    settings.accessibilityInteractionSoundsMutedDuringRecording = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setAccessibilitySelectionAnnouncementsEnabled(_ enabled: Bool) {
    guard settings.accessibilitySelectionAnnouncementsEnabled != enabled else { return }
    settings.accessibilitySelectionAnnouncementMode = enabled ? .channel : .off
    settings.accessibilitySelectionAnnouncementsEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setAccessibilitySelectionAnnouncementMode(_ mode: ScreenReaderSelectionAnnouncementMode) {
    guard settings.accessibilitySelectionAnnouncementMode != mode else { return }
    settings.accessibilitySelectionAnnouncementMode = mode
    settings.accessibilitySelectionAnnouncementsEnabled = mode != .off
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: mode != .off)
  }

  func setAccessibilityConnectionSoundsEnabled(_ enabled: Bool) {
    guard settings.accessibilityConnectionSoundsEnabled != enabled else { return }
    settings.accessibilityConnectionSoundsEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setAccessibilityRecordingSoundsEnabled(_ enabled: Bool) {
    guard settings.accessibilityRecordingSoundsEnabled != enabled else { return }
    settings.accessibilityRecordingSoundsEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setSpeechLoudnessLevelingMode(_ mode: SpeechLoudnessLevelingMode) {
    guard settings.accessibilitySpeechLoudnessLevelingMode != mode else { return }
    settings.accessibilitySpeechLoudnessLevelingMode = mode
    applySpeechLoudnessLevelingSettings()
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: mode != .off)
  }

  func setSpeechLoudnessCustomTargetRMS(_ value: Double) {
    let clamped = RadioSessionSettings.clampedSpeechLoudnessTargetRMS(value)
    guard settings.accessibilitySpeechLoudnessCustomTargetRMS != clamped else { return }
    settings.accessibilitySpeechLoudnessCustomTargetRMS = clamped
    applySpeechLoudnessLevelingSettings()
    persistSettings()
  }

  func setSpeechLoudnessCustomMaximumGain(_ value: Double) {
    let clamped = RadioSessionSettings.clampedSpeechLoudnessMaximumGain(value)
    guard settings.accessibilitySpeechLoudnessCustomMaximumGain != clamped else { return }
    settings.accessibilitySpeechLoudnessCustomMaximumGain = clamped
    applySpeechLoudnessLevelingSettings()
    persistSettings()
  }

  func setSpeechLoudnessCustomPeakLimit(_ value: Double) {
    let clamped = RadioSessionSettings.clampedSpeechLoudnessPeakLimit(value)
    guard settings.accessibilitySpeechLoudnessCustomPeakLimit != clamped else { return }
    settings.accessibilitySpeechLoudnessCustomPeakLimit = clamped
    applySpeechLoudnessLevelingSettings()
    persistSettings()
  }

  func setAccessibilitySpeechLoudnessLevelingEnabled(_ enabled: Bool) {
    let mode: SpeechLoudnessLevelingMode = enabled ? .gentle : .off
    guard settings.accessibilitySpeechLoudnessLevelingMode != mode else { return }
    settings.accessibilitySpeechLoudnessLevelingMode = mode
    applySpeechLoudnessLevelingSettings()
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setShowTutorialOnLaunchEnabled(_ enabled: Bool) {
    guard settings.showTutorialOnLaunchEnabled != enabled else { return }
    settings.showTutorialOnLaunchEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setRememberSquelchOnConnectEnabled(_ enabled: Bool) {
    guard settings.rememberSquelchOnConnectEnabled != enabled else { return }
    settings.rememberSquelchOnConnectEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setRadiosSearchFiltersVisibility(_ visibility: RadiosSearchFiltersVisibility) {
    guard settings.radiosSearchFiltersVisibility != visibility else { return }
    settings.radiosSearchFiltersVisibility = visibility
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
    guard settings.adaptiveScannerEnabled != enabled else { return }
    settings.adaptiveScannerEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setSaveChannelScannerResultsEnabled(_ enabled: Bool) {
    guard settings.saveChannelScannerResultsEnabled != enabled else { return }
    settings.saveChannelScannerResultsEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setPlayDetectedChannelScannerSignalsEnabled(_ enabled: Bool) {
    guard settings.playDetectedChannelScannerSignalsEnabled != enabled else { return }
    settings.playDetectedChannelScannerSignalsEnabled = enabled
    applyChannelScannerPlaybackMute()
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setStopChannelScannerOnSignal(_ enabled: Bool) {
    guard settings.stopChannelScannerOnSignal != enabled else { return }
    settings.stopChannelScannerOnSignal = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setFilterChannelScannerInterferenceEnabled(_ enabled: Bool) {
    guard settings.filterChannelScannerInterferenceEnabled != enabled else { return }
    settings.filterChannelScannerInterferenceEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
  }

  func setChannelScannerInterferenceFilterProfile(
    _ profile: ChannelScannerInterferenceFilterProfile
  ) {
    settings.channelScannerInterferenceFilterProfile = profile
    persistSettings()
  }

  func setSaveFMDXScannerResultsEnabled(_ enabled: Bool) {
    guard settings.saveFMDXScannerResultsEnabled != enabled else { return }
    settings.saveFMDXScannerResultsEnabled = enabled
    persistSettings()
    playInteractionFeedbackIfEnabled(isOn: enabled)
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

  func consumeStartupTutorialAutoPresentationIfNeeded() -> Bool {
    guard settings.showTutorialOnLaunchEnabled else { return false }
    guard settings.tutorialAutoShowRemainingCount > 0 else { return false }
    settings.tutorialAutoShowRemainingCount -= 1
    persistSettings()
    return true
  }

  func saveCurrentSettingsSnapshot() {
    var snapshot = settings
    let snapshotState = SavedSettingsSnapshotCore.createdSnapshot(
      from: .init(
        frequencyHz: settings.frequencyHz,
        dxNightModeEnabled: settings.dxNightModeEnabled,
        autoFilterProfileEnabled: settings.autoFilterProfileEnabled
      )
    )
    snapshot.dxNightModeEnabled = snapshotState.dxNightModeEnabled
    snapshot.autoFilterProfileEnabled = snapshotState.autoFilterProfileEnabled
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

  func importSettingsBackup(_ imported: RadioSessionSettings) {
    settings = imported
    if let backend = activeBackend {
      normalizeSettingsForBackendBeforeConnect(backend)
    } else {
      persistSettings()
    }
    applyCurrentSettingsToConnectedBackend()
    Diagnostics.log(category: "Session", message: "Imported settings backup")
  }

  func setDXNightModeEnabled(_ enabled: Bool) {
    if enabled {
      guard settings.dxNightModeEnabled == false else { return }
      var snapshot = settings
      let snapshotState = SavedSettingsSnapshotCore.createdSnapshot(
        from: .init(
          frequencyHz: settings.frequencyHz,
          dxNightModeEnabled: settings.dxNightModeEnabled,
          autoFilterProfileEnabled: settings.autoFilterProfileEnabled
        )
      )
      snapshot.dxNightModeEnabled = snapshotState.dxNightModeEnabled
      snapshot.autoFilterProfileEnabled = snapshotState.autoFilterProfileEnabled
      nightModeSnapshot = snapshot
      persistSnapshot(snapshot, forKey: nightModeSnapshotKey)
      applyNightDXProfile()
      settings.dxNightModeEnabled = true
      persistSettings()
      playInteractionFeedbackIfEnabled(isOn: true)
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
    playInteractionFeedbackIfEnabled(isOn: false)
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
    let action = ConnectedSettingsApplyCore.action(
      for: .init(
        isConnected: state == .connected,
        hasConnectedClient: client != nil,
        isWaitingForInitialServerTuningSync: isWaitingForInitialServerTuningSync()
      )
    )

    switch action {
    case .skip:
      return
    case .deferUntilInitialServerTuningSyncCompletes:
      updateBackendStatusText(L10n.text("session.status.sync_tuning"))
      return
    case .applyNow:
      break
    }

    guard let client else { return }
    var effectiveSnapshot = settings
    if let backend = activeBackend {
      let isSquelchLockedByScanner =
        (backend == .openWebRX && isOpenWebRXSquelchLockedByScanner) ||
        (backend == .kiwiSDR && isKiwiSquelchLockedByScanner)
      let adjustedState = RuntimeAdjustedSettingsCore.adjustedState(
        backend: backend,
        mode: settings.mode,
        squelchEnabled: settings.squelchEnabled,
        isSquelchLockedByScanner: isSquelchLockedByScanner
      )
      effectiveSnapshot.mode = adjustedState.mode
      effectiveSnapshot.squelchEnabled = adjustedState.squelchEnabled
    }

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

  private func playInteractionFeedbackIfEnabled(isOn: Bool) {
    AppInteractionFeedbackCenter.playIfEnabled(isOn ? .enabled : .disabled)
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
    let enabled = effectiveOpenWebRXSquelchEnabled

    Task {
      do {
        try await client.sendControl(.setOpenWebRXSquelchLevel(level: level, enabled: enabled))
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

  private func sendKiwiSquelchControl() {
    guard state == .connected, activeBackend == .kiwiSDR, let client else { return }
    let threshold = settings.kiwiSquelchThreshold
    let enabled = effectiveKiwiSquelchEnabled

    Task {
      do {
        try await client.sendControl(.setKiwiSquelch(enabled: enabled, threshold: threshold))
      } catch {
        await MainActor.run {
          self.lastError = error.localizedDescription
          self.statusText = L10n.text("session.status.connected_with_setting_error")
        }
        Diagnostics.log(
          severity: .warning,
          category: "Session",
          message: "Kiwi squelch control failed: \(error.localizedDescription)"
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
    Diagnostics.log(
      severity: .info,
      category: "FMDX",
      message: "Waiting for FM-DX tune confirmation: expected_frequency=\(frequencyHz) expected_mode=\(settings.mode.rawValue) timeout_ms=1700"
    )
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
          } else {
            Diagnostics.log(
              severity: .info,
              category: "FMDX",
              message: "FM-DX tune confirmed: expected_frequency=\(frequencyHz) reported_frequency=\(actualHz) mode=\(self.settings.mode.rawValue)"
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
    guard settings.tuneConfirmationWarningsEnabled else {
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

  private func applySpeechLoudnessLevelingSettings() {
    SharedAudioOutput.engine.setSpeechLoudnessLeveling(
      mode: settings.accessibilitySpeechLoudnessLevelingMode,
      customProfile: speechLoudnessCustomProfile(from: settings)
    )
  }

  private func speechLoudnessCustomProfile(from settings: RadioSessionSettings) -> SpeechLoudnessLevelingProfile {
    SpeechLoudnessLevelingProfile(
      targetRMS: Float(settings.accessibilitySpeechLoudnessCustomTargetRMS),
      peakLimit: Float(settings.accessibilitySpeechLoudnessCustomPeakLimit),
      minimumGain: 0.20,
      maximumGain: Float(settings.accessibilitySpeechLoudnessCustomMaximumGain),
      gainIncreaseStep: 0.15,
      gainDecreaseStep: 0.28
    )
  }

  private func scheduleWidebandTuneConfirmationIfNeeded() {
    guard settings.tuneConfirmationWarningsEnabled else {
      clearPendingWidebandTuneConfirmation()
      clearActiveFMDXTuneConfirmationWarning()
      return
    }
    guard state == .connected else { return }
    guard let backend = activeBackend, backend == .openWebRX || backend == .kiwiSDR else { return }

    let pending = PendingWidebandTuneConfirmation(
      backend: backend,
      frequencyHz: settings.frequencyHz,
      mode: settings.mode
    )
    pendingWidebandTuneConfirmation = pending
    Diagnostics.log(
      severity: .info,
      category: "Tuning",
      message: "Waiting for tune confirmation: backend=\(backend.rawValue) expected_frequency=\(pending.frequencyHz) expected_mode=\(pending.mode.rawValue) timeout_ms=1350"
    )
    widebandTuneConfirmationTask?.cancel()
    widebandTuneConfirmationTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_350_000_000)
      await MainActor.run {
        guard let self else { return }
        guard self.pendingWidebandTuneConfirmation == pending else { return }
        self.pendingWidebandTuneConfirmation = nil
        Diagnostics.log(
          severity: .warning,
          category: "Tuning",
          message: "Tune confirmation timed out: backend=\(pending.backend.rawValue) expected_frequency=\(pending.frequencyHz) expected_mode=\(pending.mode.rawValue) timeout_ms=1350"
        )
        let requestedText = self.tuneConfirmationSummary(
          frequencyHz: pending.frequencyHz,
          mode: pending.mode,
          backend: pending.backend
        )
        self.showFMDXTuneConfirmationWarning(
          L10n.text("settings.tuning.tune_confirmation_warning_timeout", requestedText)
        )
      }
    }
  }

  private func confirmWidebandTuneIfNeeded(
    backend: SDRBackend,
    reportedFrequencyHz: Int,
    reportedMode: DemodulationMode
  ) {
    guard let pending = pendingWidebandTuneConfirmation, pending.backend == backend else { return }
    let modeMatches = pending.mode == reportedMode
    let toleranceHz = max(50, min(settings.tuneStepHz / 2, 5_000))
    let frequencyMatches = abs(pending.frequencyHz - reportedFrequencyHz) <= toleranceHz
    if modeMatches && frequencyMatches {
      pendingWidebandTuneConfirmation = nil
      widebandTuneConfirmationTask?.cancel()
      clearActiveFMDXTuneConfirmationWarning()
      Diagnostics.log(
        severity: .info,
        category: "Tuning",
        message: "Tune confirmed: backend=\(backend.rawValue) expected_frequency=\(pending.frequencyHz) expected_mode=\(pending.mode.rawValue) reported_frequency=\(reportedFrequencyHz) reported_mode=\(reportedMode.rawValue) tolerance_hz=\(toleranceHz)"
      )
      return
    }

    pendingWidebandTuneConfirmation = nil
    widebandTuneConfirmationTask?.cancel()
    Diagnostics.log(
      severity: .warning,
      category: "Tuning",
      message: "Tune mismatch: backend=\(backend.rawValue) expected_frequency=\(pending.frequencyHz) expected_mode=\(pending.mode.rawValue) reported_frequency=\(reportedFrequencyHz) reported_mode=\(reportedMode.rawValue) tolerance_hz=\(toleranceHz)"
    )
    let requestedText = tuneConfirmationSummary(
      frequencyHz: pending.frequencyHz,
      mode: pending.mode,
      backend: backend
    )
    let actualText = tuneConfirmationSummary(
      frequencyHz: reportedFrequencyHz,
      mode: reportedMode,
      backend: backend
    )
    showFMDXTuneConfirmationWarning(
      L10n.text("settings.tuning.tune_confirmation_warning_mismatch", actualText, requestedText)
    )
  }

  private func clearPendingWidebandTuneConfirmation() {
    pendingWidebandTuneConfirmation = nil
    widebandTuneConfirmationTask?.cancel()
    widebandTuneConfirmationTask = nil
  }

  private func tuneConfirmationSummary(
    frequencyHz: Int,
    mode: DemodulationMode,
    backend: SDRBackend
  ) -> String {
    let frequencyText = backend == .fmDxWebserver
      ? FrequencyFormatter.fmDxMHzText(fromHz: frequencyHz)
      : FrequencyFormatter.mhzText(fromHz: frequencyHz)
    return "\(frequencyText) \(mode.rawValue.uppercased())"
  }

  private func makeClient(for profile: SDRConnectionProfile) -> any SDRBackendClient {
    switch profile.backend {
    case .kiwiSDR:
      return KiwiSDRClient()
    case .openWebRX:
      return OpenWebRXClient()
    case .fmDxWebserver:
      let cachedCapabilities = receiverDataCache.cachedData(for: ReceiverIdentity.key(for: profile))?.fmdxCapabilities
      return FMDXWebserverClient(cachedCapabilities: cachedCapabilities)
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
    var merged = snapshot
    let restoredState = SavedSettingsSnapshotCore.restoredState(
      current: .init(
        frequencyHz: settings.frequencyHz,
        dxNightModeEnabled: settings.dxNightModeEnabled,
        autoFilterProfileEnabled: settings.autoFilterProfileEnabled
      ),
      snapshot: .init(
        frequencyHz: snapshot.frequencyHz,
        dxNightModeEnabled: snapshot.dxNightModeEnabled,
        autoFilterProfileEnabled: snapshot.autoFilterProfileEnabled
      ),
      includeFrequency: includeFrequency
    )
    merged.frequencyHz = restoredState.frequencyHz
    merged.dxNightModeEnabled = restoredState.dxNightModeEnabled
    merged.autoFilterProfileEnabled = restoredState.autoFilterProfileEnabled
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
    SharedAudioOutput.engine.setSpeechLoudnessLeveling(
      mode: settings.accessibilitySpeechLoudnessLevelingMode,
      customProfile: speechLoudnessCustomProfile(from: settings)
    )
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

    if backend != .fmDxWebserver,
      settings.rememberSquelchOnConnectEnabled == false,
      settings.squelchEnabled {
      settings.squelchEnabled = false
      changed = true
    }

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

      let normalizedFrequencyHz = FMDXSessionCore.normalizedSessionFrequencyHz(
        settings.frequencyHz,
        mode: settings.mode,
        memory: fmdxBandMemory
      )
      if settings.frequencyHz != normalizedFrequencyHz {
        settings.frequencyHz = normalizedFrequencyHz
        changed = true
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
    SessionTuningCore.tuneStepState(
      preferredStepHz: value,
      preferenceMode: settings.tuneStepPreferenceMode,
      context: BandTuningContext(
        backend: .fmDxWebserver,
        frequencyHz: settings.frequencyHz,
        mode: mode,
        bandName: nil,
        bandTags: []
      )
    ).tuneStepHz
  }

  private func normalizeMode(_ mode: DemodulationMode, for backend: SDRBackend) -> DemodulationMode {
    mode.normalized(for: backend)
  }

  func normalizeFMDXReportedFrequencyHz(fromMHz value: Double) -> Int {
    FMDXSessionCore.normalizedReportedFrequencyHz(fromMHz: value)
  }

  func inferredFMDXMode(for frequencyHz: Int) -> DemodulationMode {
    FMDXSessionCore.inferredMode(for: frequencyHz)
  }

  func fmdxQuickBand(for frequencyHz: Int, mode: DemodulationMode) -> FMDXQuickBand {
    FMDXSessionCore.quickBand(for: frequencyHz, mode: mode)
  }

  func fmdxFrequencyRange(for mode: DemodulationMode) -> ClosedRange<Int> {
    SessionFrequencyCore.fmdxFrequencyRange(for: mode)
  }

  func normalizedFMDXFrequencyHz(_ value: Int, mode: DemodulationMode) -> Int {
    SessionFrequencyCore.normalizedFrequencyHz(
      value,
      backend: .fmDxWebserver,
      mode: mode
    )
  }

  private func frequencyRange(for backend: SDRBackend?) -> ClosedRange<Int> {
    SessionFrequencyCore.frequencyRange(for: backend, mode: settings.mode)
  }

  private func resolveFMDXBandwidthSelectionID(from rawValue: String) -> String {
    FMDXTelemetrySyncCore.resolveBandwidthSelectionID(
      from: rawValue,
      capabilities: .init(fmdxCapabilities)
    )
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
    FMDXTelemetrySyncCore.parseToggleState(raw)
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
    let restoringFrequencyHz = settings.frequencyHz
    let restoringMode = settings.mode

    cancelSessionTransientTasks(resetScannerState: true)
    self.client = nil
    activeBackend = profile.backend
    activeProfileCacheKey = ReceiverIdentity.key(for: profile)
    currentConnectedProfile = nil
    applySessionLifecyclePresentation(
      SessionLifecyclePresentationCore.presentation(for: .reconnectingRequested),
      profileName: profile.name
    )

    sessionRecoveryTask = Task {
      defer { self.sessionRecoveryTask = nil }

      await client.disconnect()

      let startedAt = Date()
      var attempt = 0

      while !Task.isCancelled {
        attempt += 1
        let delaySeconds = AutomaticReconnectCore.delaySeconds(forAttemptNumber: attempt)
        await MainActor.run {
          self.automaticReconnectAttempts += 1
        }

        if delaySeconds > 0 {
          try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        if Task.isCancelled { return }
        let wasBlockedByPolicy = await MainActor.run {
          self.enforceConnectionNetworkPolicyIfNeeded(
            reason: "automatic_reconnect",
            profile: profile
          )
        }
        if wasBlockedByPolicy {
          return
        }

        do {
          let newClient = makeClient(for: profile)
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
            self.hasInitialServerTuningSync = !InitialServerTuningSyncCore.requiresInitialServerTuningSync(for: profile.backend)
            self.initialServerTuningSyncDeadline = InitialServerTuningSyncCore.initialSyncDeadlineSeconds(for: profile.backend)
              .map { Date().addingTimeInterval($0) } ?? .distantPast
            if self.connectedSince == .distantPast {
              self.connectedSince = Date()
            }
            self.applySessionLifecyclePresentation(
              SessionLifecyclePresentationCore.presentation(
                for: .connected,
                backend: profile.backend
              ),
              profileName: profile.name
            )
            self.startStatusMonitor(profile: profile, client: newClient)
            self.scheduleInitialTuningFallbackAfterConnection(profileID: profile.id)
            self.scheduleListeningHistoryCapture()
            self.performConnectedSessionRestore(
              profileID: profile.id,
              frequencyHz: restoringFrequencyHz,
              mode: restoringMode
            )
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

          if !AutomaticReconnectCore.shouldContinueRetrying(
            elapsedSeconds: Date().timeIntervalSince(startedAt)
          ) {
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
        self.applySessionLifecyclePresentation(
          SessionLifecyclePresentationCore.presentation(
            for: .connectionLostAfterReconnectExhausted
          )
        )
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

  @discardableResult
  private func enforceConnectionNetworkPolicyIfNeeded(
    reason: String,
    profile: SDRConnectionProfile?
  ) -> Bool {
    guard
      let message = ConnectionNetworkPolicyMonitor.shared.blockedMessage(
        for: settings.connectionNetworkPolicy
      )
    else {
      return false
    }

    Diagnostics.log(
      severity: .warning,
      category: "Session",
      message: "Connection blocked by network policy (\(reason))"
    )
    cancelAutomaticRecovery()
    connectTask?.cancel()
    connectTask = nil
    cancelSessionTransientTasks(resetScannerState: true)
    if let client {
      Task { await client.disconnect() }
    }
    client = nil
    connectedProfileID = nil
    activeBackend = nil
    activeProfileCacheKey = nil
    currentConnectedProfile = nil
    isScannerRunning = false
    scannerStatusText = nil
    resetRuntimeState(for: nil)
    applySessionLifecyclePresentation(
      SessionLifecyclePresentationCore.presentation(for: .connectionFailed),
      profileName: profile?.name,
      errorMessage: message
    )
    return true
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
    clearPendingWidebandTuneConfirmation()
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

  private func applySessionLifecyclePresentation(
    _ presentation: SessionLifecyclePresentation,
    profileName: String? = nil,
    errorMessage: String? = nil
  ) {
    let previousState = state
    state = connectionState(for: presentation.phase)
    statusText = localizedSessionStatusText(
      for: presentation.statusKind,
      profileName: profileName
    )
    updateBackendStatusText(
      localizedBackendStatusText(for: presentation.backendStatusKind)
    )
    lastError = localizedSessionErrorText(
      for: presentation.errorKind,
      errorMessage: errorMessage
    )
    if presentation.phase == .connected, previousState != .connected {
      AppInteractionFeedbackCenter.playConnectionTransitionIfEnabled(succeeded: true)
    } else if presentation.phase == .failed, previousState != .failed {
      AppInteractionFeedbackCenter.playConnectionTransitionIfEnabled(succeeded: false)
    }
  }

  private func connectionState(
    for phase: SessionLifecyclePhase
  ) -> ConnectionState {
    switch phase {
    case .disconnected:
      return .disconnected
    case .connecting:
      return .connecting
    case .connected:
      return .connected
    case .failed:
      return .failed
    }
  }

  private func localizedSessionStatusText(
    for kind: SessionLifecycleStatusKind,
    profileName: String?
  ) -> String {
    switch kind {
    case .disconnected:
      return L10n.text("session.status.disconnected")
    case .connectingTo:
      return L10n.text("session.status.connecting_to", profileName ?? "")
    case .reconnectingTo:
      return L10n.text("session.status.reconnecting_to", profileName ?? "")
    case .connectedTo:
      return L10n.text("session.status.connected_to", profileName ?? "")
    case .connectionFailed:
      return L10n.text("session.status.connection_failed")
    case .connectionLost:
      return L10n.text("session.status.connection_lost")
    }
  }

  private func localizedBackendStatusText(
    for kind: SessionLifecycleBackendStatusKind
  ) -> String? {
    switch kind {
    case .none:
      return nil
    case .reconnectingWait:
      return L10n.text("session.status.reconnecting_wait")
    case .syncingTuning:
      return L10n.text("session.status.sync_tuning")
    }
  }

  private func localizedSessionErrorText(
    for kind: SessionLifecycleErrorKind,
    errorMessage: String?
  ) -> String? {
    switch kind {
    case .none:
      return nil
    case .providedMessage:
      return errorMessage
    case .reconnectExhausted:
      return L10n.text("session.status.reconnect_exhausted")
    }
  }

  private func statusMonitorIntervalNanoseconds() -> UInt64 {
    UInt64(ConnectionMonitorCore.pollIntervalSeconds(for: runtimePolicy.corePolicy) * 1_000_000_000)
  }

  private func shouldRefreshLiveAudioAnalysis() -> Bool {
    let now = Date()
    let shouldRefresh = LiveAudioAnalysisRefreshCore.shouldRefresh(
      policy: runtimePolicy.corePolicy,
      elapsedSecondsSinceLastReducedActivityRefresh: now.timeIntervalSince(lastReducedActivityAudioAnalysisAt)
    )
    guard shouldRefresh else { return false }

    if runtimePolicy != .interactive {
      lastReducedActivityAudioAnalysisAt = now
    }
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
      let completedInitialServerTuningSync = hasInitialServerTuningSync == false
      hasInitialServerTuningSync = true
      NowPlayingMetadataController.shared.setTitle(nil)
      let normalizedFrequencyHz = SessionFrequencyCore.normalizedFrequencyHz(
        frequencyHz,
        backend: .openWebRX,
        mode: mode ?? settings.mode
      )
      let bandEntry = openWebRXBandEntry(for: normalizedFrequencyHz)
      let result = WidebandRemoteTuningCore.synchronizeOpenWebRX(
        state: currentWidebandRemoteTuningState(),
        reportedFrequencyHz: frequencyHz,
        reportedMode: mode,
        bandName: bandEntry?.name,
        bandTags: bandEntry?.tags ?? []
      )
      let changed = applyWidebandRemoteTuningState(result.state)
      if changed {
        persistSettings()
      }
      updateBackendStatusText(result.statusSummary)
      if completedInitialServerTuningSync {
        applyRememberedSquelchAfterInitialTuningSyncIfNeeded(for: .openWebRX)
      }
      confirmWidebandTuneIfNeeded(
        backend: .openWebRX,
        reportedFrequencyHz: normalizedFrequencyHz,
        reportedMode: result.state.mode
      )
      scheduleListeningHistoryCapture()

    case .kiwiTuning(let frequencyHz, let mode, let bandName, let passband):
      initialTuningFallbackTask?.cancel()
      initialTuningFallbackTask = nil
      let completedInitialServerTuningSync = hasInitialServerTuningSync == false
      hasInitialServerTuningSync = true
      NowPlayingMetadataController.shared.setTitle(nil)
      let activeMode = mode ?? settings.mode
      let result = WidebandRemoteTuningCore.synchronizeKiwi(
        state: currentWidebandRemoteTuningState(),
        reportedFrequencyHz: frequencyHz,
        reportedMode: mode,
        reportedBandName: bandName,
        currentPassband: settings.kiwiPassband(for: activeMode, sampleRateHz: kiwiTelemetry?.sampleRateHz),
        reportedPassband: passband,
        sampleRateHz: kiwiTelemetry?.sampleRateHz
      )
      var changed = applyWidebandRemoteTuningState(result.state)
      if let resolvedPassband = result.resolvedKiwiPassband,
        settings.kiwiPassband(for: result.state.mode, sampleRateHz: kiwiTelemetry?.sampleRateHz) != resolvedPassband {
        settings.setKiwiPassband(
          resolvedPassband,
          for: result.state.mode,
          sampleRateHz: kiwiTelemetry?.sampleRateHz
        )
        changed = true
      }
      currentKiwiBandName = result.normalizedBandName
      if changed {
        persistSettings()
      }
      updateBackendStatusText(result.statusSummary)
      if completedInitialServerTuningSync {
        applyRememberedSquelchAfterInitialTuningSyncIfNeeded(for: .kiwiSDR)
      }
      confirmWidebandTuneIfNeeded(
        backend: .kiwiSDR,
        reportedFrequencyHz: result.state.frequencyHz,
        reportedMode: result.state.mode
      )
      scheduleListeningHistoryCapture()
      if activeBackend == .kiwiSDR, state == .connected {
        sendKiwiWaterfallControl()
      }

    case .fmdxCapabilities(let capabilities, let hasConfirmedSnapshot, _):
      applyFMDXCapabilityState(
        .init(
          capabilities: coreFMDXCapabilities(capabilities),
          hasConfirmedSnapshot: hasConfirmedSnapshot,
          usedCachedCapabilities: false
        )
      )
      if FMDXCapabilitiesPolicyCore.isMeaningful(coreFMDXCapabilities(capabilities)) {
        persistCachedReceiverData { cached in
          cached.fmdxCapabilities = capabilities
        }
      }
      let capabilitySync = FMDXCapabilitiesSyncCore.synchronizedState(
        settings: .init(settings),
        selectedBandwidthID: selectedFMDXBandwidthID,
        capabilities: .init(capabilities)
      )
      if let resolvedBandwidthID = capabilitySync.resolvedBandwidthID {
        selectedFMDXBandwidthID = resolvedBandwidthID
      }
      if capabilitySync.forcedFMBandFallback {
        isShowingFMDXTuneConfirmationWarning = false
        fmdxTuneWarningText = L10n.text("fmdx.band.am_not_supported")
      }
      capabilitySync.settings.apply(to: &settings)
      if capabilitySync.changedSettings {
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
      let telemetrySync = FMDXTelemetrySyncCore.synchronizedState(
        settings: .init(settings),
        telemetry: .init(telemetry),
        capabilities: .init(fmdxCapabilities),
        bandMemory: fmdxBandMemory,
        pendingTuneFrequencyHz: pendingFMDXTuneFrequencyHz
      )
      fmdxBandMemory = telemetrySync.bandMemory
      if let antennaID = telemetrySync.resolvedAntennaID {
        selectedFMDXAntennaID = antennaID
      }
      if let bandwidthID = telemetrySync.resolvedBandwidthID {
        selectedFMDXBandwidthID = bandwidthID
      }
      reconcilePendingFMDXAudioModeState(with: telemetry)
      logFMDXAudioModeChangeIfNeeded(previous: previousTelemetry, current: telemetry)
      if telemetrySync.shouldClearPendingTuneConfirmation {
        clearFMDXTuneConfirmationState()
      }
      if telemetrySync.settings.mode != settings.mode,
        let backendFrequencyHz = telemetrySync.reportedFrequencyHz,
        let backendMode = telemetrySync.reportedMode {
        Diagnostics.log(
          category: "FMDX",
          message: "Band synchronized from telemetry: previous_mode=\(settings.mode.rawValue) resolved_mode=\(backendMode.rawValue) reported_frequency_hz=\(backendFrequencyHz)"
        )
      }
      telemetrySync.settings.apply(to: &settings)
      if telemetrySync.changedSettings {
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
    let snapshot = SharedAudioOutput.engine.runtimeSnapshot()
    return ChannelScannerSignalCore.interferenceFilterState(
      metrics: ChannelScannerInterferenceMetrics(
        sampleAgeSeconds: snapshot.secondsSinceLastLevelSample,
        analysisBufferCount: snapshot.recentAnalysisBufferCount,
        envelopeVariation: snapshot.recentEnvelopeVariation,
        zeroCrossingRate: snapshot.recentZeroCrossingRate,
        spectralActivity: snapshot.recentSpectralActivity,
        levelStdDB: snapshot.recentLevelStdDB
      ),
      profile: filterProfile
    )
  }

  private func channelScannerInterferenceFilterThresholds(
    for profile: ChannelScannerInterferenceFilterProfile
  ) -> ChannelScannerInterferenceFilterThresholds {
    ChannelScannerSignalCore.interferenceFilterThresholds(for: profile)
  }

  private func isFMDXTuned(to frequencyHz: Int) -> Bool {
    guard let frequencyMHz = fmdxTelemetry?.frequencyMHz else { return false }
    let reportedHz = normalizeFMDXReportedFrequencyHz(fromMHz: frequencyMHz)
    return abs(reportedHz - frequencyHz) <= 2_000
  }

  private func defaultScannerThreshold(for backend: SDRBackend) -> Double {
    ChannelScannerSignalCore.defaultThreshold(for: backend)
  }

  private func adaptiveDwellSeconds(
    _ base: Double,
    adaptive: Bool,
    signal: Double?,
    threshold: Double
  ) -> Double {
    ChannelScannerSignalCore.adaptiveDwellSeconds(
      base,
      adaptive: adaptive,
      signal: signal,
      threshold: threshold
    )
  }

  private func adaptiveHoldSeconds(
    _ base: Double,
    adaptive: Bool,
    signal: Double?,
    threshold: Double
  ) -> Double {
    ChannelScannerSignalCore.adaptiveHoldSeconds(
      base,
      adaptive: adaptive,
      signal: signal,
      threshold: threshold
    )
  }

  private func openWebRXStatusSummary(frequencyHz: Int, mode: DemodulationMode?) -> String {
    BackendStatusSummaryCore.openWebRXSummary(
      frequencyHz: frequencyHz,
      mode: mode,
      bandName: openWebRXBandEntry(for: frequencyHz)?.name
    )
  }

  private func kiwiStatusSummary(
    frequencyHz: Int,
    mode: DemodulationMode?,
    reportedBandName: String?
  ) -> String {
    BackendStatusSummaryCore.kiwiSummary(
      frequencyHz: frequencyHz,
      mode: mode,
      reportedBandName: reportedBandName
    )
  }

  private func normalizedBandName(_ name: String?) -> String? {
    BackendStatusSummaryCore.normalizedBandName(name)
  }

  private func currentWidebandRemoteTuningState() -> WidebandRemoteTuningState {
    WidebandRemoteTuningState(
      frequencyHz: settings.frequencyHz,
      mode: settings.mode,
      preferredTuneStepHz: settings.preferredTuneStepHz,
      tuneStepHz: settings.tuneStepHz,
      tuneStepPreferenceMode: settings.tuneStepPreferenceMode
    )
  }

  @discardableResult
  private func applyWidebandRemoteTuningState(_ state: WidebandRemoteTuningState) -> Bool {
    var changed = false
    if settings.frequencyHz != state.frequencyHz {
      settings.frequencyHz = state.frequencyHz
      changed = true
    }
    if settings.mode != state.mode {
      settings.mode = state.mode
      changed = true
    }
    if settings.preferredTuneStepHz != state.preferredTuneStepHz {
      settings.preferredTuneStepHz = state.preferredTuneStepHz
      changed = true
    }
    if settings.tuneStepHz != state.tuneStepHz {
      settings.tuneStepHz = state.tuneStepHz
      changed = true
    }
    return changed
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
      let deadline = Date().addingTimeInterval(DeferredSessionRestoreCore.deadlineSeconds)

      while !Task.isCancelled {
        let status = self.deferredSessionRestoreStatus(profileID: profileID, deadline: deadline)
        if DeferredSessionRestoreCore.shouldApply(status: status) {
          if let mode {
            self.setMode(mode)
          }
          if let frequencyHz {
            self.setFrequencyHz(frequencyHz)
          }
          return
        }
        guard DeferredSessionRestoreCore.shouldContinueWaiting(status: status) else { return }

        try? await Task.sleep(
          nanoseconds: UInt64(DeferredSessionRestoreCore.pollIntervalSeconds * 1_000_000_000)
        )
      }
    }
  }

  private func performConnectedSessionRestore(
    profileID: UUID,
    frequencyHz: Int?,
    mode: DemodulationMode?
  ) {
    let action = ConnectedSessionRestoreCore.action(
      status: .init(
        hasPendingRestore: frequencyHz != nil || mode != nil,
        initialTuningSyncStatus: initialServerTuningSyncStatus()
      )
    )

    switch action {
    case .none:
      return

    case .applyNow:
      if let mode {
        setMode(mode)
      }
      if let frequencyHz {
        setFrequencyHz(frequencyHz)
      }

    case .deferUntilInitialTuningReady:
      scheduleRestoreAfterConnection(
        profileID: profileID,
        frequencyHz: frequencyHz,
        mode: mode
      )
    }
  }

  private func applyRememberedSquelchAfterInitialTuningSyncIfNeeded(for backend: SDRBackend) {
    guard settings.rememberSquelchOnConnectEnabled else { return }
    guard settings.squelchEnabled else { return }
    guard state == .connected else { return }
    guard activeBackend == backend else { return }
    switch backend {
    case .openWebRX:
      sendOpenWebRXSquelchControl()
    case .kiwiSDR:
      sendKiwiSquelchControl()
    case .fmDxWebserver:
      break
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
        try? await Task.sleep(
          nanoseconds: UInt64(DeferredSessionRestoreCore.pollIntervalSeconds * 1_000_000_000)
        )
      }

      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard self.state == .connected else { return }
        guard self.connectedProfileID == profileID else { return }
        guard InitialServerTuningSyncCore.shouldApplyInitialLocalFallback(status: self.initialServerTuningSyncStatus()) else { return }

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
      applyFMDXCapabilityState(
        FMDXCapabilitiesSessionCore.restoredState(
          cached: cached.fmdxCapabilities.map(coreFMDXCapabilities)
        )
      )
      fmdxServerPresets = cached.fmdxServerPresets

    case .kiwiSDR:
      break
    }
  }

  private func persistCachedReceiverData(_ mutate: (inout CachedReceiverData) -> Void) {
    guard let activeProfileCacheKey else { return }
    receiverDataCache.update(receiverID: activeProfileCacheKey, mutate: mutate)
  }

  private func applyFMDXCapabilityState(_ state: FMDXCapabilitiesSessionCore.State) {
    fmdxCapabilities = FMDXCapabilities(
      antennas: state.capabilities.antennas.map { option in
        FMDXControlOption(id: option.id, label: option.label, legacyValue: option.legacyValue)
      },
      bandwidths: state.capabilities.bandwidths.map { option in
        FMDXControlOption(id: option.id, label: option.label, legacyValue: option.legacyValue)
      },
      supportsAM: state.capabilities.supportsAM,
      supportsFilterControls: state.capabilities.supportsFilterControls,
      supportsAGCControl: state.capabilities.supportsAGCControl
    )
    hasFMDXCapabilitySnapshot = state.hasConfirmedSnapshot
  }

  private func coreFMDXCapabilities(_ capabilities: FMDXCapabilities) -> FMDXCapabilitiesPolicyCore.Capabilities {
    FMDXCapabilitiesPolicyCore.Capabilities(
      antennas: capabilities.antennas.map { option in
        FMDXCapabilitiesPolicyCore.ControlOption(
          id: option.id,
          label: option.label,
          legacyValue: option.legacyValue
        )
      },
      bandwidths: capabilities.bandwidths.map { option in
        FMDXCapabilitiesPolicyCore.ControlOption(
          id: option.id,
          label: option.label,
          legacyValue: option.legacyValue
        )
      },
      supportsAM: capabilities.supportsAM,
      supportsFilterControls: capabilities.supportsFilterControls,
      supportsAGCControl: capabilities.supportsAGCControl
    )
  }

  private func rememberOpenWebRXBookmark(_ bookmark: SDRServerBookmark) {
    lastOpenWebRXBookmark = bookmark
    persistCachedReceiverData { cached in
      cached.lastOpenWebRXBookmark = bookmark
    }
  }

  private func inferredKiwiBandName(for frequencyHz: Int) -> String? {
    SessionTuningCore.inferredKiwiBandName(for: frequencyHz)
  }

  private var fmDxOverallFrequencyRangeHz: ClosedRange<Int> {
    fmDxAMMinFrequencyHz...fmDxFMMaxFrequencyHz
  }

  private func preferredFMDXFrequency(for mode: DemodulationMode) -> Int {
    FMDXSessionCore.preferredFrequency(for: mode, memory: fmdxBandMemory)
  }

  private func preferredFMDXFrequency(for band: FMDXQuickBand) -> Int {
    FMDXSessionCore.preferredFrequency(for: band, memory: fmdxBandMemory)
  }

  private func preferredFMDXQuickBand(for mode: DemodulationMode) -> FMDXQuickBand {
    FMDXSessionCore.preferredQuickBand(for: mode, memory: fmdxBandMemory)
  }

  private func noteSelectedFMDXQuickBand(_ band: FMDXQuickBand) {
    fmdxBandMemory = FMDXSessionCore.notedSelectedQuickBand(band, memory: fmdxBandMemory)
  }

  private func rememberFMDXFrequency(_ frequencyHz: Int, mode: DemodulationMode) {
    fmdxBandMemory = FMDXSessionCore.rememberedFrequency(
      frequencyHz,
      mode: mode,
      memory: fmdxBandMemory
    )
  }

  private func seedFMDXBandMemory() {
    fmdxBandMemory = FMDXSessionCore.seededMemory(
      from: settings.frequencyHz,
      memory: fmdxBandMemory
    )
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
    applyFMDXCapabilityState(FMDXCapabilitiesSessionCore.resetState())
    fmdxServerPresets = []
    fmdxPresetSourceDescription = nil
    selectedFMDXAntennaID = nil
    selectedFMDXBandwidthID = nil
    kiwiTelemetry = nil
    fmDxTuneDebounceTask?.cancel()
    fmDxTuneDebounceTask = nil
    clearFMDXTuneConfirmationState()
    clearPendingWidebandTuneConfirmation()
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
    rdsAnnouncementGate.reset()
    clearPendingRDSAnnouncement()
    lastPostedRDSAnnouncementText = nil
    lastPostedRDSAnnouncementAt = .distantPast
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
    let now = Date()
    guard canAnnounceRDSAutomatically() else {
      _ = rdsAnnouncementGate.evaluate(candidate: nil, now: now)
      clearPendingRDSAnnouncement()
      return
    }

    let announcement = rdsAnnouncement(previous: previous, current: current)
    let currentAnnouncement = currentRDSFallbackAnnouncement(current, now: now)
    let effectiveAnnouncement = announcement ?? pendingRDSAnnouncement.flatMap { candidate in
      matchesCurrentRDSAnnouncement(candidate, telemetry: current) ? candidate : nil
    } ?? currentAnnouncement
    if let stableAnnouncement = rdsAnnouncementGate.evaluate(candidate: effectiveAnnouncement, now: now) {
      clearPendingRDSAnnouncement()
      postRDSAnnouncement(stableAnnouncement, now: now)
      return
    }

    guard let effectiveAnnouncement else {
      clearPendingRDSAnnouncement()
      return
    }

    schedulePendingRDSAnnouncement(effectiveAnnouncement)
  }

  private func rdsAnnouncement(
    previous: FMDXTelemetry?,
    current: FMDXTelemetry
  ) -> StableAnnouncementCandidate<RDSAnnouncementKind>? {
    let mode = settings.voiceOverRDSAnnouncementMode
    let previousPS = normalizedRDSValue(previous?.ps)
    let currentPS = normalizedRDSValue(current.ps)
    let previousStation = preferredRDSStationName(from: previous)
    let currentStation = preferredRDSStationName(from: current)

    if currentStation != previousStation, let currentStation {
      return StableAnnouncementCandidate(
        kind: .stationName,
        text: L10n.text("accessibility.rds_announcement.station", currentStation)
      )
    }
    if currentPS != previousPS, let currentPS, mode == .full, currentPS != currentStation {
      return StableAnnouncementCandidate(
        kind: .programService,
        text: L10n.text("accessibility.rds_announcement.ps", currentPS)
      )
    }

    guard mode == .full else { return nil }

    let hadPreviousRDS = previousPS != nil
      || normalizedRDSValue(previous?.rt0) != nil
      || normalizedRDSValue(previous?.rt1) != nil
      || normalizedRDSValue(previous?.pi) != nil

    let previousRT = stableRDSRadioText(from: previous)
    let currentRT = stableRDSRadioText(from: current)
    if hadPreviousRDS, currentRT != previousRT, let currentRT {
      return StableAnnouncementCandidate(
        kind: .radioText,
        text: L10n.text("accessibility.rds_announcement.rt", currentRT)
      )
    }

    let previousPI = normalizedRDSValue(previous?.pi)
    let currentPI = normalizedRDSValue(current.pi)
    if hadPreviousRDS, currentPI != previousPI, let currentPI, currentPS == nil {
      return StableAnnouncementCandidate(
        kind: .pi,
        text: L10n.text("accessibility.rds_announcement.pi", currentPI)
      )
    }

    return nil
  }

  private func currentRDSFallbackAnnouncement(
    _ current: FMDXTelemetry,
    now: Date
  ) -> StableAnnouncementCandidate<RDSAnnouncementKind>? {
    currentRDSAnnouncementCandidates(current).first { candidate in
      shouldScheduleFallbackRDSAnnouncement(candidate, now: now)
    }
  }

  private func currentRDSAnnouncementCandidates(
    _ current: FMDXTelemetry
  ) -> [StableAnnouncementCandidate<RDSAnnouncementKind>] {
    let mode = settings.voiceOverRDSAnnouncementMode
    let currentPS = normalizedRDSValue(current.ps)
    let currentStation = preferredRDSStationName(from: current)
    var candidates: [StableAnnouncementCandidate<RDSAnnouncementKind>] = []

    if mode == .full, let currentRT = stableRDSRadioText(from: current) {
      candidates.append(
        StableAnnouncementCandidate(
          kind: .radioText,
          text: L10n.text("accessibility.rds_announcement.rt", currentRT)
        )
      )
    }

    if let currentStation {
      candidates.append(
        StableAnnouncementCandidate(
          kind: .stationName,
          text: L10n.text("accessibility.rds_announcement.station", currentStation)
        )
      )
    }

    guard mode == .full else { return candidates }

    if let currentPS, currentPS != currentStation {
      candidates.append(
        StableAnnouncementCandidate(
          kind: .programService,
          text: L10n.text("accessibility.rds_announcement.ps", currentPS)
        )
      )
    }

    if let currentPI = normalizedRDSValue(current.pi), currentPS == nil {
      candidates.append(
        StableAnnouncementCandidate(
          kind: .pi,
          text: L10n.text("accessibility.rds_announcement.pi", currentPI)
        )
      )
    }

    return candidates
  }

  private func shouldScheduleFallbackRDSAnnouncement(
    _ candidate: StableAnnouncementCandidate<RDSAnnouncementKind>,
    now: Date
  ) -> Bool {
    guard lastPostedRDSAnnouncementText == candidate.text else { return true }
    return now.timeIntervalSince(lastPostedRDSAnnouncementAt)
      >= duplicateRDSAnnouncementWindow(for: candidate.kind)
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

    guard normalized.count >= 5 else { return nil }
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

  private func canAnnounceRDSAutomatically() -> Bool {
    guard settings.voiceOverRDSAnnouncementMode != .off else { return false }
    guard UIAccessibility.isVoiceOverRunning else { return false }
    guard activeBackend == .fmDxWebserver else { return false }
    guard state == .connected else { return false }
    guard !isScannerRunning else { return false }
    guard accessibilityState?.isReceiverTabActive ?? true else { return false }
    return true
  }

  private func schedulePendingRDSAnnouncement(
    _ candidate: StableAnnouncementCandidate<RDSAnnouncementKind>
  ) {
    if pendingRDSAnnouncement == candidate, pendingRDSAnnouncementTask != nil {
      return
    }

    pendingRDSAnnouncement = candidate
    pendingRDSAnnouncementTask?.cancel()
    pendingRDSAnnouncementTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled, self.pendingRDSAnnouncement == candidate {
        let now = Date()
        guard let nextEvaluationDate = self.rdsAnnouncementGate.nextEvaluationDate(
          candidate: candidate,
          now: now
        ) else {
          break
        }

        let delay = max(0, nextEvaluationDate.timeIntervalSince(now))
        if delay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        guard !Task.isCancelled, self.pendingRDSAnnouncement == candidate else { return }

        let evaluationNow = Date()
        guard self.canAnnounceRDSAutomatically() else {
          _ = self.rdsAnnouncementGate.evaluate(candidate: nil, now: evaluationNow)
          self.clearPendingRDSAnnouncement(cancelTask: false)
          return
        }

        if let stableAnnouncement = self.rdsAnnouncementGate.evaluate(
          candidate: candidate,
          now: evaluationNow
        ) {
          self.clearPendingRDSAnnouncement(cancelTask: false)
          self.postRDSAnnouncement(stableAnnouncement, now: evaluationNow)
          return
        }
      }

      if self.pendingRDSAnnouncement == candidate {
        self.clearPendingRDSAnnouncement(cancelTask: false)
      }
    }
  }

  private func clearPendingRDSAnnouncement(cancelTask: Bool = true) {
    if cancelTask {
      pendingRDSAnnouncementTask?.cancel()
    }
    pendingRDSAnnouncementTask = nil
    pendingRDSAnnouncement = nil
  }

  private func duplicateRDSAnnouncementWindow(for kind: RDSAnnouncementKind) -> TimeInterval {
    switch kind {
    case .stationName:
      return 3.8
    case .programService:
      return 4.2
    case .radioText:
      return 6.0
    case .pi:
      return 4.8
    }
  }

  private func postRDSAnnouncement(
    _ candidate: StableAnnouncementCandidate<RDSAnnouncementKind>,
    now: Date
  ) {
    if lastPostedRDSAnnouncementText == candidate.text,
       now.timeIntervalSince(lastPostedRDSAnnouncementAt) < duplicateRDSAnnouncementWindow(for: candidate.kind) {
      return
    }

    lastPostedRDSAnnouncementText = candidate.text
    lastPostedRDSAnnouncementAt = now
    AppAccessibilityAnnouncementCenter.post(candidate.text)
  }

  private func matchesCurrentRDSAnnouncement(
    _ candidate: StableAnnouncementCandidate<RDSAnnouncementKind>,
    telemetry: FMDXTelemetry
  ) -> Bool {
    candidate.text == currentRDSAnnouncementText(for: candidate.kind, telemetry: telemetry)
  }

  private func currentRDSAnnouncementText(
    for kind: RDSAnnouncementKind,
    telemetry: FMDXTelemetry
  ) -> String? {
    switch kind {
    case .stationName:
      return preferredRDSStationName(from: telemetry).map {
        L10n.text("accessibility.rds_announcement.station", $0)
      }
    case .programService:
      return normalizedRDSValue(telemetry.ps)
        .flatMap { $0 == preferredRDSStationName(from: telemetry) ? nil : $0 }
        .map {
          L10n.text("accessibility.rds_announcement.ps", $0)
        }
    case .radioText:
      return stableRDSRadioText(from: telemetry).map {
        L10n.text("accessibility.rds_announcement.rt", $0)
      }
    case .pi:
      return normalizedRDSValue(telemetry.pi).map {
        L10n.text("accessibility.rds_announcement.pi", $0)
      }
    }
  }

  private func canPushLocalTuningToServerYet() -> Bool {
    InitialServerTuningSyncCore.canApplyLocalTuning(status: initialServerTuningSyncStatus())
  }

  private func isWaitingForInitialServerTuningSync() -> Bool {
    guard state == .connected else { return false }
    return InitialServerTuningSyncCore.isWaitingForInitialServerTuningSync(status: initialServerTuningSyncStatus())
  }

  private func initialServerTuningSyncStatus() -> InitialServerTuningSyncCore.Status {
    .init(
      backend: activeBackend,
      hasInitialServerTuningSync: hasInitialServerTuningSync,
      deadlineReached: Date() >= initialServerTuningSyncDeadline
    )
  }

  private func deferredSessionRestoreStatus(
    profileID: UUID,
    deadline: Date
  ) -> DeferredSessionRestoreCore.Status {
    .init(
      isConnected: state == .connected,
      isTargetProfileConnected: connectedProfileID == profileID,
      canApplyLocalTuning: canPushLocalTuningToServerYet(),
      deadlineReached: Date() >= deadline
    )
  }

  private func tuningBandProfile(for backend: SDRBackend) -> BandTuningProfile {
    BandTuningProfiles.resolve(for: tuningBandContext(for: backend))
  }

  private func resolvedTuneStepHz(
    _ preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    using profile: BandTuningProfile
  ) -> Int {
    SessionTuningCore.resolvedTuneStep(
      preferredStepHz: preferredStepHz,
      preferenceMode: preferenceMode,
      profile: profile
    )
  }

  private func resolvedTuneStepHz(
    forPreferred preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    backend: SDRBackend?
  ) -> Int {
    tuneStepState(
      forPreferred: preferredStepHz,
      preferenceMode: preferenceMode,
      backend: backend
    ).tuneStepHz
  }

  private func tuneStepState(
    forPreferred preferredStepHz: Int,
    preferenceMode: TuneStepPreferenceMode,
    backend: SDRBackend?
  ) -> ListenSDRCore.TuneStepState {
    SessionTuningCore.tuneStepState(
      preferredStepHz: preferredStepHz,
      preferenceMode: preferenceMode,
      context: optionalTuningBandContext(for: backend)
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

  private func optionalTuningBandContext(for backend: SDRBackend?) -> BandTuningContext? {
    guard let backend else { return nil }
    return tuningBandContext(for: backend)
  }

  private func openWebRXBandEntry(for frequencyHz: Int) -> SDRBandPlanEntry? {
    openWebRXBandPlan.first(where: { $0.lowerBoundHz...$0.upperBoundHz ~= frequencyHz })
  }

  private func syncTuneStepToCurrentBandIfNeeded() -> Bool {
    guard let backend = activeBackend else { return false }
    let state = tuneStepState(
      forPreferred: settings.preferredTuneStepHz,
      preferenceMode: settings.tuneStepPreferenceMode,
      backend: backend
    )
    let profile = tuningBandProfile(for: backend)
    guard settings.tuneStepHz != state.tuneStepHz else { return false }
    settings.preferredTuneStepHz = state.preferredTuneStepHz
    settings.tuneStepHz = state.tuneStepHz
    Diagnostics.log(
      category: "Session",
      message: "Tune step adjusted to \(state.tuneStepHz) Hz for band profile \(profile.id) (mode=\(settings.tuneStepPreferenceMode.rawValue))"
    )
    return true
  }
}
