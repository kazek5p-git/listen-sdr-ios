import Foundation

enum FrequencyInputParser {
  enum Context {
    case generic
    case fmBroadcast
    case shortwave
  }

  static func parseHz(from text: String, context: Context = .generic) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let normalized = trimmed
      .lowercased()
      .replacingOccurrences(of: ",", with: ".")
      .replacingOccurrences(of: " ", with: "")

    let explicit = parseExplicitUnit(normalized)
    let unit: Double
    let numberPart: String

    if let explicit {
      unit = explicit.unit
      numberPart = explicit.numberPart
    } else {
      numberPart = normalized
      unit = inferredUnit(for: numberPart, context: context)
    }

    guard let number = Double(numberPart), number.isFinite, number >= 0 else { return nil }
    let hz = Int((number * unit).rounded())
    return hz > 0 ? hz : nil
  }

  private static func parseExplicitUnit(_ value: String) -> (numberPart: String, unit: Double)? {
    if value.hasSuffix("mhz") {
      return (String(value.dropLast(3)), 1_000_000)
    }
    if value.hasSuffix("m") {
      return (String(value.dropLast(1)), 1_000_000)
    }
    if value.hasSuffix("khz") {
      return (String(value.dropLast(3)), 1_000)
    }
    if value.hasSuffix("k") {
      return (String(value.dropLast(1)), 1_000)
    }
    if value.hasSuffix("hz") {
      return (String(value.dropLast(2)), 1)
    }
    return nil
  }

  private static func inferredUnit(for numberPart: String, context: Context) -> Double {
    if numberPart.contains(".") {
      return 1_000_000
    }

    guard let integerValue = Int(numberPart), integerValue > 0 else {
      return 1
    }

    switch context {
    case .generic:
      return integerValue < 100_000 ? 1_000 : 1

    case .fmBroadcast:
      // FM-friendly shortcuts:
      // 1023  -> 102.3 MHz
      // 10230 -> 102.30 MHz
      // 102300 -> 102300 kHz
      if (64...110).contains(integerValue) {
        return 1_000_000
      }
      if (640...1100).contains(integerValue) {
        return 100_000
      }
      if (6400...11_000).contains(integerValue) {
        return 10_000
      }
      if (64_000...110_000).contains(integerValue) {
        return 1_000
      }
      if (64_000_000...110_000_000).contains(integerValue) {
        return 1
      }
      return integerValue < 100_000 ? 1_000 : 1

    case .shortwave:
      // HF-friendly shortcuts:
      // 7050   -> 7050 kHz
      // 7050000 -> 7050000 Hz
      // 7.050  -> 7.050 MHz
      if (1...99_999).contains(integerValue) {
        return 1_000
      }
      return 1
    }
  }
}
