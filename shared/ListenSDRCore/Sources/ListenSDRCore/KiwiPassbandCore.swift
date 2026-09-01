public enum KiwiPassbandCore {
  public static let minimumPassbandHz = 4

  public static func passbandLimitHz(sampleRateHz: Int?) -> Int {
    let halfRate = max((sampleRateHz ?? 0) / 2, 5_000)
    return max(halfRate, minimumPassbandHz)
  }

  public static func normalizedBandpass(
    _ bandpass: ReceiverBandpass,
    mode: DemodulationMode,
    sampleRateHz: Int?
  ) -> ReceiverBandpass {
    let normalizedMode = mode.normalized(for: .kiwiSDR)
    let limitHz = passbandLimitHz(sampleRateHz: sampleRateHz)
    let fallback = normalizedMode.kiwiDefaultBandpass
    var lowCut = min(max(bandpass.lowCut, -limitHz), limitHz)
    var highCut = min(max(bandpass.highCut, -limitHz), limitHz)

    if lowCut >= highCut {
      lowCut = min(max(fallback.lowCut, -limitHz), limitHz)
      highCut = min(max(fallback.highCut, -limitHz), limitHz)
    }

    if (highCut - lowCut) < minimumPassbandHz {
      let center = (lowCut + highCut) / 2
      lowCut = center - (minimumPassbandHz / 2)
      highCut = lowCut + minimumPassbandHz
      if lowCut < -limitHz {
        lowCut = -limitHz
        highCut = lowCut + minimumPassbandHz
      }
      if highCut > limitHz {
        highCut = limitHz
        lowCut = highCut - minimumPassbandHz
      }
    }

    if lowCut >= highCut {
      let fallbackLow = min(max(fallback.lowCut, -limitHz), limitHz)
      let fallbackHigh = min(max(fallback.highCut, -limitHz), limitHz)
      return ReceiverBandpass(
        lowCut: min(fallbackLow, fallbackHigh - minimumPassbandHz),
        highCut: max(fallbackHigh, fallbackLow + minimumPassbandHz)
      )
    }

    return ReceiverBandpass(lowCut: lowCut, highCut: highCut)
  }

  public static func resolvedBandpass(
    storedBandpass: ReceiverBandpass?,
    mode: DemodulationMode,
    sampleRateHz: Int?
  ) -> ReceiverBandpass {
    let normalizedMode = mode.normalized(for: .kiwiSDR)
    return normalizedBandpass(
      storedBandpass ?? normalizedMode.kiwiDefaultBandpass,
      mode: normalizedMode,
      sampleRateHz: sampleRateHz
    )
  }

  public static func adjustedBandpass(
    _ bandpass: ReceiverBandpass,
    deltaHz: Int,
    mode: DemodulationMode,
    sampleRateHz: Int?
  ) -> ReceiverBandpass {
    let normalized = normalizedBandpass(bandpass, mode: mode, sampleRateHz: sampleRateHz)
    let limitHz = passbandLimitHz(sampleRateHz: sampleRateHz)
    let targetWidth = min(
      max(normalized.highCut - normalized.lowCut + deltaHz, minimumPassbandHz),
      limitHz * 2
    )
    let centeredLowCut = (normalized.lowCut + normalized.highCut - targetWidth) / 2
    var lowCut = centeredLowCut
    var highCut = centeredLowCut + targetWidth

    if lowCut < -limitHz {
      lowCut = -limitHz
      highCut = lowCut + targetWidth
    }
    if highCut > limitHz {
      highCut = limitHz
      lowCut = highCut - targetWidth
    }

    return normalizedBandpass(
      ReceiverBandpass(lowCut: lowCut, highCut: highCut),
      mode: mode,
      sampleRateHz: sampleRateHz
    )
  }
}
