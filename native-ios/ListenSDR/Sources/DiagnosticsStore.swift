import Foundation
import Combine

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

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let lines = entries.map { entry in
      let timestamp = formatter.string(from: entry.date)
      return "[\(timestamp)] [\(entry.severity.rawValue.uppercased())] [\(entry.category)] \(entry.message)"
    }
    return lines.joined(separator: "\n")
  }
}

enum Diagnostics {
  @MainActor static let sharedStore = DiagnosticsStore()

  static func log(
    severity: DiagnosticSeverity = .info,
    category: String,
    message: String
  ) {
    Task { @MainActor in
      sharedStore.log(
        severity: severity,
        category: category,
        message: message
      )
    }
  }
}
