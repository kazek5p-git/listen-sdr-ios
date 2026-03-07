import AVFAudio
import Foundation

@MainActor
final class AudioOutputEngine {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var currentSampleRate: Double?
  private var queuedBuffers = 0
  private let maxQueuedBuffers = 96
  private var sessionConfigured = false
  private var desiredVolume: Float = 0.85
  private var muted = false

  init() {
    engine.attach(playerNode)
    applyOutputLevel()
  }

  func enqueueMono(samples: [Float], sampleRate: Double) {
    guard !samples.isEmpty else { return }
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: sampleRate,
      channels: 1,
      interleaved: false
    ) else {
      return
    }

    configureAudioSessionIfNeeded()
    reconfigureGraphIfNeeded(with: format)

    guard queuedBuffers < maxQueuedBuffers else { return }
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: AVAudioFrameCount(samples.count)
    ) else {
      return
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    guard let destination = buffer.floatChannelData?[0] else { return }
    for (index, sample) in samples.enumerated() {
      destination[index] = sample
    }

    if !engine.isRunning {
      do {
        try engine.start()
      } catch {
        return
      }
    }

    if !playerNode.isPlaying {
      playerNode.play()
    }

    queuedBuffers += 1
    playerNode.scheduleBuffer(buffer) { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.queuedBuffers = max(0, self.queuedBuffers - 1)
      }
    }
  }

  func stop() {
    queuedBuffers = 0
    playerNode.stop()
    engine.stop()
    currentSampleRate = nil
  }

  func setVolume(_ value: Double) {
    desiredVolume = Float(min(max(value, 0), 1))
    applyOutputLevel()
  }

  func setMuted(_ value: Bool) {
    muted = value
    applyOutputLevel()
  }

  private func configureAudioSessionIfNeeded() {
    guard !sessionConfigured else { return }
    let session = AVAudioSession.sharedInstance()

    do {
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setPreferredSampleRate(48_000)
      try session.setActive(true, options: [])
      sessionConfigured = true
    } catch {
      sessionConfigured = false
    }
  }

  private func reconfigureGraphIfNeeded(with format: AVAudioFormat) {
    if currentSampleRate == format.sampleRate {
      return
    }

    queuedBuffers = 0
    playerNode.stop()
    engine.stop()
    engine.disconnectNodeOutput(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    currentSampleRate = format.sampleRate
    applyOutputLevel()
  }

  private func applyOutputLevel() {
    playerNode.volume = muted ? 0 : desiredVolume
  }
}

enum SharedAudioOutput {
  @MainActor static let engine = AudioOutputEngine()
}
