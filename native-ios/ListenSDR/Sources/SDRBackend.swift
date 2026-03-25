import Foundation
import ListenSDRCore

typealias SDRBackend = ListenSDRCore.SDRBackend

extension ListenSDRCore.SDRBackend {
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
}
