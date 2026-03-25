import Foundation

public enum InitialServerTuningSyncCore {
  public struct Status: Equatable, Sendable {
    public let backend: SDRBackend?
    public let hasInitialServerTuningSync: Bool
    public let deadlineReached: Bool

    public init(
      backend: SDRBackend?,
      hasInitialServerTuningSync: Bool,
      deadlineReached: Bool
    ) {
      self.backend = backend
      self.hasInitialServerTuningSync = hasInitialServerTuningSync
      self.deadlineReached = deadlineReached
    }
  }

  public static func requiresInitialServerTuningSync(for backend: SDRBackend?) -> Bool {
    backend == .openWebRX || backend == .kiwiSDR
  }

  public static func initialSyncDeadlineSeconds(for backend: SDRBackend?) -> TimeInterval? {
    requiresInitialServerTuningSync(for: backend) ? 4.0 : nil
  }

  public static func canApplyLocalTuning(status: Status) -> Bool {
    guard requiresInitialServerTuningSync(for: status.backend) else { return true }
    return status.hasInitialServerTuningSync || status.deadlineReached
  }

  public static func isWaitingForInitialServerTuningSync(status: Status) -> Bool {
    !canApplyLocalTuning(status: status)
  }

  public static func shouldApplyInitialLocalFallback(status: Status) -> Bool {
    requiresInitialServerTuningSync(for: status.backend) &&
      !status.hasInitialServerTuningSync &&
      status.deadlineReached
  }
}
