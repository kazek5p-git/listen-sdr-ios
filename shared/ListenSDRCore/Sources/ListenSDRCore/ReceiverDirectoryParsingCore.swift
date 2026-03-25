import Foundation

public struct ReceiverDirectoryEndpoint: Equatable, Sendable {
  public let host: String
  public let port: Int
  public let path: String
  public let useTLS: Bool
  public let absoluteURL: String

  public init(
    host: String,
    port: Int,
    path: String,
    useTLS: Bool,
    absoluteURL: String
  ) {
    self.host = host
    self.port = port
    self.path = path
    self.useTLS = useTLS
    self.absoluteURL = absoluteURL
  }
}

public enum SharedReceiverDirectoryStatus: String, Codable, Sendable {
  case available
  case limited
  case unreachable
  case unknown
}

public enum ReceiverDirectoryParsingCoreErrorCode: String, Equatable, Sendable {
  case unsupportedReceiverbookFormat
}

public struct ReceiverDirectoryParsingCoreError: LocalizedError, Equatable, Sendable {
  public let code: ReceiverDirectoryParsingCoreErrorCode

  public init(_ code: ReceiverDirectoryParsingCoreErrorCode) {
    self.code = code
  }

  public var errorDescription: String? {
    switch code {
    case .unsupportedReceiverbookFormat:
      return "Receiverbook map format changed and cannot be parsed."
    }
  }
}

public enum ReceiverDirectoryParsingCore {
  private static let receiverbookAssignmentPatterns: [NSRegularExpression] = [
    try! NSRegularExpression(pattern: #"\b(?:var|let|const)\s+receivers\s*=\s*"#),
    try! NSRegularExpression(pattern: #"\bwindow\.receivers\s*=\s*"#),
    try! NSRegularExpression(pattern: #"\bglobalThis\.receivers\s*=\s*"#),
  ]

  private static let receiverbookJSONScriptRegex = try! NSRegularExpression(
    pattern: #"<script[^>]*type=["']application/json["'][^>]*>(.*?)</script>"#,
    options: [.dotMatchesLineSeparators, .caseInsensitive]
  )

  public static func extractReceiverbookJSON(from html: String) throws -> String {
    if let extracted = extractReceiverbookJSONFromAssignments(html) {
      return extracted
    }

    if let extracted = extractReceiverbookJSONFromAddReceiversCall(html) {
      return extracted
    }

    if let extracted = extractReceiverbookJSONFromScriptTag(html) {
      return extracted
    }

    throw ReceiverDirectoryParsingCoreError(.unsupportedReceiverbookFormat)
  }

  public static func parseEndpoint(from rawValue: String?) -> ReceiverDirectoryEndpoint? {
    var candidate = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !candidate.isEmpty else {
      return nil
    }

    candidate = candidate.replacingOccurrences(of: " ", with: "%20")

    guard let normalizedURL = try? ReceiverLinkImportCore.normalizeInspectableURL(
      ReceiverLinkImportCore.normalizedURL(candidate)
    ) else {
      return nil
    }

    let host = normalizedURL.host.lowercased()
    let port = normalizedURL.port >= 0
      ? normalizedURL.port
      : (normalizedURL.scheme == "https" ? 443 : 80)
    let path = normalizedURL.normalizedPath

    let normalized = ReceiverImportURL(
      scheme: normalizedURL.scheme,
      userInfo: normalizedURL.userInfo,
      host: host,
      port: port,
      path: path
    )

    return ReceiverDirectoryEndpoint(
      host: host,
      port: port,
      path: path,
      useTLS: normalized.scheme == "https",
      absoluteURL: normalized.asString()
    )
  }

  public static func fmdxStatus(from rawValue: Int?) -> SharedReceiverDirectoryStatus {
    switch rawValue {
    case 1:
      return .available
    case 2:
      return .limited
    case 0:
      return .unreachable
    default:
      return .unknown
    }
  }

  public static func matchesReceiverbookType(_ value: String, backend: SDRBackend) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    switch backend {
    case .kiwiSDR:
      return normalized.contains("kiwi")
    case .openWebRX:
      return normalized.contains("openwebrx")
    case .fmDxWebserver:
      return false
    }
  }

  public static func mapProbeStatus(from statusCode: Int) -> SharedReceiverDirectoryStatus {
    switch statusCode {
    case 200...399:
      return .available
    case 401, 403, 423, 429:
      return .limited
    case 400...599:
      return .unreachable
    default:
      return .unknown
    }
  }

  private static func extractReceiverbookJSONFromAssignments(_ html: String) -> String? {
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

    for pattern in receiverbookAssignmentPatterns {
      guard let match = pattern.firstMatch(in: html, options: [], range: nsRange) else {
        continue
      }

      let startOffset = match.range.location + match.range.length
      if let extracted = extractLeadingJSONArray(from: html, startingAtUTF16Offset: startOffset) {
        return extracted
      }
    }

    return nil
  }

  private static func extractReceiverbookJSONFromAddReceiversCall(_ html: String) -> String? {
    let marker = ".addReceivers("
    guard let markerRange = html.range(of: marker) else {
      return nil
    }

    guard let utf16UpperBound = markerRange.upperBound.samePosition(in: html.utf16) else {
      return nil
    }

    let startOffset = html.utf16.distance(from: html.utf16.startIndex, to: utf16UpperBound)
    return extractLeadingJSONArray(from: html, startingAtUTF16Offset: startOffset)
  }

  private static func extractReceiverbookJSONFromScriptTag(_ html: String) -> String? {
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

    return receiverbookJSONScriptRegex
      .matches(in: html, options: [], range: nsRange)
      .compactMap { match -> String? in
        guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) else {
          return nil
        }

        let candidate = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.hasPrefix("[") ? candidate : nil
      }
      .first
  }

  private static func extractLeadingJSONArray(
    from value: String,
    startingAtUTF16Offset startUTF16Offset: Int
  ) -> String? {
    guard startUTF16Offset <= value.utf16.count else {
      return nil
    }

    var index = String.Index(utf16Offset: startUTF16Offset, in: value)
    while index < value.endIndex && value[index].isWhitespace {
      index = value.index(after: index)
    }

    guard index < value.endIndex, value[index] == "[" else {
      return nil
    }

    var depth = 0
    var inString = false
    var stringDelimiter: Character?
    var escaped = false
    var cursor = index

    while cursor < value.endIndex {
      let character = value[cursor]

      if inString {
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == stringDelimiter {
          inString = false
          stringDelimiter = nil
        }
      } else {
        switch character {
        case "\"", "'":
          inString = true
          stringDelimiter = character
        case "[":
          depth += 1
        case "]":
          depth -= 1
          if depth == 0 {
            return String(value[index...cursor])
          }
        default:
          break
        }
      }

      cursor = value.index(after: cursor)
    }

    return nil
  }
}
