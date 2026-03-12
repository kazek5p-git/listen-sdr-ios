import AVFAudio
import Foundation

struct SharedAudioRuntimeSnapshot {
  let outputSampleRateHz: Int
  let lastInputSampleRateHz: Int?
  let queuedBuffers: Int
  let engineRunning: Bool
  let sessionConfigured: Bool
  let secondsSinceLastEnqueue: TimeInterval?
  let lastStartError: String?
}

@MainActor
final class AudioOutputEngine {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let outputSampleRate = AudioPCMUtilities.preferredOutputSampleRate
  private lazy var outputFormat: AVAudioFormat? = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: outputSampleRate,
    channels: 2,
    interleaved: false
  )
  private var queuedBuffers = 0
  private let maxQueuedBuffers = 96
  private var sessionConfigured = false
  private var graphConfigured = false
  private var desiredVolume: Float = 0.85
  private var muted = false
  private var lastInputSampleRateHz: Int?
  private var lastEnqueueAt = Date.distantPast
  private var lastStartError: String?
  private var notificationTokens: [NSObjectProtocol] = []

  init() {
    engine.attach(playerNode)
    installSessionObservers()
    applyOutputLevel()
  }

  func enqueueMono(samples: [Float], sampleRate: Double) {
    guard !samples.isEmpty else { return }
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

    configureAudioSessionIfNeeded(force: !sessionConfigured || !engine.isRunning)
    ensureGraphConfigured()

    guard queuedBuffers < maxQueuedBuffers else { return }
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: AVAudioFrameCount(resampledSamples.count)
    ) else {
      return
    }

    buffer.frameLength = AVAudioFrameCount(resampledSamples.count)
    guard
      let leftChannel = buffer.floatChannelData?[0],
      let rightChannel = buffer.floatChannelData?[1]
    else {
      return
    }
    for (index, sample) in resampledSamples.enumerated() {
      leftChannel[index] = sample
      rightChannel[index] = sample
    }

    AudioRecordingController.shared.consumePCM(samples: samples, sampleRate: inputSampleRate)

    guard startEngineIfNeeded() else {
      return
    }

    queuedBuffers += 1
    lastInputSampleRateHz = Int(inputSampleRate.rounded())
    lastEnqueueAt = Date()
    playerNode.scheduleBuffer(buffer) { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.queuedBuffers = max(0, self.queuedBuffers - 1)
      }
    }

    if !playerNode.isPlaying {
      playerNode.play()
      NowPlayingMetadataController.shared.startPlayback(source: "Live SDR stream")
    }
  }

  func stop() {
    queuedBuffers = 0
    playerNode.stop()
    engine.stop()
    lastInputSampleRateHz = nil
    lastEnqueueAt = .distantPast
    NowPlayingMetadataController.shared.stopPlayback()
  }

  func setVolume(_ value: Double) {
    desiredVolume = Float(min(max(value, 0), 1))
    applyOutputLevel()
  }

  func setMuted(_ value: Bool) {
    muted = value
    applyOutputLevel()
  }

  func runtimeSnapshot() -> SharedAudioRuntimeSnapshot {
    SharedAudioRuntimeSnapshot(
      outputSampleRateHz: Int(outputSampleRate.rounded()),
      lastInputSampleRateHz: lastInputSampleRateHz,
      queuedBuffers: queuedBuffers,
      engineRunning: engine.isRunning,
      sessionConfigured: sessionConfigured,
      secondsSinceLastEnqueue: lastEnqueueAt == .distantPast ? nil : Date().timeIntervalSince(lastEnqueueAt),
      lastStartError: lastStartError
    )
  }

  private func configureAudioSessionIfNeeded(force: Bool) {
    guard force || !sessionConfigured else { return }
    let session = AVAudioSession.sharedInstance()

    do {
      try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
      try session.setPreferredIOBufferDuration(0.010)
      try session.setPreferredSampleRate(outputSampleRate)
      try session.setActive(true, options: [])
      sessionConfigured = true
      lastStartError = nil
    } catch {
      do {
        try session.setCategory(.playback, mode: .default, options: [])
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
    graphConfigured = false
    ensureGraphConfigured()
  }

  private func applyOutputLevel() {
    playerNode.volume = muted ? 0 : desiredVolume
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
      sessionConfigured = false
      log("Shared audio session interrupted.", severity: .warning)
    case .ended:
      sessionConfigured = false
      log("Shared audio session interruption ended.")
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
}

enum SharedAudioOutput {
  @MainActor static let engine = AudioOutputEngine()
}
