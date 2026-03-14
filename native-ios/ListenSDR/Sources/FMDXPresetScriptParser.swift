import Foundation

enum FMDXPresetScriptParser {
  static func qualityScore(for bookmarks: [SDRServerBookmark]) -> Int {
    stationListQualityScore(bookmarks)
  }

  static func parseBookmarks(
    from script: String,
    requiresPresetMarker: Bool = false,
    source: String = "fmdx-station-list"
  ) -> [SDRServerBookmark] {
    if requiresPresetMarker && !script.lowercased().contains("defaultpresetdata") {
      return []
    }

    let defaultPresetBlocks = captures(
      for: #"(?is)defaultPresetData\s*=\s*\{([\s\S]*?)\}"#,
      in: script,
      group: 1
    )
    for block in defaultPresetBlocks {
      let parsed = parsePresetBlockBookmarks(
        block,
        source: source,
        idPrefix: "fmdx-station-default"
      )
      if !parsed.isEmpty {
        return parsed
      }
    }

    let localStorageFallbackBlocks = captures(
      for: #"(?is)localStorage\.getItem\([\s\S]*?\)\s*\)\s*\|\|\s*\{([\s\S]*?)\}"#,
      in: script,
      group: 1
    )
    var bestFallback: [SDRServerBookmark] = []
    var bestScore = Int.min
    for block in localStorageFallbackBlocks {
      let parsed = parsePresetBlockBookmarks(
        block,
        source: source,
        idPrefix: "fmdx-station-fallback"
      )
      guard !parsed.isEmpty else { continue }

      let score = stationListQualityScore(parsed)
      if score > bestScore {
        bestFallback = parsed
        bestScore = score
      }
    }

    return bestFallback
  }

  private static func parsePresetBlockBookmarks(
    _ block: String,
    source: String,
    idPrefix: String
  ) -> [SDRServerBookmark] {
    guard
      let valuesRaw = captures(
        for: #"(?is)values\s*:\s*\[([\s\S]*?)\]"#,
        in: block,
        group: 1
      ).first
    else {
      return []
    }

    let valuesMHz = captures(for: #"-?\d+(?:\.\d+)?"#, in: valuesRaw, group: 0).compactMap { Double($0) }
    let labels = parseStationLabels(from: block)
    return buildStationBookmarks(valuesMHz: valuesMHz, labels: labels, source: source, idPrefix: idPrefix)
  }

  private static func parseStationLabels(from block: String) -> [String] {
    let tooltips = parseArray(forKey: "tooltips", from: block)
    let ps = parseArray(forKey: "ps", from: block)
    let names = parseArray(forKey: "names", from: block)
    let labels = parseArray(forKey: "labels", from: block)
    let maxCount = [tooltips.count, ps.count, names.count, labels.count].max() ?? 0
    guard maxCount > 0 else { return [] }

    return (0..<maxCount).map { index in
      let candidates = [
        value(at: index, in: tooltips),
        value(at: index, in: ps),
        value(at: index, in: names),
        value(at: index, in: labels)
      ]
      for candidate in candidates {
        if !candidate.isEmpty {
          return candidate
        }
      }
      return ""
    }
  }

  private static func parseArray(forKey key: String, from block: String) -> [String] {
    guard let raw = captures(
      for: #"(?is)\#(key)\s*:\s*\[([\s\S]*?)\]"#,
      in: block,
      group: 1
    ).first else {
      return []
    }
    return parseQuotedStringArray(from: raw)
  }

  private static func value(at index: Int, in array: [String]) -> String {
    guard index < array.count else { return "" }
    return decodeHTMLEntities(array[index]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func buildStationBookmarks(
    valuesMHz: [Double],
    labels: [String],
    source: String,
    idPrefix: String
  ) -> [SDRServerBookmark] {
    var bookmarks: [SDRServerBookmark] = []
    var seen = Set<Int>()
    bookmarks.reserveCapacity(valuesMHz.count)

    for (index, valueMHz) in valuesMHz.enumerated() {
      guard valueMHz.isFinite, valueMHz > 0 else { continue }
      let frequencyHz = normalizePresetFrequencyHz(fromMHz: valueMHz)
      guard seen.insert(frequencyHz).inserted else { continue }

      let fallbackName = FrequencyFormatter.fmDxMHzText(fromHz: frequencyHz)
      let resolvedName = index < labels.count && !labels[index].isEmpty ? labels[index] : fallbackName

      bookmarks.append(
        SDRServerBookmark(
          id: "\(idPrefix)-\(index + 1)-\(frequencyHz)",
          name: resolvedName,
          frequencyHz: frequencyHz,
          modulation: .fm,
          source: source
        )
      )
    }

    guard bookmarks.count >= 3 else { return [] }
    return bookmarks.sorted { $0.frequencyHz < $1.frequencyHz }
  }

  private static func stationListQualityScore(_ bookmarks: [SDRServerBookmark]) -> Int {
    let namedCount = bookmarks.reduce(into: 0) { result, bookmark in
      if !looksLikeFrequencyLabel(bookmark.name) {
        result += 1
      }
    }
    return (bookmarks.count * 10) + (namedCount * 25)
  }

  private static func looksLikeFrequencyLabel(_ text: String) -> Bool {
    let normalized = text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: ",", with: ".")

    if normalized.contains("mhz") {
      return true
    }
    if Double(normalized) != nil {
      return true
    }
    return normalized.range(of: #"^\d{2,3}(?:\.\d{1,3})?$"#, options: .regularExpression) != nil
  }

  private static func parseQuotedStringArray(from raw: String) -> [String] {
    var output: [String] = []
    output.reserveCapacity(16)

    var buffer = ""
    var activeQuote: Character?
    var isEscaped = false

    func flushBuffer() {
      output.append(buffer)
      buffer.removeAll(keepingCapacity: true)
    }

    for character in raw {
      if let quote = activeQuote {
        if isEscaped {
          switch character {
          case "n":
            buffer.append("\n")
          case "r":
            buffer.append("\r")
          case "t":
            buffer.append("\t")
          default:
            buffer.append(character)
          }
          isEscaped = false
          continue
        }

        if character == "\\" {
          isEscaped = true
          continue
        }

        if character == quote {
          flushBuffer()
          activeQuote = nil
          continue
        }

        buffer.append(character)
      } else if character == "'" || character == "\"" {
        activeQuote = character
      }
    }

    return output
  }

  private static func normalizePresetFrequencyHz(fromMHz value: Double) -> Int {
    let hzValue = value >= 1_000 ? value * 1_000 : value * 1_000_000.0
    return Int((hzValue / 1_000.0).rounded() * 1_000.0)
  }

  private static func captures(for pattern: String, in text: String, group: Int) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, options: [], range: range).compactMap { match in
      guard group < match.numberOfRanges else { return nil }
      let captureRange = match.range(at: group)
      guard let swiftRange = Range(captureRange, in: text) else { return nil }
      return String(text[swiftRange])
    }
  }

  private static func decodeHTMLEntities(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    let data = Data(text.utf8)
    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
      .documentType: NSAttributedString.DocumentType.html,
      .characterEncoding: String.Encoding.utf8.rawValue
    ]
    if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
      return attributed.string
    }
    return text
  }
}
