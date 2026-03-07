import Foundation

struct SDRConnectionProfile: Identifiable, Codable, Equatable {
  var id: UUID
  var name: String
  var backend: SDRBackend
  var host: String
  var port: Int
  var useTLS: Bool
  var path: String
  var username: String
  var password: String

  init(
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

  static func empty() -> SDRConnectionProfile {
    SDRConnectionProfile(
      name: "New receiver",
      backend: .kiwiSDR,
      host: "",
      port: SDRBackend.kiwiSDR.defaultPort,
      useTLS: false,
      path: "/"
    )
  }

  var normalizedPath: String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return "/"
    }
    return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
  }

  var endpointDescription: String {
    let scheme = useTLS ? "https" : "http"
    return "\(scheme)://\(host):\(port)\(normalizedPath)"
  }
}
