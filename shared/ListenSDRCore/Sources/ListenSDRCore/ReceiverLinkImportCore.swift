import Foundation

public struct ReceiverImportURL: Equatable {
  public let scheme: String
  public let userInfo: String?
  public let host: String
  public let port: Int
  public let path: String

  public init(
    scheme: String,
    userInfo: String? = nil,
    host: String,
    port: Int = -1,
    path: String = "/"
  ) {
    self.scheme = scheme
    self.userInfo = userInfo
    self.host = host
    self.port = port
    self.path = path
  }

  public var normalizedPath: String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "/"
    }
    return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
  }

  public func asString() -> String {
    var result = "\(scheme)://"
    if let userInfo, !userInfo.isEmpty {
      result += "\(userInfo)@"
    }

    if host.contains(":") && !host.hasPrefix("[") && !host.hasSuffix("]") {
      result += "[\(host)]"
    } else {
      result += host
    }

    if port >= 0 {
      result += ":\(port)"
    }

    result += normalizedPath
    return result
  }
}

public enum ReceiverImportBackend: Equatable {
  case kiwiSDR
  case openWebRX
  case fmDxWebserver
}

public enum ReceiverLinkImportCoreErrorCode: String, Equatable, Sendable {
  case emptyInput
  case invalidURL
  case missingHost
  case couldNotDetectReceiver
}

public struct ReceiverLinkImportCoreError: Error, Equatable, Sendable {
  public let code: ReceiverLinkImportCoreErrorCode

  public init(_ code: ReceiverLinkImportCoreErrorCode) {
    self.code = code
  }
}

public enum ReceiverLinkImportCore {
  private static let absoluteURLPattern = try! NSRegularExpression(
    pattern: #"(?is)^([a-z][a-z0-9+.\-]*)://([^/?#]*)([^?#]*)?(?:\?[^#]*)?(?:#.*)?$"#
  )

  public static func normalizedURL(_ rawInput: String) throws -> ReceiverImportURL {
    let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ReceiverLinkImportCoreError(.emptyInput)
    }

    let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
    guard let match = extractURLMatch(from: withScheme) else {
      throw ReceiverLinkImportCoreError(.invalidURL)
    }

    let scheme = match.scheme.lowercased()
    guard scheme == "http" || scheme == "https" else {
      throw ReceiverLinkImportCoreError(.invalidURL)
    }

    let authority = try parseAuthority(match.authority)
    return ReceiverImportURL(
      scheme: scheme,
      userInfo: authority.userInfo,
      host: authority.host,
      port: authority.port,
      path: match.path.isEmpty ? "/" : match.path
    )
  }

  public static func normalizeInspectableURL(_ url: ReceiverImportURL) -> ReceiverImportURL {
    ReceiverImportURL(
      scheme: url.scheme,
      userInfo: url.userInfo,
      host: url.host,
      port: url.port,
      path: url.normalizedPath
    )
  }

  public static func detectBackend(urlPath: String, html: String) throws -> ReceiverImportBackend {
    let lowered = html.lowercased()
    let path = urlPath.lowercased()

    if lowered.contains("kiwisdr.min.css")
      || lowered.contains("kiwisdr.min.js")
      || lowered.contains("id-kiwi-body")
      || lowered.contains("kiwi-with-headphones") {
      return .kiwiSDR
    }

    if lowered.contains("openwebrx")
      || lowered.contains("/ws/")
      || lowered.contains("openwebrx+") {
      return .openWebRX
    }

    if lowered.contains("fm-dx")
      || lowered.contains("fmdx")
      || lowered.contains("buttonpresets")
      || path.hasSuffix("/text")
      || path.hasSuffix("/audio") {
      return .fmDxWebserver
    }

    throw ReceiverLinkImportCoreError(.couldNotDetectReceiver)
  }

  public static func normalizedProfilePath(for backend: ReceiverImportBackend, rawPath: String) -> String {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = trimmed.lowercased()

    switch backend {
    case .kiwiSDR:
      return "/"

    case .openWebRX:
      if lowered.hasSuffix("/ws") || lowered.hasSuffix("/ws/") {
        return "/"
      }
      return normalizedPath(trimmed)

    case .fmDxWebserver:
      if lowered.hasSuffix("/text") || lowered.hasSuffix("/audio") {
        let parts = trimmed.split(separator: "/").filter { !$0.isEmpty }.dropLast()
        if parts.isEmpty {
          return "/"
        }
        return "/" + parts.joined(separator: "/")
      }
      return normalizedPath(trimmed)
    }
  }

  public static func extractHTMLTitle(from html: String) -> String? {
    let regex = try! NSRegularExpression(pattern: "(?is)<title[^>]*>(.*?)</title>")
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    guard let match = regex.firstMatch(in: html, options: [], range: range),
      let titleRange = Range(match.range(at: 1), in: html) else {
      return nil
    }

    let title = html[titleRange]
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return title.isEmpty ? nil : title
  }

  public static func preferredHTMLTitle(from html: String) -> String? {
    guard let title = extractHTMLTitle(from: html), isMeaningfulHTMLTitle(title) else {
      return nil
    }
    return title
  }

  public static func fallbackDisplayName(host: String?) -> String {
    if let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return host
    }
    return "Receiver"
  }

  private static func normalizedPath(_ rawPath: String) -> String {
    if rawPath.isEmpty {
      return "/"
    }
    return rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
  }

  private static func isMeaningfulHTMLTitle(_ title: String) -> Bool {
    !title.localizedCaseInsensitiveContains("kiwisdr")
      && !title.localizedCaseInsensitiveContains("openwebrx")
      && !title.localizedCaseInsensitiveContains("fm-dx")
  }

  private static func extractURLMatch(from value: String) -> (scheme: String, authority: String, path: String)? {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = absoluteURLPattern.firstMatch(in: value, options: [], range: range),
      let schemeRange = Range(match.range(at: 1), in: value),
      let authorityRange = Range(match.range(at: 2), in: value) else {
      return nil
    }

    let pathRange = Range(match.range(at: 3), in: value)
    return (
      scheme: String(value[schemeRange]),
      authority: String(value[authorityRange]),
      path: pathRange.map { String(value[$0]) } ?? ""
    )
  }

  private static func parseAuthority(_ authority: String) throws -> ParsedAuthority {
    guard !authority.isEmpty else {
      throw ReceiverLinkImportCoreError(.missingHost)
    }

    let userInfoSeparator = authority.lastIndex(of: "@")
    let userInfo = userInfoSeparator.map { String(authority[..<$0]) }
    let hostPort = userInfoSeparator.map { String(authority[authority.index(after: $0)...]) } ?? authority

    guard !hostPort.isEmpty else {
      throw ReceiverLinkImportCoreError(.missingHost)
    }

    if hostPort.hasPrefix("[") {
      guard let closingBracketIndex = hostPort.firstIndex(of: "]"),
        closingBracketIndex > hostPort.index(after: hostPort.startIndex) else {
        throw ReceiverLinkImportCoreError(.invalidURL)
      }

      let host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<closingBracketIndex])
      let remainder = String(hostPort[hostPort.index(after: closingBracketIndex)...])
      let port: Int

      if remainder.isEmpty {
        port = -1
      } else if remainder.hasPrefix(":") {
        port = try parsePort(String(remainder.dropFirst()))
      } else {
        throw ReceiverLinkImportCoreError(.invalidURL)
      }

      return ParsedAuthority(userInfo: userInfo, host: host, port: port)
    }

    let firstColon = hostPort.firstIndex(of: ":")
    let lastColon = hostPort.lastIndex(of: ":")
    let hasSinglePortSeparator = firstColon != nil && firstColon == lastColon
    let host = hasSinglePortSeparator ? String(hostPort[..<lastColon!]) : hostPort

    guard !host.isEmpty else {
      throw ReceiverLinkImportCoreError(.missingHost)
    }

    let port = hasSinglePortSeparator ? try parsePort(String(hostPort[hostPort.index(after: lastColon!)...])) : -1
    return ParsedAuthority(userInfo: userInfo, host: host, port: port)
  }

  private static func parsePort(_ rawPort: String) throws -> Int {
    guard !rawPort.isEmpty, let parsed = Int(rawPort), (1...65_535).contains(parsed) else {
      throw ReceiverLinkImportCoreError(.invalidURL)
    }
    return parsed
  }

  private struct ParsedAuthority {
    let userInfo: String?
    let host: String
    let port: Int
  }
}
