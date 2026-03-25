import Foundation

public enum ReceiverIdentity {
  public static func key(
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

  public static func key(for profile: SDRConnectionProfile) -> String {
    key(
      backend: profile.backend,
      host: profile.host,
      port: profile.port,
      useTLS: profile.useTLS,
      path: profile.normalizedPath
    )
  }
}
