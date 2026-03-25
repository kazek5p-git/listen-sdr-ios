import Foundation

public enum SDRBackend: String, Codable, CaseIterable, Identifiable, Sendable {
  case kiwiSDR = "kiwi"
  case openWebRX = "openwebrx"
  case fmDxWebserver = "fmdx"

  public var id: String { rawValue }

  public var defaultPort: Int {
    defaultPort(useTLS: false)
  }

  public func defaultPort(useTLS: Bool) -> Int {
    switch self {
    case .kiwiSDR, .openWebRX:
      return 8073
    case .fmDxWebserver:
      return useTLS ? 443 : 8080
    }
  }
}
