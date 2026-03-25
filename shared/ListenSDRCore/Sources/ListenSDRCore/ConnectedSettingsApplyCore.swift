public enum ConnectedSettingsApplyCore {
  public enum Action: String, Codable, Equatable {
    case skip
    case deferUntilInitialServerTuningSyncCompletes
    case applyNow
  }

  public struct Status: Codable, Equatable {
    public let isConnected: Bool
    public let hasConnectedClient: Bool
    public let isWaitingForInitialServerTuningSync: Bool

    public init(
      isConnected: Bool,
      hasConnectedClient: Bool,
      isWaitingForInitialServerTuningSync: Bool
    ) {
      self.isConnected = isConnected
      self.hasConnectedClient = hasConnectedClient
      self.isWaitingForInitialServerTuningSync = isWaitingForInitialServerTuningSync
    }
  }

  public static func action(for status: Status) -> Action {
    guard status.isConnected, status.hasConnectedClient else { return .skip }
    if status.isWaitingForInitialServerTuningSync {
      return .deferUntilInitialServerTuningSyncCompletes
    }
    return .applyNow
  }
}
