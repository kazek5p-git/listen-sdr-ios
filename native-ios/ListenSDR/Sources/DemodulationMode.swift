import Foundation

struct ReceiverBandpass: Codable, Equatable, Hashable {
  let lowCut: Int
  let highCut: Int
}

enum DemodulationMode: String, Codable, CaseIterable, Identifiable {
  case am
  case amn
  case amw
  case fm
  case nfm
  case nnfm
  case usb
  case usn
  case lsb
  case lsn
  case cw
  case cwn
  case iq
  case drm
  case sam
  case sau
  case sal
  case sas
  case qam

  var id: String { rawValue }

  var displayName: String {
    rawValue.uppercased()
  }

  static let openWebRXSupportedModes: [DemodulationMode] = [
    .am, .fm, .nfm, .usb, .lsb, .cw
  ]

  static let kiwiSupportedModes: [DemodulationMode] = [
    .am, .amn, .amw,
    .nfm, .nnfm,
    .usb, .usn,
    .lsb, .lsn,
    .cw, .cwn,
    .iq, .drm,
    .sam, .sau, .sal, .sas,
    .qam
  ]

  var isFineTuningMode: Bool {
    switch self {
    case .usb, .usn, .lsb, .lsn, .cw, .cwn:
      return true
    case .am, .amn, .amw, .fm, .nfm, .nnfm, .iq, .drm, .sam, .sau, .sal, .sas, .qam:
      return false
    }
  }

  func normalized(for backend: SDRBackend) -> DemodulationMode {
    switch backend {
    case .fmDxWebserver:
      return self == .am ? .am : .fm

    case .kiwiSDR:
      if self == .fm {
        return .nfm
      }
      if Self.kiwiSupportedModes.contains(self) {
        return self
      }
      return .am

    case .openWebRX:
      switch self {
      case .am, .fm, .nfm, .usb, .lsb, .cw:
        return self
      case .amn, .amw, .iq, .drm, .sam, .sau, .sal, .sas, .qam:
        return .am
      case .nnfm:
        return .nfm
      case .usn:
        return .usb
      case .lsn:
        return .lsb
      case .cwn:
        return .cw
      }
    }
  }

  var kiwiProtocolMode: String {
    switch normalized(for: .kiwiSDR) {
    case .am:
      return "am"
    case .amn:
      return "amn"
    case .amw:
      return "amw"
    case .fm, .nfm:
      return "nbfm"
    case .nnfm:
      return "nnfm"
    case .usb:
      return "usb"
    case .usn:
      return "usn"
    case .lsb:
      return "lsb"
    case .lsn:
      return "lsn"
    case .cw:
      return "cw"
    case .cwn:
      return "cwn"
    case .iq:
      return "iq"
    case .drm:
      return "drm"
    case .sam:
      return "sam"
    case .sau:
      return "sau"
    case .sal:
      return "sal"
    case .sas:
      return "sas"
    case .qam:
      return "qam"
    }
  }

  var kiwiDefaultBandpass: ReceiverBandpass {
    switch normalized(for: .kiwiSDR) {
    case .am:
      return ReceiverBandpass(lowCut: -4_900, highCut: 4_900)
    case .amn:
      return ReceiverBandpass(lowCut: -2_500, highCut: 2_500)
    case .amw:
      return ReceiverBandpass(lowCut: -6_000, highCut: 6_000)
    case .fm, .nfm:
      return ReceiverBandpass(lowCut: -6_000, highCut: 6_000)
    case .nnfm:
      return ReceiverBandpass(lowCut: -3_000, highCut: 3_000)
    case .usb:
      return ReceiverBandpass(lowCut: 300, highCut: 2_700)
    case .usn:
      return ReceiverBandpass(lowCut: 300, highCut: 2_400)
    case .lsb:
      return ReceiverBandpass(lowCut: -2_700, highCut: -300)
    case .lsn:
      return ReceiverBandpass(lowCut: -2_400, highCut: -300)
    case .cw:
      return ReceiverBandpass(lowCut: 300, highCut: 700)
    case .cwn:
      return ReceiverBandpass(lowCut: 470, highCut: 530)
    case .iq, .drm:
      return ReceiverBandpass(lowCut: -5_000, highCut: 5_000)
    case .sam, .sas, .qam:
      return ReceiverBandpass(lowCut: -4_900, highCut: 4_900)
    case .sau:
      return ReceiverBandpass(lowCut: -2_450, highCut: 7_350)
    case .sal:
      return ReceiverBandpass(lowCut: -7_350, highCut: 2_450)
    }
  }

  var openWebRXProtocolMode: String {
    switch normalized(for: .openWebRX) {
    case .am, .amn, .amw, .iq, .drm, .sam, .sau, .sal, .sas, .qam:
      return "am"
    case .fm:
      return "wfm"
    case .nfm, .nnfm:
      return "nfm"
    case .usb, .usn:
      return "usb"
    case .lsb, .lsn:
      return "lsb"
    case .cw, .cwn:
      return "cw"
    }
  }

  var openWebRXDefaultBandpass: ReceiverBandpass {
    switch normalized(for: .openWebRX) {
    case .am, .amn, .amw, .iq, .drm, .sam, .sau, .sal, .sas, .qam:
      return ReceiverBandpass(lowCut: -4_900, highCut: 4_900)
    case .fm:
      return ReceiverBandpass(lowCut: -75_000, highCut: 75_000)
    case .nfm, .nnfm:
      return ReceiverBandpass(lowCut: -6_000, highCut: 6_000)
    case .usb, .usn:
      return ReceiverBandpass(lowCut: 300, highCut: 2_700)
    case .lsb, .lsn:
      return ReceiverBandpass(lowCut: -2_700, highCut: -300)
    case .cw, .cwn:
      return ReceiverBandpass(lowCut: 300, highCut: 700)
    }
  }

  static func fromKiwi(_ rawValue: String?) -> DemodulationMode? {
    guard let rawValue else { return nil }
    switch rawValue.lowercased() {
    case "am":
      return .am
    case "amn":
      return .amn
    case "amw":
      return .amw
    case "fm", "wfm", "nbfm":
      return .nfm
    case "nnfm":
      return .nnfm
    case "usb":
      return .usb
    case "usn":
      return .usn
    case "lsb":
      return .lsb
    case "lsn":
      return .lsn
    case "cw":
      return .cw
    case "cwn":
      return .cwn
    case "iq":
      return .iq
    case "drm":
      return .drm
    case "sam":
      return .sam
    case "sau":
      return .sau
    case "sal":
      return .sal
    case "sas":
      return .sas
    case "qam":
      return .qam
    default:
      return nil
    }
  }

  static func fromOpenWebRX(_ rawValue: String?) -> DemodulationMode? {
    guard let rawValue else { return nil }
    switch rawValue.lowercased() {
    case "am":
      return .am
    case "fm", "wfm":
      return .fm
    case "nfm":
      return .nfm
    case "usb":
      return .usb
    case "lsb":
      return .lsb
    case "cw":
      return .cw
    default:
      return nil
    }
  }
}
