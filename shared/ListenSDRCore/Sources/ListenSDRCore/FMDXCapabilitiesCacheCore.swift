import Foundation

public enum FMDXCapabilitiesCacheCore {
  public struct Resolution: Equatable, Sendable {
    public let capabilities: FMDXCapabilitiesPolicyCore.Capabilities
    public let usedFallbackCapabilities: Bool
    public let primarySnapshotWasMeaningful: Bool
    public let shouldPersistResolvedCapabilities: Bool

    public init(
      capabilities: FMDXCapabilitiesPolicyCore.Capabilities,
      usedFallbackCapabilities: Bool,
      primarySnapshotWasMeaningful: Bool,
      shouldPersistResolvedCapabilities: Bool
    ) {
      self.capabilities = capabilities
      self.usedFallbackCapabilities = usedFallbackCapabilities
      self.primarySnapshotWasMeaningful = primarySnapshotWasMeaningful
      self.shouldPersistResolvedCapabilities = shouldPersistResolvedCapabilities
    }
  }

  public static func resolve(
    primary: FMDXCapabilitiesPolicyCore.Capabilities,
    fallback: FMDXCapabilitiesPolicyCore.Capabilities?
  ) -> Resolution {
    let resolved = FMDXCapabilitiesMergeCore.merged(primary: primary, fallback: fallback)
    let primarySnapshotWasMeaningful = FMDXCapabilitiesPolicyCore.isMeaningful(primary)
    let shouldPersistResolvedCapabilities = FMDXCapabilitiesPolicyCore.isMeaningful(resolved)

    return Resolution(
      capabilities: resolved,
      usedFallbackCapabilities: fallback != nil && resolved != primary,
      primarySnapshotWasMeaningful: primarySnapshotWasMeaningful,
      shouldPersistResolvedCapabilities: shouldPersistResolvedCapabilities
    )
  }
}
