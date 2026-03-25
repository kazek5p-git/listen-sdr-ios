import Foundation

public enum ReceiverDirectorySearchCore {
  public static func normalizedSearchText(_ value: String) -> String {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )

    return folded
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  public static func searchableText(fields: [String?]) -> String {
    normalizedSearchText(
      fields
        .compactMap { $0 }
        .joined(separator: " ")
    )
  }

  public static func matchesSearch(query: String, searchableText: String) -> Bool {
    let normalizedQuery = normalizedSearchText(query)
    guard !normalizedQuery.isEmpty else { return true }

    let normalizedSearchableText = normalizedSearchText(searchableText)
    if normalizedSearchableText.contains(normalizedQuery) {
      return true
    }

    let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
    guard queryTokens.count > 1 else { return false }
    return queryTokens.allSatisfy { normalizedSearchableText.contains($0) }
  }
}
