import Foundation

enum ReceiverIdentity {
  static func key(
    backend: SDRBackend,
    host: String,
    port: Int,
    useTLS: Bool,
    path: String
  ) -> String {
    let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedPath = trimmedPath.isEmpty
      ? "/"
      : (trimmedPath.hasPrefix("/") ? trimmedPath : "/\(trimmedPath)")
    return "\(backend.rawValue)|\(useTLS ? "https" : "http")|\(normalizedHost)|\(port)|\(normalizedPath.lowercased())"
  }

  static func key(for profile: SDRConnectionProfile) -> String {
    key(
      backend: profile.backend,
      host: profile.host,
      port: profile.port,
      useTLS: profile.useTLS,
      path: profile.normalizedPath
    )
  }

  static func key(for entry: ReceiverDirectoryEntry) -> String {
    key(
      backend: entry.backend,
      host: entry.host,
      port: entry.port,
      useTLS: entry.useTLS,
      path: entry.path
    )
  }
}
