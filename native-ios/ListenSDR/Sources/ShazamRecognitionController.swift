import AVFAudio
import Foundation
import ShazamKit

@MainActor
final class ShazamRecognitionController: NSObject, ObservableObject, SHSessionDelegate {
  static let shared = ShazamRecognitionController()
  private static let recognitionSampleRate: Double = 16_000

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
  private let listenDurationSeconds: Double = 8
  private let matchTimeoutSeconds: Double = 10

  private var integrationEnabled = false
  private var activeBackend: SDRBackend?
  private var session: SHSession?
  private var signatureGenerator: SHSignatureGenerator?
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
    activeBackend = backend
    session = SHSession()
    session?.delegate = self
    signatureGenerator = SHSignatureGenerator()
    collectedDurationSeconds = 0
    currentSamplePosition = 0
    activeRequestID = UUID()
    state = .listening

    let requestID = activeRequestID
    timeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64((listenDurationSeconds + matchTimeoutSeconds) * 1_000_000_000))
      guard let self else { return }
      guard self.activeRequestID == requestID else { return }
      if case .listening = self.state {
        self.finishListeningAndMatch()
      }
      if case .matching = self.state {
        self.state = .noMatch
        self.cleanupActiveRecognition()
      }
    }
  }

  func cancelRecognition(clearResult: Bool = false) {
    timeoutTask?.cancel()
    timeoutTask = nil
    cleanupActiveRecognition()
    state = clearResult ? .idle : state
  }

  func consume(samples: [Float], sampleRate: Double) {
    guard integrationEnabled else { return }
    guard case .listening = state else { return }
    guard let backend = activeBackend, supportsRecognition(for: backend) else { return }
    guard !samples.isEmpty else { return }

    let requestID = activeRequestID
    let copiedSamples = samples

    processingQueue.async { [weak self] in
      guard let self else { return }
      guard let buffer = Self.makeRecognitionBuffer(
        samples: copiedSamples,
        sampleRate: sampleRate,
        targetSampleRate: Self.recognitionSampleRate
      ) else { return }

      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.activeRequestID == requestID else { return }
        guard case .listening = self.state else { return }
        guard let signatureGenerator = self.signatureGenerator else { return }

        let audioTime = AVAudioTime(
          sampleTime: self.currentSamplePosition,
          atRate: Self.recognitionSampleRate
        )

        do {
          try signatureGenerator.append(buffer, at: audioTime)
          self.currentSamplePosition += AVAudioFramePosition(buffer.frameLength)
          self.collectedDurationSeconds += Double(buffer.frameLength) / Self.recognitionSampleRate

          if self.collectedDurationSeconds >= self.listenDurationSeconds {
            self.finishListeningAndMatch()
          }
        } catch {
          self.state = .unavailable(L10n.text("shazam.error"))
          self.cleanupActiveRecognition()
        }
      }
    }
  }

  func supportsRecognition(for backend: SDRBackend) -> Bool {
    switch backend {
    case .kiwiSDR, .openWebRX:
      return true
    case .fmDxWebserver:
      return false
    }
  }

  func session(_ session: SHSession, didFind match: SHMatch) {
    timeoutTask?.cancel()
    timeoutTask = nil

    guard let item = match.mediaItems.first else {
      state = .noMatch
      cleanupActiveRecognition()
      return
    }

    let title = normalized(stringValue(for: "title", in: item)) ?? L10n.text("shazam.result.unknown_title")
    let artist = normalized(stringValue(for: "artist", in: item))
      ?? normalized(stringValue(for: "subtitle", in: item))
    state = .matched(title: title, artist: artist)
    cleanupActiveRecognition()
  }

  private func finishListeningAndMatch() {
    guard case .listening = state else { return }
    guard let session, let signatureGenerator else {
      state = .noMatch
      cleanupActiveRecognition()
      return
    }

    let signature = signatureGenerator.signature()
    state = .matching
    session.match(signature)
  }

  private func cleanupActiveRecognition() {
    session?.delegate = nil
    session = nil
    signatureGenerator = nil
    collectedDurationSeconds = 0
    currentSamplePosition = 0
    activeBackend = nil
  }

  private static func makeRecognitionBuffer(
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
        outStatus.pointee = .noDataNow
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
    case .error, .noDataNow:
      return nil
    @unknown default:
      return nil
    }
  }

  private func stringValue(for key: String, in item: SHMatchedMediaItem) -> String? {
    item.value(forKey: key) as? String
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
