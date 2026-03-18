import Foundation

@MainActor
enum DiagnosticsExportBuilder {
  static func createExportFile(
    profileStore: ProfileStore,
    radioSession: RadioSessionViewModel,
    diagnostics: DiagnosticsStore,
    historyStore: ListeningHistoryStore,
    recordingStore: RecordingStore
  ) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ListenSDR-Diagnostics",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"

    let fileURL = directory.appendingPathComponent(
      "listen-sdr-diagnostics-\(formatter.string(from: Date())).txt"
    )
    try buildText(
      profileStore: profileStore,
      radioSession: radioSession,
      diagnostics: diagnostics,
      historyStore: historyStore,
      recordingStore: recordingStore
    ).write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  static func buildText(
    profileStore: ProfileStore,
    radioSession: RadioSessionViewModel,
    diagnostics: DiagnosticsStore,
    historyStore: ListeningHistoryStore,
    recordingStore: RecordingStore
  ) -> String {
    let bundle = Bundle.main
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    let generatedAt = ISO8601DateFormatter().string(from: Date())

    var lines: [String] = []
    lines.append("Listen SDR diagnostics export")
    lines.append("Generated: \(generatedAt)")
    lines.append("Version: \(version) (\(build))")
    lines.append("")

    lines.append("[Session]")
    lines.append("State: \(connectionStateText(radioSession.state))")
    lines.append("Status: \(radioSession.statusText)")
    if let backendStatus = radioSession.backendStatusText {
      lines.append("Backend status: \(backendStatus)")
    }
    if let error = radioSession.lastError {
      lines.append("Last error: \(error)")
    }
    if let profile = profileStore.selectedProfile {
      lines.append("Selected profile: \(profile.name)")
      lines.append("Selected endpoint: \(profile.endpointDescription)")
      lines.append("Selected backend: \(profile.backend.rawValue)")
    } else {
      lines.append("Selected profile: none")
    }
    if let connectedProfile = radioSession.connectedProfileSnapshot {
      lines.append("Connected profile: \(connectedProfile.name)")
      lines.append("Connected endpoint: \(connectedProfile.endpointDescription)")
      lines.append("Connected backend: \(connectedProfile.backend.rawValue)")
    } else {
      lines.append("Connected profile: none")
    }
    lines.append("Frequency: \(radioSession.settings.frequencyHz) Hz")
    lines.append("Mode: \(radioSession.settings.mode.rawValue)")
    lines.append("Tune step: \(radioSession.settings.tuneStepHz) Hz")
    lines.append("Tune step mode: \(radioSession.settings.tuneStepPreferenceMode.rawValue)")
    lines.append("Muted: \(radioSession.settings.audioMuted)")
    lines.append("Volume: \(String(format: "%.2f", radioSession.settings.audioVolume))")
    lines.append("Scanner running: \(radioSession.isScannerRunning)")
    if let scannerStatus = radioSession.scannerStatusText, !scannerStatus.isEmpty {
      lines.append("Scanner status: \(scannerStatus)")
    }
    lines.append("Scanner threshold: \(String(format: "%.1f", radioSession.scannerThreshold))")
    lines.append("Scanner dwell: \(String(format: "%.2f", radioSession.settings.scannerDwellSeconds)) s")
    lines.append("Scanner hold: \(String(format: "%.2f", radioSession.settings.scannerHoldSeconds)) s")
    lines.append("Scanner adaptive: \(radioSession.settings.adaptiveScannerEnabled)")
    lines.append("Scanner save channel results: \(radioSession.settings.saveChannelScannerResultsEnabled)")
    lines.append("Scanner stop on signal: \(radioSession.settings.stopChannelScannerOnSignal)")
    lines.append("Scanner interference filter: \(radioSession.settings.filterChannelScannerInterferenceEnabled)")
    lines.append(
      "Scanner interference filter profile: \(radioSession.settings.channelScannerInterferenceFilterProfile.rawValue)"
    )
    let audioDiagnostics = radioSession.audioDiagnosticsSnapshot
    if let connectedDurationSeconds = audioDiagnostics.connectedDurationSeconds {
      lines.append("Connected for: \(String(format: "%.1f", connectedDurationSeconds)) s")
    }
    lines.append("Auto reconnect attempts: \(audioDiagnostics.automaticReconnectAttempts)")
    lines.append("Auto reconnect successes: \(audioDiagnostics.automaticReconnectSuccesses)")
    let sharedAudioSnapshot = SharedAudioOutput.engine.runtimeSnapshot()
    lines.append("Shared audio running: \(sharedAudioSnapshot.engineRunning)")
    lines.append("Shared audio queued buffers: \(sharedAudioSnapshot.queuedBuffers)")
    lines.append("Shared audio queued duration: \(String(format: "%.2f", sharedAudioSnapshot.queuedDurationSeconds)) s")
    lines.append("Shared audio peak queued buffers: \(audioDiagnostics.sharedAudio.peakQueuedBuffers)")
    lines.append("Shared audio session configured: \(sharedAudioSnapshot.sessionConfigured)")
    lines.append("Shared audio output rate: \(sharedAudioSnapshot.outputSampleRateHz) Hz")
    lines.append(
      "Shared audio peak enqueue gap: \(String(format: "%.2f", audioDiagnostics.sharedAudio.peakSecondsSinceLastEnqueue)) s"
    )
    lines.append("Shared audio samples: \(audioDiagnostics.sharedAudio.sampleCount)")
    if let inputRate = sharedAudioSnapshot.lastInputSampleRateHz {
      lines.append("Shared audio last input rate: \(inputRate) Hz")
    }
    if let secondsSinceLastEnqueue = sharedAudioSnapshot.secondsSinceLastEnqueue {
      lines.append("Shared audio last enqueue: \(String(format: "%.2f", secondsSinceLastEnqueue)) s ago")
    }
    if let recentLevelDBFS = sharedAudioSnapshot.recentLevelDBFS {
      lines.append("Shared audio recent level: \(String(format: "%.1f", recentLevelDBFS)) dBFS")
    }
    if let secondsSinceLastLevelSample = sharedAudioSnapshot.secondsSinceLastLevelSample {
      lines.append("Shared audio level sample age: \(String(format: "%.2f", secondsSinceLastLevelSample)) s")
    }
    if let recentEnvelopeVariation = sharedAudioSnapshot.recentEnvelopeVariation {
      lines.append("Shared audio envelope variation: \(String(format: "%.2f", recentEnvelopeVariation))")
    }
    if let recentZeroCrossingRate = sharedAudioSnapshot.recentZeroCrossingRate {
      lines.append("Shared audio zero crossing rate: \(String(format: "%.2f", recentZeroCrossingRate))")
    }
    if let recentSpectralActivity = sharedAudioSnapshot.recentSpectralActivity {
      lines.append("Shared audio spectral activity: \(String(format: "%.2f", recentSpectralActivity))")
    }
    if let recentLevelStdDB = sharedAudioSnapshot.recentLevelStdDB {
      lines.append("Shared audio level stability: \(String(format: "%.2f", recentLevelStdDB)) dB")
    }
    lines.append("Shared audio analysis buffers: \(sharedAudioSnapshot.recentAnalysisBufferCount)")
    if let lastStartError = sharedAudioSnapshot.lastStartError, !lastStartError.isEmpty {
      lines.append("Shared audio last start error: \(lastStartError)")
    }
    if let audioExcerpt = diagnostics.exportAudioExcerpt(), !audioExcerpt.isEmpty {
      lines.append("")
      lines.append("[Audio log tail]")
      lines.append(audioExcerpt)
    }
    lines.append("")

    lines.append("[Receiver data]")
    lines.append("OpenWebRX profiles: \(radioSession.openWebRXProfiles.count)")
    lines.append("OpenWebRX bookmarks: \(radioSession.serverBookmarks.count)")
    lines.append("OpenWebRX band plan entries: \(radioSession.openWebRXBandPlan.count)")
    lines.append("Channel scanner results: \(radioSession.channelScannerResults.count)")
    for result in radioSession.channelScannerResults.prefix(12) {
      lines.append(
        "- channel-scan title=\(result.name) freq=\(result.frequencyHz) mode=\(result.mode?.rawValue ?? "-") signal=\(String(format: "%.1f", result.signal)) \(result.signalUnit) detected=\(format(result.detectedAt))"
      )
    }
    lines.append("FM-DX station list entries: \(radioSession.fmdxServerPresets.count)")
    if let presetSource = radioSession.fmdxPresetSourceDescription, !presetSource.isEmpty {
      lines.append("FM-DX station list source: \(presetSource)")
    }
    if let kiwiBand = radioSession.currentKiwiBandName {
      lines.append("Kiwi band: \(kiwiBand)")
    }
    if let kiwiTelemetry = radioSession.kiwiTelemetry {
      if let rssi = kiwiTelemetry.rssiDBm {
        lines.append("Kiwi RSSI: \(String(format: "%.1f", rssi)) dBm")
      }
      lines.append("Kiwi sample rate: \(kiwiTelemetry.sampleRateHz) Hz")
      if let bandwidth = kiwiTelemetry.bandwidthHz {
        lines.append("Kiwi bandwidth: \(bandwidth) Hz")
      }
      if let fftSize = kiwiTelemetry.waterfallFFTSize {
        lines.append("Kiwi waterfall FFT: \(fftSize)")
      }
      if let zoomMax = kiwiTelemetry.zoomMax {
        lines.append("Kiwi waterfall zoom max: \(zoomMax)")
      }
      lines.append("Kiwi waterfall bins: \(kiwiTelemetry.waterfallBins.count)")
    }
    if let telemetry = radioSession.fmdxTelemetry {
      lines.append("FM-DX station: \(telemetry.ps ?? "-")")
      if let signal = telemetry.signal {
        lines.append("FM-DX signal: \(String(format: "%.1f", signal)) dBf")
      }
      let audioMode = telemetry.audioMode?.rawValue ?? "unknown"
      let forcedState = (telemetry.isForcedStereo ?? false) ? "forced" : "auto"
      lines.append("FM-DX audio mode: \(audioMode) (\(forcedState))")
    }
    if let quality = radioSession.fmdxAudioQualityReport {
      lines.append("FM-DX audio quality: \(quality.level.rawValue) (\(quality.score)/100)")
      lines.append("FM-DX queued duration: \(String(format: "%.2f", quality.queuedDurationSeconds)) s")
      lines.append("FM-DX queued buffers: \(quality.queuedBufferCount)")
      lines.append("FM-DX output gap: \(String(format: "%.2f", quality.outputGapSeconds)) s")
    }
    if let fmdxAudio = audioDiagnostics.fmdxAudio {
      lines.append("FM-DX audio samples: \(fmdxAudio.sampleCount)")
      lines.append("FM-DX audio queue started: \(fmdxAudio.queueStarted)")
      lines.append("FM-DX peak queued duration: \(String(format: "%.2f", fmdxAudio.peakQueuedDurationSeconds)) s")
      lines.append("FM-DX peak queued buffers: \(fmdxAudio.peakQueuedBuffers)")
      lines.append("FM-DX peak output gap: \(String(format: "%.2f", fmdxAudio.peakOutputGapSeconds)) s")
      lines.append("FM-DX latency trims: \(fmdxAudio.latencyTrimEvents)")
      if let qualityScore = fmdxAudio.currentQualityScore {
        lines.append("FM-DX current quality score: \(qualityScore)")
      }
      if let qualityLevel = fmdxAudio.currentQualityLevel {
        lines.append("FM-DX current quality level: \(qualityLevel)")
      }
    }
    lines.append("")

    lines.append("[Recording]")
    lines.append("Recording active: \(recordingStore.isRecording)")
    if let receiverName = recordingStore.activeReceiverName {
      lines.append("Recording receiver: \(receiverName)")
    }
    if let format = recordingStore.activeFormat {
      lines.append("Recording format: \(format.rawValue)")
    }
    lines.append("Saved recordings: \(recordingStore.recordings.count)")
    lines.append("")

    lines.append("[History]")
    lines.append("Recent receivers: \(historyStore.recentReceivers.count)")
    for record in historyStore.recentReceivers.prefix(10) {
      lines.append(
        "- receiver=\(record.receiverName) backend=\(record.backend.rawValue) endpoint=\(record.makeProfile().endpointDescription) last=\(format(record.lastUsedAt))"
      )
    }
    lines.append("Recent listening entries: \(historyStore.recentListening.count)")
    for record in historyStore.recentListening.prefix(15) {
      let title = record.stationTitle ?? "-"
      lines.append(
        "- title=\(title) receiver=\(record.receiverName) backend=\(record.backend.rawValue) freq=\(record.frequencyHz) mode=\(record.mode?.rawValue ?? "-") last=\(format(record.lastHeardAt))"
      )
    }
    lines.append("")

    lines.append("[Logs]")
    lines.append(diagnostics.exportText())
    return lines.joined(separator: "\n")
  }

  private static func format(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private static func connectionStateText(_ state: ConnectionState) -> String {
    switch state {
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .connected:
      return "connected"
    case .failed:
      return "failed"
    }
  }
}
