import Foundation

public enum FMDXCapabilitiesMergeCore {
  public static func merged(
    primary: FMDXCapabilitiesPolicyCore.Capabilities,
    fallback: FMDXCapabilitiesPolicyCore.Capabilities?
  ) -> FMDXCapabilitiesPolicyCore.Capabilities {
    guard let fallback else {
      return primary
    }

    return FMDXCapabilitiesPolicyCore.Capabilities(
      antennas: primary.antennas.isEmpty ? fallback.antennas : primary.antennas,
      bandwidths: primary.bandwidths.isEmpty ? fallback.bandwidths : primary.bandwidths,
      supportsAM: primary.supportsAM || fallback.supportsAM,
      supportsFilterControls: primary.supportsFilterControls || fallback.supportsFilterControls,
      supportsAGCControl: primary.supportsAGCControl || fallback.supportsAGCControl,
      requiresTunePassword: primary.requiresTunePassword || fallback.requiresTunePassword,
      lockedToAdmin: primary.lockedToAdmin || fallback.lockedToAdmin
    )
  }
}
