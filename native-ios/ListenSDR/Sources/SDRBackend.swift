import Foundation

enum SDRBackend: String, Codable, CaseIterable, Identifiable {
  case kiwiSDR = "kiwi"
  case openWebRX = "openwebrx"
  case fmDxWebserver = "fmdx"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .kiwiSDR:
      return "KiwiSDR"
    case .openWebRX:
      return "OpenWebRX"
    case .fmDxWebserver:
      return "FM-DX Webserver"
    }
  }

  var defaultPort: Int {
    switch self {
    case .kiwiSDR, .openWebRX:
      return 8073
    case .fmDxWebserver:
      return 8080
    }
  }
}
