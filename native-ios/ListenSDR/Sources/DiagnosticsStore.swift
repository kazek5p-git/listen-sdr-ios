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
  }

  func clear() {
    entries.removeAll()
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

  private func format(_ entry: DiagnosticLogEntry) -> String {
    "[\(Self.timestampFormatter.string(from: entry.date))] [\(entry.severity.rawValue.uppercased())] [\(entry.category)] \(entry.message)"
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
