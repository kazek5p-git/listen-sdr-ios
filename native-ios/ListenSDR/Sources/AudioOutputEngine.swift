import AVFAudio
import Foundation

struct SharedAudioRuntimeSnapshot {
  let outputSampleRateHz: Int
  let lastInputSampleRateHz: Int?
  let queuedBuffers: Int
  let queuedDurationSeconds: TimeInterval
  let engineRunning: Bool
  let sessionConfigured: Bool
  let secondsSinceLastEnqueue: TimeInterval?
  let recentLevelDBFS: Double?
  let secondsSinceLastLevelSample: TimeInterval?
  let recentEnvelopeVariation: Double?
  let recentZeroCrossingRate: Double?
  let recentSpectralActivity: Double?
  let recentLevelStdDB: Double?
  let recentAnalysisBufferCount: Int
  let lastStartError: String?
}

@MainActor
final class AudioOutputEngine {
  private struct SharedAudioSignalMetrics {
    let capturedAt: Date
    let levelDBFS: Double
    let envelopeVariation: Double
    let zeroCrossingRate: Double
    let spectralActivity: Double
  }

  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let outputSampleRate = AudioPCMUtilities.preferredOutputSampleRate
  private let preferredIOBufferDurationSeconds: TimeInterval = 0.023
  private let startupBufferedSeconds: TimeInterval = 0.18
  private let startupBufferedChunks = 3
  private lazy var outputFormat: AVAudioFormat? = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: outputSampleRate,
    channels: 2,
    interleaved: false
  )
  private var queuedBuffers = 0
  private var queuedDurationSeconds: TimeInterval = 0
  private var queuedBufferDurations: [ObjectIdentifier: TimeInterval] = [:]
  private let maxQueuedBuffers = 96
  private var sessionConfigured = false
  private var graphConfigured = false
  private var desiredVolume: Float = 0.85
  private var muted = false
  private var scannerPlaybackMuted = false
  private var mixWithOtherAudioApps = false
  private var speechLoudnessLevelingMode: SpeechLoudnessLevelingMode = .off
  private let speechLoudnessLeveler = SpeechLoudnessLeveler()
  private var lastInputSampleRateHz: Int?
  private var lastEnqueueAt = Date.distantPast
  private var lastLevelDBFS: Double?
  private var lastLevelSampleAt = Date.distantPast
  private var recentSignalMetrics: [SharedAudioSignalMetrics] = []
  private var lastStartError: String?
  private var needsBufferedPlaybackStart = true
  private var isSessionInterrupted = false
  private var shouldResumeAfterInterruption = false
  private var notificationTokens: [NSObjectProtocol] = []

  init() {
    engine.attach(playerNode)
    installSessionObservers()
    applyOutputLevel()
  }

  func enqueueMono(samples: [Float], sampleRate: Double) {
    guard !samples.isEmpty else { return }
    guard !isSessionInterrupted else { return }
    guard let outputFormat else {
      log("Unable to create shared audio output format.", severity: .error)
      return
    }

    let inputSampleRate = AudioPCMUtilities.sanitizedInputSampleRate(sampleRate)
    let resampledSamples = AudioPCMUtilities.resampleMono(
      samples,
      from: inputSampleRate,
      to: outputSampleRate
    )
    guard !resampledSamples.isEmpty else { return }
    let playbackSamples = speechLoudnessLevelingMode != .off
      ? speechLoudnessLeveler.process(resampledSamples)
      : resampledSamples
    let bufferDurationSeconds = Double(playbackSamples.count) / outputSampleRate

    configureAudioSessionIfNeeded(force: !sessionConfigured || !engine.isRunning)
    ensureGraphConfigured()

    guard queuedBuffers < maxQueuedBuffers else { return }
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: AVAudioFrameCount(resampledSamples.count)
    ) else {
      return
    }

    buffer.frameLength = AVAudioFrameCount(playbackSamples.count)
    guard
      let leftChannel = buffer.floatChannelData?[0],
      let rightChannel = buffer.floatChannelData?[1]
    else {
      return
    }
    var sumSquares = 0.0
    var sumAbsolute = 0.0
    var sumAbsoluteSquares = 0.0
    var sumAbsoluteDelta = 0.0
    var zeroCrossings = 0
    var previousValue = 0.0
    var hasPreviousValue = false
    for (index, sample) in playbackSamples.enumerated() {
      leftChannel[index] = sample
      rightChannel[index] = sample
      let value = Double(sample)
      let absoluteValue = abs(value)
      sumSquares += value * value
      sumAbsolute += absoluteValue
      sumAbsoluteSquares += absoluteValue * absoluteValue
      if hasPreviousValue {
        sumAbsoluteDelta += abs(value - previousValue)
        if (previousValue <= 0 && value > 0) || (previousValue >= 0 && value < 0) {
          zeroCrossings += 1
        }
      } else {
        hasPreviousValue = true
      }
      previousValue = value
    }
    let rms = sqrt(sumSquares / Double(playbackSamples.count))
    let levelDBFS: Double = {
      guard rms.isFinite, rms > 0.000_001 else { return -80 }
      return max(-80, min(0, 20.0 * log10(rms)))
    }()
    let meanAbsolute = sumAbsolute / Double(playbackSamples.count)
    let envelopeVariance = max(
      0,
      (sumAbsoluteSquares / Double(playbackSamples.count)) - (meanAbsolute * meanAbsolute)
    )
    let envelopeVariation = meanAbsolute > 0.000_001
      ? min(4.0, sqrt(envelopeVariance) / meanAbsolute)
      : 0
    let zeroCrossingRate = playbackSamples.count > 1
      ? Double(zeroCrossings) / Double(playbackSamples.count - 1)
      : 0
    let spectralActivity = playbackSamples.count > 1 && meanAbsolute > 0.000_001
      ? min(
        4.0,
        (sumAbsoluteDelta / Double(playbackSamples.count - 1)) / meanAbsolute
      )
      : 0
    let analysisTimestamp = Date()

    AudioRecordingController.shared.consumePCM(samples: samples, sampleRate: inputSampleRate)

    guard startEngineIfNeeded() else {
      return
    }

    let bufferID = ObjectIdentifier(buffer)
    queuedBuffers += 1
    queuedDurationSeconds += bufferDurationSeconds
    queuedBufferDurations[bufferID] = bufferDurationSeconds
    lastInputSampleRateHz = Int(inputSampleRate.rounded())
    lastEnqueueAt = analysisTimestamp
    lastLevelDBFS = levelDBFS
    lastLevelSampleAt = lastEnqueueAt
    appendSignalMetrics(
      capturedAt: analysisTimestamp,
      levelDBFS: levelDBFS,
      envelopeVariation: envelopeVariation,
      zeroCrossingRate: zeroCrossingRate,
      spectralActivity: spectralActivity
    )
    playerNode.scheduleBuffer(buffer) { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.queuedBuffers = max(0, self.queuedBuffers - 1)
        if let duration = self.queuedBufferDurations.removeValue(forKey: bufferID) {
          self.queuedDurationSeconds = max(0, self.queuedDurationSeconds - duration)
        }
        self.handleQueueDrainIfNeeded()
      }
    }

    startPlaybackIfReady()
  }

  func stop() {
    queuedBuffers = 0
    queuedDurationSeconds = 0
    queuedBufferDurations.removeAll()
    needsBufferedPlaybackStart = true
    playerNode.stop()
    engine.stop()
    lastInputSampleRateHz = nil
    lastEnqueueAt = .distantPast
    lastLevelDBFS = nil
    lastLevelSampleAt = .distantPast
    recentSignalMetrics.removeAll()
    scannerPlaybackMuted = false
    speechLoudnessLeveler.reset()
    NowPlayingMetadataController.shared.stopPlayback()
    deactivateAudioSessionIfPossible()
  }

  func setVolume(_ value: Double) {
    desiredVolume = Float(min(max(value, 0), 1))
    applyOutputLevel()
  }

  func setMuted(_ value: Bool) {
    muted = value
    applyOutputLevel()
  }

  func setScannerPlaybackMuted(_ value: Bool) {
    guard scannerPlaybackMuted != value else { return }
    scannerPlaybackMuted = value
    applyOutputLevel()
  }

  func setMixWithOtherAudioApps(_ enabled: Bool) {
    guard mixWithOtherAudioApps != enabled else { return }
    mixWithOtherAudioApps = enabled
    sessionConfigured = false
    if engine.isRunning || queuedBuffers > 0 {
      configureAudioSessionIfNeeded(force: true)
    }
  }

  func setSpeechLoudnessLeveling(
    mode: SpeechLoudnessLevelingMode,
    customProfile: SpeechLoudnessLevelingProfile
  ) {
    let resolvedProfile = mode == .custom
      ? customProfile
      : AudioOutputEngine.profile(for: mode)
    let modeChanged = speechLoudnessLevelingMode != mode
    speechLoudnessLevelingMode = mode
    speechLoudnessLeveler.updateProfile(resolvedProfile)
    if modeChanged && mode == .off {
      speechLoudnessLeveler.reset()
    }
  }

  func runtimeSnapshot() -> SharedAudioRuntimeSnapshot {
    let aggregatedSignalMetrics = aggregateRecentSignalMetrics()
    return SharedAudioRuntimeSnapshot(
      outputSampleRateHz: Int(outputSampleRate.rounded()),
      lastInputSampleRateHz: lastInputSampleRateHz,
      queuedBuffers: queuedBuffers,
      queuedDurationSeconds: queuedDurationSeconds,
      engineRunning: engine.isRunning,
      sessionConfigured: sessionConfigured,
      secondsSinceLastEnqueue: lastEnqueueAt == .distantPast ? nil : Date().timeIntervalSince(lastEnqueueAt),
      recentLevelDBFS: lastLevelDBFS,
      secondsSinceLastLevelSample: lastLevelSampleAt == .distantPast ? nil : Date().timeIntervalSince(lastLevelSampleAt),
      recentEnvelopeVariation: aggregatedSignalMetrics.envelopeVariation,
      recentZeroCrossingRate: aggregatedSignalMetrics.zeroCrossingRate,
      recentSpectralActivity: aggregatedSignalMetrics.spectralActivity,
      recentLevelStdDB: aggregatedSignalMetrics.levelStdDB,
      recentAnalysisBufferCount: aggregatedSignalMetrics.count,
      lastStartError: lastStartError
    )
  }

  private func configureAudioSessionIfNeeded(force: Bool) {
    guard force || !sessionConfigured else { return }
    let session = AVAudioSession.sharedInstance()
    let options = audioSessionCategoryOptions()

    do {
      try session.setCategory(.playback, mode: .default, options: options)
      try session.setPreferredIOBufferDuration(preferredIOBufferDurationSeconds)
      try session.setPreferredSampleRate(outputSampleRate)
      try session.setActive(true, options: [])
      sessionConfigured = true
      lastStartError = nil
    } catch {
      do {
        let fallbackOptions: AVAudioSession.CategoryOptions = mixWithOtherAudioApps ? [.mixWithOthers] : []
        try session.setCategory(.playback, mode: .default, options: fallbackOptions)
        try session.setActive(true, options: [])
        sessionConfigured = true
        lastStartError = nil
      } catch {
        sessionConfigured = false
        lastStartError = error.localizedDescription
        log("Shared audio session setup failed: \(error.localizedDescription)", severity: .warning)
      }
    }
  }

  private func ensureGraphConfigured() {
    guard let outputFormat else { return }
    guard !graphConfigured else {
      return
    }

    queuedBuffers = 0
    queuedDurationSeconds = 0
    queuedBufferDurations.removeAll()
    needsBufferedPlaybackStart = true
    playerNode.stop()
    engine.stop()
    engine.disconnectNodeOutput(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
    engine.prepare()
    graphConfigured = true
    applyOutputLevel()
  }

  private func startEngineIfNeeded() -> Bool {
    if engine.isRunning {
      lastStartError = nil
      return true
    }

    do {
      try engine.start()
      lastStartError = nil
      return true
    } catch {
      let firstError = error.localizedDescription
      log("Shared audio engine start failed: \(firstError). Retrying...", severity: .warning)
      lastStartError = firstError
      sessionConfigured = false
      configureAudioSessionIfNeeded(force: true)
      recoverGraph()

      do {
        try engine.start()
        lastStartError = nil
        log("Shared audio engine recovered after restart.")
        return true
      } catch {
        lastStartError = error.localizedDescription
        log("Shared audio engine restart failed: \(error.localizedDescription)", severity: .error)
        return false
      }
    }
  }

  private func recoverGraph() {
    playerNode.stop()
    engine.stop()
    engine.reset()
    queuedBuffers = 0
    queuedDurationSeconds = 0
    queuedBufferDurations.removeAll()
    recentSignalMetrics.removeAll()
    speechLoudnessLeveler.reset()
    scannerPlaybackMuted = false
    needsBufferedPlaybackStart = true
    graphConfigured = false
    ensureGraphConfigured()
  }

  private func applyOutputLevel() {
    playerNode.volume = (muted || scannerPlaybackMuted) ? 0 : desiredVolume
  }

  private func audioSessionCategoryOptions() -> AVAudioSession.CategoryOptions {
    var options: AVAudioSession.CategoryOptions = [.allowAirPlay]
    if mixWithOtherAudioApps {
      options.insert(.mixWithOthers)
    }
    return options
  }

  private static func profile(for mode: SpeechLoudnessLevelingMode) -> SpeechLoudnessLevelingProfile {
    switch mode {
    case .off, .gentle:
      return .gentle
    case .strong:
      return .strong
    case .veryStrong:
      return .veryStrong
    case .custom:
      return .gentle
    }
  }

  private func deactivateAudioSessionIfPossible() {
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
      sessionConfigured = false
    } catch {
      log("Shared audio session deactivation failed: \(error.localizedDescription)", severity: .warning)
    }
  }

  private func installSessionObservers() {
    let center = NotificationCenter.default
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        Task { @MainActor in
          self?.handleAudioSessionInterruption(notification)
        }
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        Task { @MainActor in
          self?.handleAudioRouteChange(notification)
        }
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.sessionConfigured = false
          self?.recoverGraph()
          self?.log("Audio media services were reset.", severity: .warning)
        }
      }
    )
  }

  private func handleAudioSessionInterruption(_ notification: Notification) {
    guard
      let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      return
    }

    switch type {
    case .began:
      beginAudioSessionInterruption()
    case .ended:
      let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      endAudioSessionInterruption(shouldResume: options.contains(.shouldResume))
    @unknown default:
      sessionConfigured = false
    }
  }

  private func handleAudioRouteChange(_ notification: Notification) {
    sessionConfigured = false
    if let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
      log("Shared audio route changed (\(reason.rawValue)).")
    } else {
      log("Shared audio route changed.")
    }
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(severity: severity, category: "Shared Audio", message: message)
  }

  private func beginAudioSessionInterruption() {
    guard !isSessionInterrupted else { return }

    isSessionInterrupted = true
    shouldResumeAfterInterruption = playerNode.isPlaying || engine.isRunning || queuedBuffers > 0
    clearPlaybackStateForInterruption()
    sessionConfigured = false
    log("Shared audio session interrupted. Audio paused for system interruption.", severity: .warning)
  }

  private func endAudioSessionInterruption(shouldResume: Bool) {
    let shouldRearm = shouldResumeAfterInterruption || shouldResume
    isSessionInterrupted = false
    shouldResumeAfterInterruption = false
    sessionConfigured = false

    guard shouldRearm else {
      log("Shared audio session interruption ended.")
      return
    }

    configureAudioSessionIfNeeded(force: true)
    ensureGraphConfigured()
    log("Shared audio session interruption ended. Audio will resume when stream data arrives.")
  }

  private func clearPlaybackStateForInterruption() {
    queuedBuffers = 0
    queuedDurationSeconds = 0
    queuedBufferDurations.removeAll()
    needsBufferedPlaybackStart = true
    playerNode.stop()
    engine.stop()
    engine.reset()
    graphConfigured = false
    lastInputSampleRateHz = nil
    lastEnqueueAt = .distantPast
    lastLevelDBFS = nil
    lastLevelSampleAt = .distantPast
    recentSignalMetrics.removeAll()
    NowPlayingMetadataController.shared.stopPlayback()
  }

  private func appendSignalMetrics(
    capturedAt: Date,
    levelDBFS: Double,
    envelopeVariation: Double,
    zeroCrossingRate: Double,
    spectralActivity: Double
  ) {
    recentSignalMetrics.append(
      SharedAudioSignalMetrics(
        capturedAt: capturedAt,
        levelDBFS: levelDBFS,
        envelopeVariation: envelopeVariation,
        zeroCrossingRate: zeroCrossingRate,
        spectralActivity: spectralActivity
      )
    )
    if recentSignalMetrics.count > 12 {
      recentSignalMetrics.removeFirst(recentSignalMetrics.count - 12)
    }
  }

  private func aggregateRecentSignalMetrics() -> (
    envelopeVariation: Double?,
    zeroCrossingRate: Double?,
    spectralActivity: Double?,
    levelStdDB: Double?,
    count: Int
  ) {
    let cutoff = Date().addingTimeInterval(-1.2)
    let window = recentSignalMetrics.filter { $0.capturedAt >= cutoff }.suffix(8)
    guard !window.isEmpty else {
      return (nil, nil, nil, nil, 0)
    }

    let count = window.count
    let averageEnvelopeVariation = window.map(\.envelopeVariation).reduce(0, +) / Double(count)
    let averageZeroCrossingRate = window.map(\.zeroCrossingRate).reduce(0, +) / Double(count)
    let averageSpectralActivity = window.map(\.spectralActivity).reduce(0, +) / Double(count)
    let averageLevel = window.map(\.levelDBFS).reduce(0, +) / Double(count)
    let levelVariance = window.reduce(0.0) { partialResult, metrics in
      let delta = metrics.levelDBFS - averageLevel
      return partialResult + (delta * delta)
    } / Double(count)

    return (
      averageEnvelopeVariation,
      averageZeroCrossingRate,
      averageSpectralActivity,
      sqrt(max(0, levelVariance)),
      count
    )
  }

  private func startPlaybackIfReady() {
    if needsBufferedPlaybackStart {
      let hasBufferedEnough = queuedDurationSeconds >= startupBufferedSeconds
        || queuedBuffers >= startupBufferedChunks
      guard hasBufferedEnough else { return }
    }

    guard !playerNode.isPlaying else { return }

    playerNode.play()
    needsBufferedPlaybackStart = false
    NowPlayingMetadataController.shared.startPlayback(source: "Live SDR stream")
    log(
      String(
        format: "Shared audio playback started with %.2f s queued across %d buffers.",
        queuedDurationSeconds,
        queuedBuffers
      )
    )
  }

  private func handleQueueDrainIfNeeded() {
    guard queuedBuffers == 0 else { return }
    guard queuedDurationSeconds <= 0.001 else { return }
    guard playerNode.isPlaying else { return }

    playerNode.stop()
    needsBufferedPlaybackStart = true
    log("Shared audio queue drained; waiting for buffered resume.", severity: .warning)
  }
}

enum SharedAudioOutput {
  @MainActor static let engine = AudioOutputEngine()
}
