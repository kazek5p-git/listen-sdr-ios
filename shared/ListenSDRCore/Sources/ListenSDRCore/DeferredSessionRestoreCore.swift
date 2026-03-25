import Foundation

public enum DeferredSessionRestoreCore {
  public struct Status: Equatable, Sendable {
    public let isConnected: Bool
    public let isTargetProfileConnected: Bool
    public let canApplyLocalTuning: Bool
    public let deadlineReached: Bool

    public init(
      isConnected: Bool,
      isTargetProfileConnected: Bool,
      canApplyLocalTuning: Bool,
      deadlineReached: Bool
    ) {
      self.isConnected = isConnected
      self.isTargetProfileConnected = isTargetProfileConnected
      self.canApplyLocalTuning = canApplyLocalTuning
      self.deadlineReached = deadlineReached
    }
  }

  public static let deadlineSeconds: TimeInterval = 10.0
  public static let pollIntervalSeconds: TimeInterval = 0.09

  public static func shouldApply(status: Status) -> Bool {
    status.isConnected && status.isTargetProfileConnected && status.canApplyLocalTuning
  }

  public static func shouldContinueWaiting(status: Status) -> Bool {
    !status.deadlineReached && !shouldApply(status: status)
  }
}
