import Foundation

struct OpenWebRXProfileOption: Identifiable, Hashable {
  let id: String
  let name: String
}

struct SDRServerBookmark: Identifiable, Hashable {
  let id: String
  let name: String
  let frequencyHz: Int
  let modulation: DemodulationMode?
  let source: String
}

struct SDRBandFrequency: Identifiable, Hashable {
  let id: String
  let name: String
  let frequencyHz: Int
}

struct SDRBandPlanEntry: Identifiable, Hashable {
  let id: String
  let name: String
  let lowerBoundHz: Int
  let upperBoundHz: Int
  let tags: [String]
  let frequencies: [SDRBandFrequency]

  var centerFrequencyHz: Int {
    (lowerBoundHz + upperBoundHz) / 2
  }

  var rangeText: String {
    "\(FrequencyFormatter.mhzText(fromHz: lowerBoundHz)) - \(FrequencyFormatter.mhzText(fromHz: upperBoundHz))"
  }
}

struct FMDXTxInfo: Equatable {
  let station: String?
  let erpKW: String?
  let city: String?
  let itu: String?
  let distanceKm: String?
  let azimuthDeg: String?
  let polarization: String?
  let stationPI: String?
  let regional: Bool?
}

struct FMDXTelemetry: Equatable {
  let frequencyMHz: Double?
  let signal: Double?
  let signalTop: Double?
  let users: Int?
  let isStereo: Bool?
  let isForcedStereo: Bool?
  let rdsEnabled: Bool?
  let pi: String?
  let ps: String?
  let rt0: String?
  let rt1: String?
  let pty: Int?
  let tp: Int?
  let ta: Int?
  let countryName: String?
  let countryISO: String?
  let afMHz: [Double]
  let bandwidth: String?
  let antenna: String?
  let eq: String?
  let ims: String?
  let txInfo: FMDXTxInfo?
}

struct KiwiTelemetry: Equatable {
  let rssiDBm: Double?
  let waterfallBins: [UInt8]
  let sampleRateHz: Int
}

enum BackendTelemetryEvent: Equatable {
  case openWebRXProfiles([OpenWebRXProfileOption], selectedID: String?)
  case openWebRXBookmarks([SDRServerBookmark])
  case openWebRXBandPlan([SDRBandPlanEntry])
  case fmdx(FMDXTelemetry)
  case kiwi(KiwiTelemetry)
}

enum BackendControlCommand {
  case selectOpenWebRXProfile(String)
}

extension DemodulationMode {
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
