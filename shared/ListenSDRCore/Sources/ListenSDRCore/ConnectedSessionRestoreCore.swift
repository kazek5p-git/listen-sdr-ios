import Foundation

public enum ConnectedSessionRestoreAction: String, Codable, Sendable {
  case none
  case applyNow
  case deferUntilInitialTuningReady
}

public enum ConnectedSessionRestoreCore {
  public struct Status: Equatable, Sendable {
    public let hasPendingRestore: Bool
    public let initialTuningSyncStatus: InitialServerTuningSyncCore.Status

    public init(
      hasPendingRestore: Bool,
      initialTuningSyncStatus: InitialServerTuningSyncCore.Status
    ) {
      self.hasPendingRestore = hasPendingRestore
      self.initialTuningSyncStatus = initialTuningSyncStatus
    }
  }

  public static func action(status: Status) -> ConnectedSessionRestoreAction {
    guard status.hasPendingRestore else { return .none }
    return InitialServerTuningSyncCore.canApplyLocalTuning(status: status.initialTuningSyncStatus)
      ? .applyNow
      : .deferUntilInitialTuningReady
  }
}
