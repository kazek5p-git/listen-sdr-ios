import AVFAudio
import Foundation
import ShazamKit

private let shazamRecognitionSampleRate: Double = 16_000

private func makeShazamRecognitionBuffer(
  samples: [Float],
  sampleRate: Double,
  targetSampleRate: Double
) -> AVAudioPCMBuffer? {
  guard let inputFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: sampleRate,
    channels: 1,
    interleaved: false
  ) else {
    return nil
  }

  guard let inputBuffer = AVAudioPCMBuffer(
    pcmFormat: inputFormat,
    frameCapacity: AVAudioFrameCount(samples.count)
  ) else {
    return nil
  }

  inputBuffer.frameLength = AVAudioFrameCount(samples.count)
  guard let inputChannel = inputBuffer.floatChannelData?[0] else { return nil }
  for (index, sample) in samples.enumerated() {
    inputChannel[index] = sample
  }

  guard let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: targetSampleRate,
    channels: 1,
    interleaved: false
  ) else {
    return nil
  }

  guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
    return nil
  }

  let ratio = targetSampleRate / sampleRate
  let estimatedFrames = max(1, Int((Double(inputBuffer.frameLength) * ratio).rounded(.up)) + 32)
  guard let outputBuffer = AVAudioPCMBuffer(
    pcmFormat: outputFormat,
    frameCapacity: AVAudioFrameCount(estimatedFrames)
  ) else {
    return nil
  }

  var providedInput = false
  var conversionError: NSError?
  let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
    if providedInput {
      outStatus.pointee = .endOfStream
      return nil
    }
    providedInput = true
    outStatus.pointee = .haveData
    return inputBuffer
  }

  if conversionError != nil {
    return nil
  }

  switch status {
  case .haveData, .inputRanDry, .endOfStream:
    return outputBuffer.frameLength > 0 ? outputBuffer : nil
  case .error:
    return nil
  @unknown default:
    return nil
  }
}

@MainActor
final class ShazamRecognitionController: NSObject, ObservableObject, SHSessionDelegate {
  static let shared = ShazamRecognitionController()

  enum RecognitionState: Equatable {
    case idle
    case listening
    case matching
    case matched(title: String, artist: String?)
    case noMatch
    case unavailable(String)
  }

  @Published private(set) var state: RecognitionState = .idle

  private let processingQueue = DispatchQueue(label: "ListenSDR.ShazamRecognition")
  private let listenDurationSeconds: Double = 10
  private let matchTimeoutSeconds: Double = 10

  private var integrationEnabled = false
  private var activeBackend: SDRBackend?
  private var session: SHSession?
  private var collectedDurationSeconds = 0.0
  private var currentSamplePosition: AVAudioFramePosition = 0
  private var activeRequestID = UUID()
  private var timeoutTask: Task<Void, Never>?

  private override init() {
    super.init()
  }

  func setIntegrationEnabled(_ enabled: Bool) {
    integrationEnabled = enabled
    if !enabled {
      NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
      cancelRecognition(clearResult: true)
    }
  }

  func startRecognition(for backend: SDRBackend, isConnected: Bool) {
    guard integrationEnabled else { return }
    guard isConnected else {
      state = .unavailable(L10n.text("shazam.connect_first"))
      return
    }
    guard supportsRecognition(for: backend) else {
      state = .unavailable(L10n.text("shazam.unsupported_stream"))
      return
    }

    cancelRecognition(clearResult: true)
    NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
    activeBackend = backend
    session = SHSession()
    session?.delegate = self
    collectedDurationSeconds = 0
    currentSamplePosition = 0
    activeRequestID = UUID()
    state = .listening
    updateBackendCaptureState(enabled: true, for: backend)
    Diagnostics.log(category: "Shazam", message: "Recognition started for \(backend.displayName)")

    let requestID = activeRequestID
    let timeoutSeconds = listenDurationSeconds + matchTimeoutSeconds
    timeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
      guard let self else { return }
      guard self.activeRequestID == requestID else { return }
      if case .listening = self.state {
        self.state = .matching
        self.updateBackendCaptureState(enabled: false, for: self.activeBackend)
      }
      if case .matching = self.state {
        self.state = .noMatch
        NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
        Diagnostics.log(category: "Shazam", message: "Recognition finished with no match")
        self.cleanupActiveRecognition()
      }
    }
  }

  func cancelRecognition(clearResult: Bool = false) {
    updateBackendCaptureState(enabled: false, for: activeBackend)
    timeoutTask?.cancel()
    timeoutTask = nil
    cleanupActiveRecognition()
    if clearResult || state == .listening || state == .matching {
      state = .idle
    }
    if clearResult {
      NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
    }
    Diagnostics.log(category: "Shazam", message: "Recognition cancelled")
  }

  nonisolated func consumeFromAnyThread(samples: [Float], sampleRate: Double) {
    Task { @MainActor [weak self] in
      self?.consume(samples: samples, sampleRate: sampleRate)
    }
  }

  func consume(samples: [Float], sampleRate: Double) {
    guard integrationEnabled else { return }
    guard case .listening = state else { return }
    guard let backend = activeBackend, supportsRecognition(for: backend) else { return }
    guard !samples.isEmpty else { return }

    let requestID = activeRequestID
    let copiedSamples = samples
    let targetSampleRate = shazamRecognitionSampleRate

    processingQueue.async { [weak self] in
      guard let self else { return }
      guard let buffer = makeShazamRecognitionBuffer(
        samples: copiedSamples,
        sampleRate: sampleRate,
        targetSampleRate: targetSampleRate
      ) else { return }

      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.activeRequestID == requestID else { return }
        guard case .listening = self.state else { return }
        guard let session = self.session else { return }

        let audioTime = AVAudioTime(
          sampleTime: self.currentSamplePosition,
          atRate: targetSampleRate
        )

        session.matchStreamingBuffer(buffer, at: audioTime)
        self.currentSamplePosition += AVAudioFramePosition(buffer.frameLength)
        self.collectedDurationSeconds += Double(buffer.frameLength) / targetSampleRate

        if self.collectedDurationSeconds >= self.listenDurationSeconds {
          self.state = .matching
          self.updateBackendCaptureState(enabled: false, for: self.activeBackend)
          Diagnostics.log(category: "Shazam", message: "Recognition captured enough audio; awaiting match")
        }
      }
    }
  }

  func supportsRecognition(for backend: SDRBackend) -> Bool {
    switch backend {
    case .kiwiSDR, .openWebRX, .fmDxWebserver:
      return true
    }
  }

  nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.timeoutTask?.cancel()
      self.timeoutTask = nil

      guard let item = match.mediaItems.first else {
        self.state = .noMatch
        NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
        self.cleanupActiveRecognition()
        return
      }

      let title = self.normalized(self.stringValue(for: "title", in: item))
        ?? L10n.text("shazam.result.unknown_title")
      let artist = self.normalized(self.stringValue(for: "artist", in: item))
        ?? self.normalized(self.stringValue(for: "subtitle", in: item))
      NowPlayingMetadataController.shared.setRecognizedTrack(title: title, artist: artist)
      self.state = .matched(title: title, artist: artist)
      Diagnostics.log(category: "Shazam", message: "Recognition matched: \(title)")
      self.cleanupActiveRecognition()
    }
  }

  nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard self.session === session else { return }

      if let error {
        let message = self.normalized(error.localizedDescription) ?? L10n.text("shazam.error")
        self.state = .unavailable(message)
        NowPlayingMetadataController.shared.setRecognizedTrack(title: nil, artist: nil)
        Diagnostics.log(
          severity: .error,
          category: "Shazam",
          message: "Recognition failed: \(message)"
        )
        self.cleanupActiveRecognition()
        return
      }

      Diagnostics.log(
        category: "Shazam",
        message: "Streaming buffer produced no immediate match; continuing until timeout"
      )
    }
  }

  private func cleanupActiveRecognition() {
    updateBackendCaptureState(enabled: false, for: activeBackend)
    session?.delegate = nil
    session = nil
    collectedDurationSeconds = 0
    currentSamplePosition = 0
    activeBackend = nil
    activeRequestID = UUID()
  }

  private func stringValue(for key: String, in item: SHMatchedMediaItem) -> String? {
    item.value(forKey: key) as? String
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func updateBackendCaptureState(enabled: Bool, for backend: SDRBackend?) {
    guard backend == .fmDxWebserver else { return }
    FMDXMP3AudioPlayer.shared.setRecognitionCaptureEnabled(enabled)
  }
}
