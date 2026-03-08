import Foundation

enum SDRBackend: String, Codable, CaseIterable, Identifiable {
  case kiwiSDR = "kiwi"
  case openWebRX = "openwebrx"
  case fmDxWebserver = "fmdx"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .kiwiSDR:
      return L10n.text("backend.kiwi")
    case .openWebRX:
      return L10n.text("backend.openwebrx")
    case .fmDxWebserver:
      return L10n.text("backend.fmdx")
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
