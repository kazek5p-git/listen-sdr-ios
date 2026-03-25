import Foundation

public enum ReceiverCountryResolver {
  private static let englishLocale = Locale(identifier: "en_US_POSIX")
  private static let aliasLocales: [Locale] = [
    englishLocale,
    Locale(identifier: "pl_PL"),
    Locale(identifier: "de_DE"),
    Locale(identifier: "fr_FR"),
    Locale(identifier: "es_ES"),
    Locale(identifier: "it_IT"),
  ]
  private static let regionCodes = Set(Locale.Region.isoRegions.map { $0.identifier.uppercased() })
  private static let aliasToRegionCode = buildAliasToRegionCodeMap()
  private static let aliasTokenCounts = Array(
    Set(aliasToRegionCode.keys.map { $0.split(separator: " ").count })
  ).sorted(by: >)

  public static func normalizedCountryLabel(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard let regionCode = resolvedCountryCode(fromCountryName: trimmed) else {
      return trimmed
    }

    return localizedCountryName(for: regionCode)
  }

  public static func normalizedCountryLabel(countryCode: String?, countryName: String?) -> String? {
    if let regionCode = resolvedCountryCode(countryCode: countryCode, countryName: countryName) {
      return localizedCountryName(for: regionCode)
    }

    return normalizedCountryLabel(countryName)
  }

  public static func resolvedCountryCode(countryCode: String?, countryName: String?) -> String? {
    if let regionCode = normalizedRegionCodeToken(countryCode) {
      return regionCode
    }

    return resolvedCountryCode(fromCountryName: countryName)
  }

  public static func inferredCountryLabel(locationLabel: String?, host: String) -> String? {
    guard let regionCode = resolvedCountryCode(fromMetadataLabel: locationLabel, host: host) else {
      return nil
    }

    return localizedCountryName(for: regionCode)
  }

  public static func resolvedCountryCode(fromCountryName rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let flagRegionCode = extractRegionCodeFromFlag(in: trimmed) {
      return flagRegionCode
    }

    let normalized = normalizedSearchText(trimmed)
    guard !normalized.isEmpty else { return nil }

    if let aliasMatch = aliasToRegionCode[normalized] {
      return aliasMatch
    }

    return normalizedRegionCodeToken(normalized.uppercased())
  }

  public static func resolvedCountryCode(fromMetadataLabel locationLabel: String?, host: String?) -> String? {
    if let locationLabel {
      if let flagRegionCode = extractRegionCodeFromFlag(in: locationLabel) {
        return flagRegionCode
      }

      if let directRegionCode = resolvedCountryCode(fromCountryName: locationLabel) {
        return directRegionCode
      }

      if let labelRegionCode = resolvedCountryCode(fromSearchableLabel: locationLabel) {
        return labelRegionCode
      }

      if let uppercaseTokenRegionCode = resolvedCountryCode(fromUppercaseTokens: locationLabel) {
        return uppercaseTokenRegionCode
      }
    }

    return resolvedCountryCode(fromHost: host)
  }

  private static func localizedCountryName(for regionCode: String) -> String {
    Locale.current.localizedString(forRegionCode: regionCode)
      ?? englishLocale.localizedString(forRegionCode: regionCode)
      ?? regionCode
  }

  private static func resolvedCountryCode(fromSearchableLabel label: String) -> String? {
    let tokens = normalizedSearchText(label)
      .split(separator: " ")
      .map(String.init)
    guard !tokens.isEmpty else { return nil }

    for tokenCount in aliasTokenCounts {
      guard tokenCount <= tokens.count else { continue }
      let upperBound = tokens.count - tokenCount
      for startIndex in 0...upperBound {
        let phrase = tokens[startIndex..<(startIndex + tokenCount)].joined(separator: " ")
        if let regionCode = aliasToRegionCode[phrase] {
          return regionCode
        }
      }
    }

    return nil
  }

  private static func resolvedCountryCode(fromUppercaseTokens label: String) -> String? {
    let rawTokens = label
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    for token in rawTokens.reversed() {
      guard token == token.uppercased() else { continue }

      let normalizedToken = normalizedSearchText(token)
      if let aliasMatch = aliasToRegionCode[normalizedToken] {
        return aliasMatch
      }

      if let regionCode = normalizedRegionCodeToken(token) {
        return regionCode
      }
    }

    return nil
  }

  private static func resolvedCountryCode(fromHost host: String?) -> String? {
    guard let host else { return nil }
    let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedHost.isEmpty else { return nil }

    let topLevelDomain = trimmedHost
      .split(separator: ".")
      .last?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()

    return normalizedRegionCodeToken(topLevelDomain)
  }

  private static func normalizedRegionCodeToken(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !trimmed.isEmpty else { return nil }

    if trimmed == "UK" {
      return "GB"
    }

    guard regionCodes.contains(trimmed) else { return nil }
    return trimmed
  }

  private static func extractRegionCodeFromFlag(in value: String) -> String? {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count >= 2 else { return nil }

    for index in 0..<(scalars.count - 1) {
      let first = scalars[index].value
      let second = scalars[index + 1].value
      guard
        (0x1F1E6...0x1F1FF).contains(first),
        (0x1F1E6...0x1F1FF).contains(second),
        let firstScalar = UnicodeScalar(65 + first - 0x1F1E6),
        let secondScalar = UnicodeScalar(65 + second - 0x1F1E6)
      else {
        continue
      }

      let regionCode = "\(Character(firstScalar))\(Character(secondScalar))"
      if let normalized = normalizedRegionCodeToken(regionCode) {
        return normalized
      }
    }

    return nil
  }

  private static func normalizedSearchText(_ value: String) -> String {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: englishLocale
    )

    let separated = folded.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) {
        return Character(scalar)
      }
      return " "
    }

    return String(separated)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func buildAliasToRegionCodeMap() -> [String: String] {
    var aliases: [String: String] = [:]

    for regionCode in regionCodes {
      for locale in aliasLocales {
        if let localizedName = locale.localizedString(forRegionCode: regionCode) {
          registerAlias(localizedName, for: regionCode, into: &aliases)
        }
      }
    }

    let manualAliases: [String: String] = [
      "united states of america": "US",
      "usa": "US",
      "great britain": "GB",
      "britain": "GB",
      "united kingdom": "GB",
      "uk": "GB",
      "england": "GB",
      "scotland": "GB",
      "wales": "GB",
      "northern ireland": "GB",
      "the netherlands": "NL",
      "holland": "NL",
      "czech republic": "CZ",
      "south korea": "KR",
      "republic of korea": "KR",
      "north korea": "KP",
      "dprk": "KP",
      "uae": "AE",
    ]

    for (alias, regionCode) in manualAliases {
      registerAlias(alias, for: regionCode, into: &aliases)
    }

    return aliases
  }

  private static func registerAlias(
    _ rawAlias: String,
    for regionCode: String,
    into aliases: inout [String: String]
  ) {
    let normalizedAlias = normalizedSearchText(rawAlias)
    guard !normalizedAlias.isEmpty else { return }
    aliases[normalizedAlias] = regionCode
  }
}
