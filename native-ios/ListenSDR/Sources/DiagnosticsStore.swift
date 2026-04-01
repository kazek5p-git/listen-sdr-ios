import Foundation
import Combine
import OSLog

enum DiagnosticSeverity: String {
  case info
  case warning
  case error
}

struct DiagnosticLogEntry: Identifiable, Equatable {
  let id: UUID
  let date: Date
  let severity: DiagnosticSeverity
  let category: String
  let message: String
}

@MainActor
final class DiagnosticsStore: ObservableObject {
  @Published private(set) var entries: [DiagnosticLogEntry] = []

  private let maxEntries = 500
  private let fileManager = FileManager.default
  private let storageDirectoryURL: URL
  private let currentLogURL: URL
  private let previousLogURL: URL

  init() {
    let baseDirectory =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let storageDirectoryURL = baseDirectory.appendingPathComponent("ListenSDRDiagnostics", isDirectory: true)
    self.storageDirectoryURL = storageDirectoryURL
    currentLogURL = storageDirectoryURL.appendingPathComponent("current.log")
    previousLogURL = storageDirectoryURL.appendingPathComponent("previous.log")
    preparePersistentStorage()
  }

  func log(
    severity: DiagnosticSeverity = .info,
    category: String,
    message: String
  ) {
    let entry = DiagnosticLogEntry(
      id: UUID(),
      date: Date(),
      severity: severity,
      category: category,
      message: message
    )
    entries.append(entry)
    if entries.count > maxEntries {
      entries.removeFirst(entries.count - maxEntries)
    }
    appendToCurrentLog(format(entry))
  }

  func clear() {
    entries.removeAll()
    try? "".write(to: currentLogURL, atomically: true, encoding: .utf8)
    try? fileManager.removeItem(at: previousLogURL)
  }

  func exportText() -> String {
    guard !entries.isEmpty else {
      return "Listen SDR diagnostics: no entries."
    }

    let lines = entries.map { entry in
      format(entry)
    }
    return lines.joined(separator: "\n")
  }

  func exportPreviousSessionText() -> String? {
    let text = try? String(contentsOf: previousLogURL, encoding: .utf8)
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
  }

  func exportCombinedText() -> String {
    let currentText = exportText()
    guard let previousText = exportPreviousSessionText(), !previousText.isEmpty else {
      return currentText
    }
    return """
    [Current session logs]
    \(currentText)

    [Previous session logs]
    \(previousText)
    """
  }

  func exportAudioExcerpt(limit: Int = 28) -> String? {
    guard limit > 0 else { return nil }

    let filteredEntries = entries.filter { entry in
      if entry.severity != .info {
        return true
      }

      let category = entry.category.lowercased()
      let message = entry.message.lowercased()

      if category.contains("audio") {
        return true
      }
      if category == "session" {
        return message.contains("reconnect")
          || message.contains("sync timed out")
          || message.contains("tuning fallback")
          || message.contains("disconnect")
      }
      if category.contains("kiwi") || category.contains("openwebrx") || category.contains("fm-dx") {
        return message.contains("audio")
          || message.contains("buffer")
          || message.contains("queue")
          || message.contains("latency")
          || message.contains("trim")
          || message.contains("busy")
      }
      return message.contains("audio")
        || message.contains("buffer")
        || message.contains("enqueue")
        || message.contains("queue")
        || message.contains("latency")
        || message.contains("trim")
    }

    guard !filteredEntries.isEmpty else { return nil }
    return filteredEntries
      .suffix(limit)
      .map(format)
      .joined(separator: "\n")
  }

  func exportPreviousSessionAudioExcerpt(limit: Int = 28) -> String? {
    guard
      limit > 0,
      let previousText = exportPreviousSessionText()
    else { return nil }

    let filteredLines = previousText
      .split(separator: "\n")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { line in
        let normalized = line.lowercased()
        return normalized.contains("audio")
          || normalized.contains("buffer")
          || normalized.contains("enqueue")
          || normalized.contains("queue")
          || normalized.contains("latency")
          || normalized.contains("trim")
          || normalized.contains("gap")
          || normalized.contains("reconnect")
          || normalized.contains("disconnect")
      }

    guard !filteredLines.isEmpty else { return nil }
    return filteredLines.suffix(limit).joined(separator: "\n")
  }

  func exportCombinedAudioExcerpt(limit: Int = 28) -> String? {
    var parts: [String] = []
    if let currentExcerpt = exportAudioExcerpt(limit: limit), !currentExcerpt.isEmpty {
      parts.append("[Current session audio log tail]\n\(currentExcerpt)")
    }
    if let previousExcerpt = exportPreviousSessionAudioExcerpt(limit: limit), !previousExcerpt.isEmpty {
      parts.append("[Previous session audio log tail]\n\(previousExcerpt)")
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
  }

  private func format(_ entry: DiagnosticLogEntry) -> String {
    "[\(Self.timestampFormatter.string(from: entry.date))] [\(entry.severity.rawValue.uppercased())] [\(entry.category)] \(entry.message)"
  }

  private func preparePersistentStorage() {
    try? fileManager.createDirectory(
      at: storageDirectoryURL,
      withIntermediateDirectories: true
    )

    if fileManager.fileExists(atPath: currentLogURL.path) {
      try? fileManager.removeItem(at: previousLogURL)
      if (try? fileManager.attributesOfItem(atPath: currentLogURL.path)[.size] as? NSNumber)?.intValue ?? 0 > 0 {
        try? fileManager.copyItem(at: currentLogURL, to: previousLogURL)
      }
    }

    try? "".write(to: currentLogURL, atomically: true, encoding: .utf8)
  }

  private func appendToCurrentLog(_ line: String) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if !fileManager.fileExists(atPath: currentLogURL.path) {
      try? fileManager.createDirectory(
        at: storageDirectoryURL,
        withIntermediateDirectories: true
      )
      fileManager.createFile(atPath: currentLogURL.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: currentLogURL) else { return }
    defer { try? handle.close() }
    try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
  }

  private static let timestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

enum Diagnostics {
  @MainActor static let sharedStore = DiagnosticsStore()
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "ListenSDR",
    category: "Diagnostics"
  )

  static func log(
    severity: DiagnosticSeverity = .info,
    category: String,
    message: String
  ) {
    let line = "[\(category)] \(message)"
    switch severity {
    case .info:
      logger.info("\(line, privacy: .public)")
    case .warning:
      logger.notice("\(line, privacy: .public)")
    case .error:
      logger.error("\(line, privacy: .public)")
    }

    Task { @MainActor in
      sharedStore.log(
        severity: severity,
        category: category,
        message: message
      )
    }
  }
}
