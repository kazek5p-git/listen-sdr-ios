import Foundation

public enum FMDXCapabilitiesSessionCore {
  public struct State: Equatable, Sendable {
    public let capabilities: FMDXCapabilitiesPolicyCore.Capabilities
    public let hasConfirmedSnapshot: Bool
    public let usedCachedCapabilities: Bool

    public init(
      capabilities: FMDXCapabilitiesPolicyCore.Capabilities,
      hasConfirmedSnapshot: Bool,
      usedCachedCapabilities: Bool
    ) {
      self.capabilities = capabilities
      self.hasConfirmedSnapshot = hasConfirmedSnapshot
      self.usedCachedCapabilities = usedCachedCapabilities
    }
  }

  public static func resetState() -> State {
    State(
      capabilities: .init(),
      hasConfirmedSnapshot: false,
      usedCachedCapabilities: false
    )
  }

  public static func restoredState(
    cached: FMDXCapabilitiesPolicyCore.Capabilities?
  ) -> State {
    guard let cached, FMDXCapabilitiesPolicyCore.isMeaningful(cached) else {
      return resetState()
    }

    return State(
      capabilities: cached,
      hasConfirmedSnapshot: false,
      usedCachedCapabilities: true
    )
  }

  public static func connectedState(
    resolution: FMDXCapabilitiesCacheCore.Resolution
  ) -> State {
    let usedCachedCapabilities = resolution.usedFallbackCapabilities ||
      (!resolution.primarySnapshotWasMeaningful &&
        FMDXCapabilitiesPolicyCore.isMeaningful(resolution.capabilities))

    return State(
      capabilities: resolution.capabilities,
      hasConfirmedSnapshot: resolution.primarySnapshotWasMeaningful,
      usedCachedCapabilities: usedCachedCapabilities
    )
  }
}
