import Foundation
import SwiftUI

enum AudioRecordingFormat: String, Codable {
  case wav
  case mp3

  var fileExtension: String {
    switch self {
    case .wav:
      return "wav"
    case .mp3:
      return "mp3"
    }
  }

  var localizedTitle: String {
    switch self {
    case .wav:
      return L10n.text("recordings.format.wav")
    case .mp3:
      return L10n.text("recordings.format.mp3")
    }
  }
}

struct AudioRecordingInfo: Identifiable, Codable, Hashable {
  let id: UUID
  let receiverName: String
  let backend: SDRBackend
  let frequencyHz: Int
  let mode: DemodulationMode?
  let format: AudioRecordingFormat
  let filePath: String
  let createdAt: Date
  let finishedAt: Date
  let byteCount: Int64

  var fileURL: URL {
    URL(fileURLWithPath: filePath)
  }

  var displayFileName: String {
    fileURL.lastPathComponent
  }

  var durationSeconds: TimeInterval {
    max(finishedAt.timeIntervalSince(createdAt), 0)
  }

  var durationText: String {
    Self.durationFormatter.string(from: durationSeconds) ?? "0:00"
  }

  private static let durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = [.pad]
    return formatter
  }()
}

extension AudioRecordingInfo {
  var title: String {
    displayFileName
  }
}

struct AudioRecordingSessionSnapshot {
  let isRecording: Bool
  let receiverName: String?
  let format: AudioRecordingFormat?
}

struct AudioRecordingContext {
  let receiverName: String
  let backend: SDRBackend
  let frequencyHz: Int
  let mode: DemodulationMode?
  let format: AudioRecordingFormat
}

private struct ActiveAudioRecording {
  let id: UUID
  let context: AudioRecordingContext
  let fileURL: URL
  let handle: FileHandle
  let createdAt: Date
  var byteCount: Int64
  var sampleRate: Double?
  var pcmFrameCount: UInt32
}

final class AudioRecordingController {
  static let shared = AudioRecordingController()

  private let queue = DispatchQueue(label: "ListenSDR.AudioRecordingController")
  private let fileManager = FileManager.default
  private let indexURL: URL
  private let recordingsDirectoryURL: URL
  private var recordings: [AudioRecordingInfo] = []
  private var activeRecording: ActiveAudioRecording?

  private init() {
    let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    recordingsDirectoryURL = root.appendingPathComponent("Recordings", isDirectory: true)
    indexURL = recordingsDirectoryURL.appendingPathComponent("recordings-index.json")
    try? fileManager.createDirectory(
      at: recordingsDirectoryURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    loadRecordings()
  }

  func currentSnapshot() -> AudioRecordingSessionSnapshot {
    queue.sync {
      AudioRecordingSessionSnapshot(
        isRecording: activeRecording != nil,
        receiverName: activeRecording?.context.receiverName,
        format: activeRecording?.context.format
      )
    }
  }

  func listRecordings() -> [AudioRecordingInfo] {
    queue.sync {
      recordings.sorted { $0.createdAt > $1.createdAt }
    }
  }

  func startRecording(context: AudioRecordingContext) throws -> AudioRecordingSessionSnapshot {
    try queue.sync {
      if activeRecording != nil {
        _ = stopRecordingLocked()
      }

      let id = UUID()
      let timestamp = recordingTimestampFormatter.string(from: Date())
      let safeReceiver = sanitizedFileComponent(context.receiverName)
      let fileName = "\(timestamp)-\(safeReceiver).\(context.format.fileExtension)"
      let fileURL = recordingsDirectoryURL.appendingPathComponent(fileName)
      fileManager.createFile(atPath: fileURL.path, contents: nil)
      let handle = try FileHandle(forWritingTo: fileURL)

      var recording = ActiveAudioRecording(
        id: id,
        context: context,
        fileURL: fileURL,
        handle: handle,
        createdAt: Date(),
        byteCount: 0,
        sampleRate: nil,
        pcmFrameCount: 0
      )

      if context.format == .wav {
        try handle.write(contentsOf: Data(repeating: 0, count: 44))
        recording.byteCount = 44
      }

      activeRecording = recording
      return AudioRecordingSessionSnapshot(isRecording: true, receiverName: context.receiverName, format: context.format)
    }
  }

  func stopRecording() -> AudioRecordingInfo? {
    queue.sync {
      stopRecordingLocked()
    }
  }

  func delete(_ recording: AudioRecordingInfo) {
    queue.sync {
      recordings.removeAll { $0.id == recording.id }
      try? fileManager.removeItem(at: recording.fileURL)
      persistRecordingsLocked()
    }
  }

  func consumePCM(samples: [Float], sampleRate: Double) {
    guard !samples.isEmpty else { return }

    queue.async {
      guard var recording = self.activeRecording, recording.context.format == .wav else { return }
      if recording.sampleRate == nil {
        recording.sampleRate = sampleRate
      }
      let pcmData = Self.makePCM16Data(from: samples)
      do {
        try recording.handle.seekToEnd()
        try recording.handle.write(contentsOf: pcmData)
        recording.byteCount += Int64(pcmData.count)
        recording.pcmFrameCount += UInt32(samples.count)
        self.activeRecording = recording
      } catch {
        _ = self.stopRecordingLocked()
      }
    }
  }

  func consumeMP3(data: Data) {
    guard !data.isEmpty else { return }

    queue.async {
      guard var recording = self.activeRecording, recording.context.format == .mp3 else { return }
      do {
        try recording.handle.seekToEnd()
        try recording.handle.write(contentsOf: data)
        recording.byteCount += Int64(data.count)
        self.activeRecording = recording
      } catch {
        _ = self.stopRecordingLocked()
      }
    }
  }

  private func stopRecordingLocked() -> AudioRecordingInfo? {
    guard let recording = activeRecording else { return nil }
    activeRecording = nil

    do {
      if recording.context.format == .wav {
        let sampleRate = recording.sampleRate ?? 48_000
        let payloadByteCount = Int(max(recording.byteCount - 44, 0))
        let header = Self.makeWAVHeader(
          sampleRate: sampleRate,
          totalPCMBytes: payloadByteCount
        )
        try recording.handle.seek(toOffset: 0)
        try recording.handle.write(contentsOf: header)
      }
    } catch {
      recording.handle.closeFile()
    }
    recording.handle.closeFile()

    let finishedAt = Date()
    let info = AudioRecordingInfo(
      id: recording.id,
      receiverName: recording.context.receiverName,
      backend: recording.context.backend,
      frequencyHz: recording.context.frequencyHz,
      mode: recording.context.mode,
      format: recording.context.format,
      filePath: recording.fileURL.path,
      createdAt: recording.createdAt,
      finishedAt: finishedAt,
      byteCount: max(recording.byteCount, 0)
    )

    recordings.insert(info, at: 0)
    recordings.sort { $0.createdAt > $1.createdAt }
    persistRecordingsLocked()
    return info
  }

  private func loadRecordings() {
    guard
      let data = try? Data(contentsOf: indexURL),
      let decoded = try? JSONDecoder().decode([AudioRecordingInfo].self, from: data)
    else {
      recordings = []
      return
    }

    recordings = decoded.filter { fileManager.fileExists(atPath: $0.filePath) }
    persistRecordingsLocked()
  }

  private func persistRecordingsLocked() {
    guard let data = try? JSONEncoder().encode(recordings) else { return }
    try? data.write(to: indexURL, options: [.atomic])
  }

  private func sanitizedFileComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let raw = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let output = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let text = String(output).replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
    return text.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "recording" : text
  }

  private static func makePCM16Data(from samples: [Float]) -> Data {
    var pcm = Data(capacity: samples.count * 2)
    for sample in samples {
      let clamped = max(-1.0, min(1.0, sample))
      let scaled = Int16((clamped * Float(Int16.max)).rounded())
      var littleEndian = scaled.littleEndian
      withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
    }
    return pcm
  }

  private static func makeWAVHeader(sampleRate: Double, totalPCMBytes: Int) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let safeSampleRate = UInt32(max(8_000, min(192_000, Int(sampleRate.rounded()))))
    let byteRate = safeSampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let chunkSize = UInt32(totalPCMBytes + 36)
    let dataSize = UInt32(totalPCMBytes)

    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.append(Self.littleEndianData(chunkSize))
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    data.append(Self.littleEndianData(UInt32(16)))
    data.append(Self.littleEndianData(UInt16(1)))
    data.append(Self.littleEndianData(channels))
    data.append(Self.littleEndianData(safeSampleRate))
    data.append(Self.littleEndianData(byteRate))
    data.append(Self.littleEndianData(blockAlign))
    data.append(Self.littleEndianData(bitsPerSample))
    data.append("data".data(using: .ascii)!)
    data.append(Self.littleEndianData(dataSize))
    return data
  }

  private static func littleEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
    var little = value.littleEndian
    return withUnsafeBytes(of: &little) { Data($0) }
  }

  private let recordingTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}

@MainActor
final class RecordingStore: ObservableObject {
  @Published private(set) var recordings: [AudioRecordingInfo] = []
  @Published private(set) var isRecording = false
  @Published private(set) var activeReceiverName: String?
  @Published private(set) var activeFormat: AudioRecordingFormat?

  func refresh() {
    recordings = AudioRecordingController.shared.listRecordings()
    apply(snapshot: AudioRecordingController.shared.currentSnapshot())
  }

  func startRecording(
    receiverName: String,
    backend: SDRBackend,
    frequencyHz: Int,
    mode: DemodulationMode?
  ) {
    let format: AudioRecordingFormat = backend == .fmDxWebserver ? .mp3 : .wav
    let context = AudioRecordingContext(
      receiverName: receiverName,
      backend: backend,
      frequencyHz: frequencyHz,
      mode: mode,
      format: format
    )

    if let snapshot = try? AudioRecordingController.shared.startRecording(context: context) {
      apply(snapshot: snapshot)
      refresh()
    }
  }

  func stopRecording() {
    _ = AudioRecordingController.shared.stopRecording()
    refresh()
  }

  func delete(_ recording: AudioRecordingInfo) {
    AudioRecordingController.shared.delete(recording)
    refresh()
  }

  private func apply(snapshot: AudioRecordingSessionSnapshot) {
    isRecording = snapshot.isRecording
    activeReceiverName = snapshot.receiverName
    activeFormat = snapshot.format
  }
}
