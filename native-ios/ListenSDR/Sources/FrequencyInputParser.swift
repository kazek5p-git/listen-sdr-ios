import Foundation

enum FrequencyInputParser {
  static func parseHz(from text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let normalized = trimmed
      .lowercased()
      .replacingOccurrences(of: ",", with: ".")
      .replacingOccurrences(of: " ", with: "")

    let unit: Double
    let numberPart: String

    if normalized.hasSuffix("mhz") {
      unit = 1_000_000
      numberPart = String(normalized.dropLast(3))
    } else if normalized.hasSuffix("m") {
      unit = 1_000_000
      numberPart = String(normalized.dropLast(1))
    } else if normalized.hasSuffix("khz") {
      unit = 1_000
      numberPart = String(normalized.dropLast(3))
    } else if normalized.hasSuffix("k") {
      unit = 1_000
      numberPart = String(normalized.dropLast(1))
    } else if normalized.hasSuffix("hz") {
      unit = 1
      numberPart = String(normalized.dropLast(2))
    } else {
      numberPart = normalized
      if numberPart.contains(".") {
        unit = 1_000_000
      } else if let integerValue = Int(numberPart), integerValue < 100_000 {
        unit = 1_000
      } else {
        unit = 1
      }
    }

    guard let number = Double(numberPart), number.isFinite, number >= 0 else { return nil }
    let hz = Int((number * unit).rounded())
    return hz > 0 ? hz : nil
  }
}
