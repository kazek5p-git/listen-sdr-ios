import Foundation

struct OpenWebRXProfileOption: Identifiable, Hashable, Codable {
  let id: String
  let name: String
}

struct SDRServerBookmark: Identifiable, Hashable, Codable {
  let id: String
  let name: String
  let frequencyHz: Int
  let modulation: DemodulationMode?
  let source: String
}

struct SDRBandFrequency: Identifiable, Hashable, Codable {
  let id: String
  let name: String
  let frequencyHz: Int
}

struct SDRBandPlanEntry: Identifiable, Hashable, Codable {
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

enum FMDXAudioMode: String, Equatable {
  case mono
  case stereo

  init(isStereo: Bool) {
    self = isStereo ? .stereo : .mono
  }

  var isStereo: Bool {
    self == .stereo
  }
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

extension FMDXTelemetry {
  var audioMode: FMDXAudioMode? {
    if let isForcedStereo {
      return isForcedStereo ? .mono : .stereo
    }
    guard let isStereo else { return nil }
    return FMDXAudioMode(isStereo: isStereo)
  }
}

struct KiwiTelemetry: Equatable {
  let rssiDBm: Double?
  let waterfallBins: [UInt8]
  let sampleRateHz: Int
  let passband: ReceiverBandpass?
  let bandwidthHz: Int?
  let waterfallFFTSize: Int?
  let zoomMax: Int?
}

enum BackendTelemetryEvent: Equatable {
  case openWebRXProfiles([OpenWebRXProfileOption], selectedID: String?)
  case openWebRXBookmarks([SDRServerBookmark])
  case openWebRXBandPlan([SDRBandPlanEntry])
  case openWebRXTuning(frequencyHz: Int, mode: DemodulationMode?)
  case kiwiTuning(frequencyHz: Int, mode: DemodulationMode?, bandName: String?, passband: ReceiverBandpass?)
  case fmdxCapabilities(FMDXCapabilities)
  case fmdxPresets([SDRServerBookmark])
  case fmdx(FMDXTelemetry)
  case kiwi(KiwiTelemetry)
}

enum BackendControlCommand {
  case selectOpenWebRXProfile(String)
  case setOpenWebRXSquelchLevel(Int)
  case setKiwiWaterfall(
    speed: Int,
    zoom: Int,
    minDB: Int,
    maxDB: Int,
    centerFrequencyHz: Int,
    panOffsetBins: Int,
    windowFunction: Int,
    interpolation: Int,
    cicCompensation: Bool
  )
  case setKiwiPassband(lowCut: Int, highCut: Int, frequencyHz: Int, mode: DemodulationMode)
  case setKiwiNoiseBlanker(
    algorithm: KiwiNoiseBlankerAlgorithm,
    gate: Int,
    threshold: Int,
    wildThreshold: Double,
    wildTaps: Int,
    wildImpulseSamples: Int
  )
  case setKiwiNoiseFilter(
    algorithm: KiwiNoiseFilterAlgorithm,
    denoiseEnabled: Bool,
    autonotchEnabled: Bool
  )
  case setFMDXFrequencyHz(Int)
  case setFMDXFilter(eqEnabled: Bool, imsEnabled: Bool)
  case setFMDXAGC(Bool)
  case setFMDXForcedStereo(Bool)
  case setFMDXAntenna(String)
  case setFMDXBandwidth(value: String, legacyValue: String?)
}
