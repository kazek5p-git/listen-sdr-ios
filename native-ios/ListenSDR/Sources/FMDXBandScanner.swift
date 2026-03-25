import Foundation
import ListenSDRCore

typealias FMDXCustomScanSettings = ListenSDRCore.FMDXCustomScanSettings
typealias FMDXBandScanStartBehavior = ListenSDRCore.FMDXBandScanStartBehavior
typealias FMDXBandScanRangeDefinition = ListenSDRCore.FMDXBandScanRangeDefinition
typealias FMDXBandScanRangePreset = ListenSDRCore.FMDXBandScanRangePreset
typealias FMDXBandScanMode = ListenSDRCore.FMDXBandScanMode
typealias FMDXBandScanTimingProfile = ListenSDRCore.FMDXBandScanTimingProfile
typealias FMDXBandScanSequenceBuilder = ListenSDRCore.FMDXBandScanSequenceBuilder
typealias FMDXBandScanSample = ListenSDRCore.FMDXBandScanSample
typealias FMDXBandScanResult = ListenSDRCore.FMDXBandScanResult
typealias FMDXBandScanReducer = ListenSDRCore.FMDXBandScanReducer
typealias FMDXSavedScanResultMatcher = ListenSDRCore.FMDXSavedScanResultMatcher

extension FMDXBandScanRangePreset {
  var localizedTitle: String {
    L10n.text("fmdx.scanner.range.\(rawValue)")
  }
}

extension FMDXBandScanMode {
  var localizedTitle: String {
    L10n.text("fmdx.scanner.mode.\(rawValue)")
  }

  func timingProfile(
    for band: FMDXQuickBand,
    settings: RadioSessionSettings
  ) -> FMDXBandScanTimingProfile {
    timingProfile(
      for: band,
      customSettings: FMDXCustomScanSettings(
        settleSeconds: settings.fmdxCustomScanSettleSeconds,
        metadataWindowSeconds: settings.fmdxCustomScanMetadataWindowSeconds
      )
    )
  }
}
