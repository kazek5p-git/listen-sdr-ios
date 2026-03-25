import Foundation

public struct SDRConnectionProfile: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var backend: SDRBackend
  public var host: String
  public var port: Int
  public var useTLS: Bool
  public var path: String
  public var username: String
  public var password: String

  public init(
    id: UUID = UUID(),
    name: String,
    backend: SDRBackend,
    host: String,
    port: Int,
    useTLS: Bool = false,
    path: String = "/",
    username: String = "",
    password: String = ""
  ) {
    self.id = id
    self.name = name
    self.backend = backend
    self.host = host
    self.port = port
    self.useTLS = useTLS
    self.path = path
    self.username = username
    self.password = password
  }

  public static func empty() -> SDRConnectionProfile {
    SDRConnectionProfile(
      name: "New receiver",
      backend: .kiwiSDR,
      host: "",
      port: SDRBackend.kiwiSDR.defaultPort,
      useTLS: false,
      path: "/"
    )
  }

  public var normalizedPath: String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "/"
    }
    return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
  }

  public var endpointDescription: String {
    let scheme = useTLS ? "https" : "http"
    return "\(scheme)://\(host):\(port)\(normalizedPath)"
  }

  public mutating func applyBackendChange(_ backend: SDRBackend) {
    self.backend = backend
    port = backend.defaultPort(useTLS: useTLS)
  }

  public mutating func applyTLSChange(_ useTLS: Bool) {
    let previousDefaultPort = backend.defaultPort(useTLS: self.useTLS)
    let nextDefaultPort = backend.defaultPort(useTLS: useTLS)
    self.useTLS = useTLS

    if port == previousDefaultPort || port == nextDefaultPort {
      port = nextDefaultPort
    }
  }
}
