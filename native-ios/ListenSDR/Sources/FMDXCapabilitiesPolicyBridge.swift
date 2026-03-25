import Foundation
import ListenSDRCore

typealias FMDXCapabilitiesPolicyCore = ListenSDRCore.FMDXCapabilitiesPolicyCore
typealias FMDXCapabilitiesMergeCore = ListenSDRCore.FMDXCapabilitiesMergeCore
typealias FMDXCapabilitiesCacheCore = ListenSDRCore.FMDXCapabilitiesCacheCore
typealias FMDXCapabilitiesSessionCore = ListenSDRCore.FMDXCapabilitiesSessionCore

extension ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption {
  init(_ option: FMDXControlOption) {
    self.init(
      id: option.id,
      label: option.label,
      legacyValue: option.legacyValue
    )
  }
}

extension FMDXControlOption {
  init(_ option: ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption) {
    self.init(
      id: option.id,
      label: option.label,
      legacyValue: option.legacyValue
    )
  }
}

extension ListenSDRCore.FMDXCapabilitiesPolicyCore.Capabilities {
  init(_ capabilities: FMDXCapabilities) {
    self.init(
      antennas: capabilities.antennas.map(ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption.init),
      bandwidths: capabilities.bandwidths.map(ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption.init),
      supportsAM: capabilities.supportsAM,
      supportsFilterControls: capabilities.supportsFilterControls,
      supportsAGCControl: capabilities.supportsAGCControl
    )
  }
}

extension FMDXCapabilities {
  init(_ capabilities: ListenSDRCore.FMDXCapabilitiesPolicyCore.Capabilities) {
    self.init(
      antennas: capabilities.antennas.map(FMDXControlOption.init),
      bandwidths: capabilities.bandwidths.map(FMDXControlOption.init),
      supportsAM: capabilities.supportsAM,
      supportsFilterControls: capabilities.supportsFilterControls,
      supportsAGCControl: capabilities.supportsAGCControl
    )
  }
}
