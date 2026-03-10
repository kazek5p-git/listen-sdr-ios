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

struct FMDXControlOption: Identifiable, Hashable {
  let id: String
  let label: String
  let legacyValue: String?
}

struct FMDXCapabilities: Equatable {
  let antennas: [FMDXControlOption]
  let bandwidths: [FMDXControlOption]
  let supportsAM: Bool
  let supportsFilterControls: Bool
  let supportsAGCControl: Bool

  static let empty = FMDXCapabilities(
    antennas: [],
    bandwidths: [],
    supportsAM: false,
    supportsFilterControls: false,
    supportsAGCControl: false
  )
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
  let ms: Int?
  let ecc: Int?
  let rbds: Bool?
  let countryName: String?
  let countryISO: String?
  let afMHz: [Double]
  let bandwidth: String?
  let antenna: String?
  let agc: String?
  let eq: String?
  let ims: String?
  let psErrors: String?
  let rt0Errors: String?
  let rt1Errors: String?
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
  case openWebRXTuning(frequencyHz: Int, mode: DemodulationMode?)
  case kiwiTuning(frequencyHz: Int, mode: DemodulationMode?, bandName: String?)
  case fmdxCapabilities(FMDXCapabilities)
  case fmdxPresets([SDRServerBookmark])
  case fmdx(FMDXTelemetry)
  case kiwi(KiwiTelemetry)
}

enum BackendControlCommand {
  case selectOpenWebRXProfile(String)
  case setOpenWebRXSquelchLevel(Int)
  case setKiwiWaterfall(speed: Int, zoom: Int, minDB: Int, maxDB: Int, centerFrequencyHz: Int)
  case setFMDXFrequencyHz(Int)
  case setFMDXFilter(eqEnabled: Bool, imsEnabled: Bool)
  case setFMDXAGC(Bool)
  case setFMDXForcedStereo(Bool)
  case setFMDXAntenna(String)
  case setFMDXBandwidth(value: String, legacyValue: String?)
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
