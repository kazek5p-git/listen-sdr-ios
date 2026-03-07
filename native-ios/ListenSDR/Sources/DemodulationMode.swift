import Foundation

enum DemodulationMode: String, Codable, CaseIterable, Identifiable {
  case am
  case fm
  case nfm
  case usb
  case lsb
  case cw

  var id: String { rawValue }

  var displayName: String {
    rawValue.uppercased()
  }
}
