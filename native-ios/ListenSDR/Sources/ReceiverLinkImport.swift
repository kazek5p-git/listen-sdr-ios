import Foundation

struct ReceiverLinkImportCandidate: Equatable {
  let sourceURL: URL
  let profile: SDRConnectionProfile
  let detectionSummary: String?
}

enum ReceiverLinkImportError: LocalizedError {
  case emptyInput
  case invalidURL
  case missingHost
  case unsupportedURL
  case couldNotDetectReceiver

  var errorDescription: String? {
    switch self {
    case .emptyInput:
      return L10n.text("receiver.import.error.empty")
    case .invalidURL:
      return L10n.text("receiver.import.error.invalid_url")
    case .missingHost:
      return L10n.text("receiver.import.error.missing_host")
    case .unsupportedURL:
      return L10n.text("receiver.import.error.unsupported")
    case .couldNotDetectReceiver:
      return L10n.text("receiver.import.error.unrecognized")
    }
  }
}

enum ReceiverLinkImportDetector {
  static func analyze(_ rawInput: String) async throws -> ReceiverLinkImportCandidate {
    let url = try normalizedURL(from: rawInput)
    let initialURL = normalizeInspectableURL(url)
    let page = try await fetchPage(from: initialURL)
    let inspectedURL = normalizeInspectableURL(page.finalURL)
    let backend = try detectBackend(from: inspectedURL, html: page.body)
    let normalizedPath = normalizedProfilePath(for: backend, rawPath: inspectedURL.path)
    let displayName = await suggestedName(for: inspectedURL, backend: backend, html: page.body)
    let useTLS = inspectedURL.scheme?.lowercased() == "https"
    let profile = SDRConnectionProfile(
      name: displayName,
      backend: backend,
      host: inspectedURL.host() ?? "",
      port: inspectedURL.port ?? backend.defaultPort(useTLS: useTLS),
      useTLS: useTLS,
      path: normalizedPath
    )

    return ReceiverLinkImportCandidate(
      sourceURL: inspectedURL,
      profile: profile,
      detectionSummary: L10n.text("receiver.import.detected.from_page", backend.displayName)
    )
  }

  struct FetchedPage {
    let finalURL: URL
    let body: String
  }

  static func normalizedURL(from rawInput: String) throws -> URL {
    let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ReceiverLinkImportError.emptyInput
    }

    let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
    guard let components = URLComponents(string: withScheme),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https" else {
      throw ReceiverLinkImportError.invalidURL
    }

    guard let host = components.host, !host.isEmpty else {
      throw ReceiverLinkImportError.missingHost
    }

    var normalized = components
    normalized.host = host
    normalized.fragment = nil
    normalized.query = nil

    guard let url = normalized.url else {
      throw ReceiverLinkImportError.invalidURL
    }

    return url
  }

  static func detectBackend(from url: URL, html: String) throws -> SDRBackend {
    let lowered = html.lowercased()
    let path = url.path.lowercased()

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

    throw ReceiverLinkImportError.couldNotDetectReceiver
  }

  static func normalizedProfilePath(for backend: SDRBackend, rawPath: String) -> String {
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
        let parts = trimmed.split(separator: "/").dropLast()
        if parts.isEmpty {
          return "/"
        }
        return "/" + parts.joined(separator: "/")
      }
      return normalizedPath(trimmed)
    }
  }

  static func adjustedProfile(_ profile: SDRConnectionProfile, for backend: SDRBackend) -> SDRConnectionProfile {
    var adjusted = profile
    adjusted.applyBackendChange(backend)
    adjusted.path = normalizedProfilePath(for: backend, rawPath: profile.path)
    return adjusted
  }

  private static func normalizeInspectableURL(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }

    if components.path.isEmpty {
      components.path = "/"
    }
    components.query = nil
    components.fragment = nil
    return components.url ?? url
  }

  static func normalizeInspectableURLForTests(_ url: URL) -> URL {
    normalizeInspectableURL(url)
  }

  private static func normalizedPath(_ rawPath: String) -> String {
    guard !rawPath.isEmpty else { return "/" }
    return rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
  }

  private static func fetchPage(from url: URL) async throws -> FetchedPage {
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("Listen SDR", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode) else {
      throw ReceiverLinkImportError.unsupportedURL
    }

    return FetchedPage(
      finalURL: httpResponse.url ?? url,
      body: String(decoding: data, as: UTF8.self)
    )
  }

  private static func suggestedName(for url: URL, backend: SDRBackend, html: String) async -> String {
    if backend == .kiwiSDR, let kiwiName = await kiwiStatusName(for: url), !kiwiName.isEmpty {
      return kiwiName
    }

    if let title = extractHTMLTitle(from: html),
      !title.isEmpty,
      !title.localizedCaseInsensitiveContains("kiwisdr"),
      !title.localizedCaseInsensitiveContains("openwebrx"),
      !title.localizedCaseInsensitiveContains("fm-dx") {
      return title
    }

    if let host = url.host(), !host.isEmpty {
      return host
    }

    return L10n.text("receiver.import.default_name")
  }

  private static func kiwiStatusName(for url: URL) async -> String? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.path = "/status"
    components.query = nil
    components.fragment = nil
    guard let statusURL = components.url else { return nil }

    do {
      var request = URLRequest(url: statusURL)
      request.timeoutInterval = 8
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode) else {
        return nil
      }
      let body = String(decoding: data, as: UTF8.self)
      for line in body.split(separator: "\n") where line.hasPrefix("name=") {
        return String(line.dropFirst("name=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    } catch {
      return nil
    }

    return nil
  }

  private static func extractHTMLTitle(from html: String) -> String? {
    let pattern = "(?is)<title[^>]*>(.*?)</title>"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

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
}
