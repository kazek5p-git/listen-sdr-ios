import Foundation
import ListenSDRCore

typealias BandTuningContext = ListenSDRCore.BandTuningContext
typealias BandTuningProfile = ListenSDRCore.BandTuningProfile
typealias BandTuningProfiles = ListenSDRCore.BandTuningProfiles
typealias FMDXQuickBand = ListenSDRCore.FMDXQuickBand
typealias FMDXBandMemory = ListenSDRCore.FMDXBandMemory
typealias FMDXSessionCore = ListenSDRCore.FMDXSessionCore
typealias SessionTuningCore = ListenSDRCore.SessionTuningCore

extension FMDXQuickBand {
  var localizedTitle: String {
    L10n.text("fmdx.subband.\(rawValue)")
  }
}
