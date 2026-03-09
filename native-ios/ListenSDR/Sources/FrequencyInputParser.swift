import Foundation

enum FrequencyInputParser {
  enum Context {
    case generic
    case fmBroadcast
    case shortwave
  }

  static func parseHz(
    from text: String,
    context: Context = .generic,
    preferredRangeHz: ClosedRange<Int>? = nil
  ) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let normalizedRaw = trimmed
      .lowercased()
      .replacingOccurrences(of: ",", with: ".")
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "_", with: "")

    let normalized = normalizedNumericSeparators(in: normalizedRaw)
    guard !normalized.isEmpty else { return nil }

    let explicit = parseExplicitUnit(normalized)
    let unit: Double
    let numberPart: String

    if let explicit {
      unit = explicit.unit
      numberPart = explicit.numberPart
    } else {
      numberPart = normalized
      unit = inferredUnit(for: numberPart, context: context, preferredRangeHz: preferredRangeHz)
    }

    guard let number = Double(numberPart), number.isFinite, number >= 0 else { return nil }
    let hz = Int((number * unit).rounded())
    return hz > 0 ? hz : nil
  }

  private static func normalizedNumericSeparators(in value: String) -> String {
    var result = ""
    result.reserveCapacity(value.count)
    var seenDot = false

    for scalar in value.unicodeScalars {
      if CharacterSet.decimalDigits.contains(scalar) {
        result.unicodeScalars.append(scalar)
        continue
      }
      if scalar == "." {
        if !seenDot {
          result.unicodeScalars.append(scalar)
          seenDot = true
        }
        continue
      }
      if CharacterSet.letters.contains(scalar) {
        result.unicodeScalars.append(scalar)
      }
    }

    return result
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

  private static func inferredUnit(
    for numberPart: String,
    context: Context,
    preferredRangeHz: ClosedRange<Int>?
  ) -> Double {
    if numberPart.contains(".") {
      return 1_000_000
    }

    guard let integerValue = Int(numberPart), integerValue > 0 else {
      return 1
    }

    if let preferredRangeHz,
      let rangedUnit = inferredUnit(forIntegerValue: integerValue, preferredRangeHz: preferredRangeHz) {
      return rangedUnit
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

  private static func inferredUnit(
    forIntegerValue integerValue: Int,
    preferredRangeHz: ClosedRange<Int>
  ) -> Double? {
    let candidateUnits: [Int64] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000]
    let lowerBound = Int64(preferredRangeHz.lowerBound)
    let upperBound = Int64(preferredRangeHz.upperBound)
    let centerHz = lowerBound + ((upperBound - lowerBound) / 2)
    let integerValue64 = Int64(integerValue)

    let matches = candidateUnits.compactMap { unit -> (unit: Int64, distance: Int64)? in
      let hz = integerValue64 * unit
      guard hz >= lowerBound, hz <= upperBound else {
        return nil
      }
      return (unit, abs(hz - centerHz))
    }

    guard let bestMatch = matches.min(by: { lhs, rhs in
      if lhs.distance == rhs.distance {
        return lhs.unit < rhs.unit
      }
      return lhs.distance < rhs.distance
    }) else {
      return nil
    }

    return Double(bestMatch.unit)
  }
}
