import Foundation

enum SDRBackend: String, Codable, CaseIterable, Identifiable {
  case kiwiSDR = "kiwi"
  case openWebRX = "openwebrx"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .kiwiSDR:
      return "KiwiSDR"
    case .openWebRX:
      return "OpenWebRX"
    }
  }

  var defaultPort: Int {
    8073
  }
}
