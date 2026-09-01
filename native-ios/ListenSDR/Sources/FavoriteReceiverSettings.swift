import Foundation

/// Ustawienia odbiornika przechowywane razem z ulubionym wpisem.
struct FavoriteReceiverSettings: Codable, Hashable {
  let frequencyHz: Int
  let mode: DemodulationMode
  let tuneStepHz: Int
  let preferredTuneStepHz: Int
  let tuneStepPreferenceMode: TuneStepPreferenceMode
  let rfGain: Double
  let agcEnabled: Bool
  let imsEnabled: Bool
  let noiseReductionEnabled: Bool
  let squelchEnabled: Bool
  let openWebRXSquelchLevel: Int
  let kiwiSquelchThreshold: Int
  let kiwiNoiseBlankerAlgorithm: KiwiNoiseBlankerAlgorithm
  let kiwiNoiseBlankerGate: Int
  let kiwiNoiseBlankerThreshold: Int
  let kiwiNoiseBlankerWildThreshold: Double
  let kiwiNoiseBlankerWildTaps: Int
  let kiwiNoiseBlankerWildImpulseSamples: Int
  let kiwiNoiseFilterAlgorithm: KiwiNoiseFilterAlgorithm
  let kiwiDenoiseEnabled: Bool
  let kiwiAutonotchEnabled: Bool
  let kiwiPassbandsByMode: [String: ReceiverBandpass]
  let kiwiWaterfallSpeed: Int
  let kiwiWaterfallWindowFunction: Int
  let kiwiWaterfallInterpolation: Int
  let kiwiWaterfallCICCompensation: Bool
  let kiwiWaterfallZoom: Int
  let kiwiWaterfallPanOffsetBins: Int
  let kiwiWaterfallMinDB: Int
  let kiwiWaterfallMaxDB: Int
  let fmdxAudioMode: String?
  let fmdxAntennaID: String?
  let fmdxBandwidthID: String?
  let selectedOpenWebRXProfileID: String?

  init(
    settings: RadioSessionSettings,
    selectedOpenWebRXProfileID: String? = nil
  ) {
    frequencyHz = settings.frequencyHz
    mode = settings.mode
    tuneStepHz = settings.tuneStepHz
    preferredTuneStepHz = settings.preferredTuneStepHz
    tuneStepPreferenceMode = settings.tuneStepPreferenceMode
    rfGain = settings.rfGain
    agcEnabled = settings.agcEnabled
    imsEnabled = settings.imsEnabled
    noiseReductionEnabled = settings.noiseReductionEnabled
    squelchEnabled = settings.squelchEnabled
    openWebRXSquelchLevel = settings.openWebRXSquelchLevel
    kiwiSquelchThreshold = settings.kiwiSquelchThreshold
    kiwiNoiseBlankerAlgorithm = settings.kiwiNoiseBlankerAlgorithm
    kiwiNoiseBlankerGate = settings.kiwiNoiseBlankerGate
    kiwiNoiseBlankerThreshold = settings.kiwiNoiseBlankerThreshold
    kiwiNoiseBlankerWildThreshold = settings.kiwiNoiseBlankerWildThreshold
    kiwiNoiseBlankerWildTaps = settings.kiwiNoiseBlankerWildTaps
    kiwiNoiseBlankerWildImpulseSamples = settings.kiwiNoiseBlankerWildImpulseSamples
    kiwiNoiseFilterAlgorithm = settings.kiwiNoiseFilterAlgorithm
    kiwiDenoiseEnabled = settings.kiwiDenoiseEnabled
    kiwiAutonotchEnabled = settings.kiwiAutonotchEnabled
    kiwiPassbandsByMode = settings.kiwiPassbandsByMode
    kiwiWaterfallSpeed = settings.kiwiWaterfallSpeed
    kiwiWaterfallWindowFunction = settings.kiwiWaterfallWindowFunction
    kiwiWaterfallInterpolation = settings.kiwiWaterfallInterpolation
    kiwiWaterfallCICCompensation = settings.kiwiWaterfallCICCompensation
    kiwiWaterfallZoom = settings.kiwiWaterfallZoom
    kiwiWaterfallPanOffsetBins = settings.kiwiWaterfallPanOffsetBins
    kiwiWaterfallMinDB = settings.kiwiWaterfallMinDB
    kiwiWaterfallMaxDB = settings.kiwiWaterfallMaxDB
    fmdxAudioMode = settings.fmdxAudioMode.rawValue
    fmdxAntennaID = settings.fmdxAntennaID
    fmdxBandwidthID = settings.fmdxBandwidthID
    self.selectedOpenWebRXProfileID = selectedOpenWebRXProfileID
  }

  private enum CodingKeys: String, CodingKey {
    case frequencyHz
    case mode
    case tuneStepHz
    case preferredTuneStepHz
    case tuneStepPreferenceMode
    case rfGain
    case agcEnabled
    case imsEnabled
    case noiseReductionEnabled
    case squelchEnabled
    case openWebRXSquelchLevel
    case kiwiSquelchThreshold
    case kiwiNoiseBlankerAlgorithm
    case kiwiNoiseBlankerGate
    case kiwiNoiseBlankerThreshold
    case kiwiNoiseBlankerWildThreshold
    case kiwiNoiseBlankerWildTaps
    case kiwiNoiseBlankerWildImpulseSamples
    case kiwiNoiseFilterAlgorithm
    case kiwiDenoiseEnabled
    case kiwiAutonotchEnabled
    case kiwiPassbandsByMode
    case kiwiWaterfallSpeed
    case kiwiWaterfallWindowFunction
    case kiwiWaterfallInterpolation
    case kiwiWaterfallCICCompensation
    case kiwiWaterfallZoom
    case kiwiWaterfallPanOffsetBins
    case kiwiWaterfallMinDB
    case kiwiWaterfallMaxDB
    case fmdxAudioMode
    case fmdxAntennaID
    case fmdxBandwidthID
    case selectedOpenWebRXProfileID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = FavoriteReceiverSettings(settings: .default)

    func decode<T: Decodable>(
      _ type: T.Type,
      forKey key: CodingKeys,
      fallback: T
    ) -> T {
      do {
        return try container.decodeIfPresent(type, forKey: key) ?? fallback
      } catch {
        return fallback
      }
    }

    frequencyHz = decode(Int.self, forKey: .frequencyHz, fallback: defaults.frequencyHz)
    mode = decode(DemodulationMode.self, forKey: .mode, fallback: defaults.mode)
    tuneStepHz = decode(Int.self, forKey: .tuneStepHz, fallback: defaults.tuneStepHz)
    preferredTuneStepHz = decode(Int.self, forKey: .preferredTuneStepHz, fallback: defaults.preferredTuneStepHz)
    tuneStepPreferenceMode = decode(
      TuneStepPreferenceMode.self,
      forKey: .tuneStepPreferenceMode,
      fallback: defaults.tuneStepPreferenceMode
    )
    rfGain = decode(Double.self, forKey: .rfGain, fallback: defaults.rfGain)
    agcEnabled = decode(Bool.self, forKey: .agcEnabled, fallback: defaults.agcEnabled)
    imsEnabled = decode(Bool.self, forKey: .imsEnabled, fallback: defaults.imsEnabled)
    noiseReductionEnabled = decode(
      Bool.self,
      forKey: .noiseReductionEnabled,
      fallback: defaults.noiseReductionEnabled
    )
    squelchEnabled = decode(Bool.self, forKey: .squelchEnabled, fallback: defaults.squelchEnabled)
    openWebRXSquelchLevel = decode(
      Int.self,
      forKey: .openWebRXSquelchLevel,
      fallback: defaults.openWebRXSquelchLevel
    )
    kiwiSquelchThreshold = decode(
      Int.self,
      forKey: .kiwiSquelchThreshold,
      fallback: defaults.kiwiSquelchThreshold
    )
    kiwiNoiseBlankerAlgorithm = decode(
      KiwiNoiseBlankerAlgorithm.self,
      forKey: .kiwiNoiseBlankerAlgorithm,
      fallback: defaults.kiwiNoiseBlankerAlgorithm
    )
    kiwiNoiseBlankerGate = decode(
      Int.self,
      forKey: .kiwiNoiseBlankerGate,
      fallback: defaults.kiwiNoiseBlankerGate
    )
    kiwiNoiseBlankerThreshold = decode(
      Int.self,
      forKey: .kiwiNoiseBlankerThreshold,
      fallback: defaults.kiwiNoiseBlankerThreshold
    )
    kiwiNoiseBlankerWildThreshold = decode(
      Double.self,
      forKey: .kiwiNoiseBlankerWildThreshold,
      fallback: defaults.kiwiNoiseBlankerWildThreshold
    )
    kiwiNoiseBlankerWildTaps = decode(
      Int.self,
      forKey: .kiwiNoiseBlankerWildTaps,
      fallback: defaults.kiwiNoiseBlankerWildTaps
    )
    kiwiNoiseBlankerWildImpulseSamples = decode(
      Int.self,
      forKey: .kiwiNoiseBlankerWildImpulseSamples,
      fallback: defaults.kiwiNoiseBlankerWildImpulseSamples
    )
    kiwiNoiseFilterAlgorithm = decode(
      KiwiNoiseFilterAlgorithm.self,
      forKey: .kiwiNoiseFilterAlgorithm,
      fallback: defaults.kiwiNoiseFilterAlgorithm
    )
    kiwiDenoiseEnabled = decode(
      Bool.self,
      forKey: .kiwiDenoiseEnabled,
      fallback: defaults.kiwiDenoiseEnabled
    )
    kiwiAutonotchEnabled = decode(
      Bool.self,
      forKey: .kiwiAutonotchEnabled,
      fallback: defaults.kiwiAutonotchEnabled
    )
    kiwiPassbandsByMode = decode(
      [String: ReceiverBandpass].self,
      forKey: .kiwiPassbandsByMode,
      fallback: defaults.kiwiPassbandsByMode
    )
    kiwiWaterfallSpeed = decode(
      Int.self,
      forKey: .kiwiWaterfallSpeed,
      fallback: defaults.kiwiWaterfallSpeed
    )
    kiwiWaterfallWindowFunction = decode(
      Int.self,
      forKey: .kiwiWaterfallWindowFunction,
      fallback: defaults.kiwiWaterfallWindowFunction
    )
    kiwiWaterfallInterpolation = decode(
      Int.self,
      forKey: .kiwiWaterfallInterpolation,
      fallback: defaults.kiwiWaterfallInterpolation
    )
    kiwiWaterfallCICCompensation = decode(
      Bool.self,
      forKey: .kiwiWaterfallCICCompensation,
      fallback: defaults.kiwiWaterfallCICCompensation
    )
    kiwiWaterfallZoom = decode(
      Int.self,
      forKey: .kiwiWaterfallZoom,
      fallback: defaults.kiwiWaterfallZoom
    )
    kiwiWaterfallPanOffsetBins = decode(
      Int.self,
      forKey: .kiwiWaterfallPanOffsetBins,
      fallback: defaults.kiwiWaterfallPanOffsetBins
    )
    kiwiWaterfallMinDB = decode(
      Int.self,
      forKey: .kiwiWaterfallMinDB,
      fallback: defaults.kiwiWaterfallMinDB
    )
    kiwiWaterfallMaxDB = decode(
      Int.self,
      forKey: .kiwiWaterfallMaxDB,
      fallback: defaults.kiwiWaterfallMaxDB
    )
    fmdxAudioMode = try? container.decode(String.self, forKey: .fmdxAudioMode)
    fmdxAntennaID = try? container.decode(String.self, forKey: .fmdxAntennaID)
    fmdxBandwidthID = try? container.decode(String.self, forKey: .fmdxBandwidthID)
    selectedOpenWebRXProfileID = try? container.decode(String.self, forKey: .selectedOpenWebRXProfileID)
  }

  func applying(
    to current: RadioSessionSettings,
    backend: SDRBackend
  ) -> RadioSessionSettings {
    var updated = current
    updated.frequencyHz = max(frequencyHz, 0)
    updated.mode = mode.normalized(for: backend)
    updated.tuneStepHz = RadioSessionSettings.normalizedTuneStep(tuneStepHz)
    updated.preferredTuneStepHz = RadioSessionSettings.normalizedTuneStep(preferredTuneStepHz)
    updated.tuneStepPreferenceMode = tuneStepPreferenceMode
    updated.rfGain = min(max(rfGain, 0), 100)
    updated.agcEnabled = agcEnabled
    updated.imsEnabled = imsEnabled
    updated.noiseReductionEnabled = noiseReductionEnabled
    updated.squelchEnabled = squelchEnabled
    updated.openWebRXSquelchLevel = RadioSessionSettings.clampedOpenWebRXSquelchLevel(openWebRXSquelchLevel)
    updated.kiwiSquelchThreshold = RadioSessionSettings.clampedKiwiSquelchThreshold(kiwiSquelchThreshold)
    updated.kiwiNoiseBlankerAlgorithm = kiwiNoiseBlankerAlgorithm
    updated.kiwiNoiseBlankerGate = RadioSessionSettings.clampedKiwiNoiseBlankerGate(kiwiNoiseBlankerGate)
    updated.kiwiNoiseBlankerThreshold = RadioSessionSettings.clampedKiwiNoiseBlankerThreshold(kiwiNoiseBlankerThreshold)
    updated.kiwiNoiseBlankerWildThreshold = RadioSessionSettings.clampedKiwiNoiseBlankerWildThreshold(kiwiNoiseBlankerWildThreshold)
    updated.kiwiNoiseBlankerWildTaps = RadioSessionSettings.clampedKiwiNoiseBlankerWildTaps(kiwiNoiseBlankerWildTaps)
    updated.kiwiNoiseBlankerWildImpulseSamples = RadioSessionSettings.clampedKiwiNoiseBlankerWildImpulseSamples(kiwiNoiseBlankerWildImpulseSamples)
    updated.kiwiNoiseFilterAlgorithm = kiwiNoiseFilterAlgorithm
    updated.kiwiDenoiseEnabled = kiwiDenoiseEnabled
    updated.kiwiAutonotchEnabled = kiwiAutonotchEnabled
    updated.kiwiPassbandsByMode = kiwiPassbandsByMode.reduce(into: [:]) { result, item in
      let (rawMode, bandpass) = item
      guard let mode = DemodulationMode(rawValue: rawMode)?.normalized(for: .kiwiSDR) else { return }
      result[mode.rawValue] = RadioSessionSettings.normalizedKiwiBandpass(
        bandpass,
        mode: mode,
        sampleRateHz: nil
      )
    }
    updated.kiwiWaterfallSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(kiwiWaterfallSpeed)
    updated.kiwiWaterfallWindowFunction = RadioSessionSettings.normalizedKiwiWaterfallWindowFunction(kiwiWaterfallWindowFunction)
    updated.kiwiWaterfallInterpolation = RadioSessionSettings.normalizedKiwiWaterfallInterpolation(kiwiWaterfallInterpolation)
    updated.kiwiWaterfallCICCompensation = kiwiWaterfallCICCompensation
    updated.kiwiWaterfallZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(kiwiWaterfallZoom)
    updated.kiwiWaterfallPanOffsetBins = RadioSessionSettings.clampedKiwiWaterfallPanOffsetBins(kiwiWaterfallPanOffsetBins)
    updated.kiwiWaterfallMinDB = RadioSessionSettings.clampedKiwiWaterfallMinDB(kiwiWaterfallMinDB)
    updated.kiwiWaterfallMaxDB = RadioSessionSettings.clampedKiwiWaterfallMaxDB(kiwiWaterfallMaxDB)
    if updated.kiwiWaterfallMaxDB <= updated.kiwiWaterfallMinDB {
      updated.kiwiWaterfallMaxDB = min(30, updated.kiwiWaterfallMinDB + 10)
    }
    if let audioMode = fmdxAudioMode.flatMap(FMDXAudioMode.init(rawValue:)) {
      updated.fmdxAudioMode = audioMode
    }
    updated.fmdxAntennaID = fmdxAntennaID
    updated.fmdxBandwidthID = fmdxBandwidthID
    return updated
  }
}
