import Foundation

public enum AutomaticReconnectCore {
  public static let retryDelayScheduleSeconds: [TimeInterval] = [1, 2, 3, 5, 8, 12]
  public static let retryWindowSeconds: TimeInterval = 75

  public static func delaySeconds(forAttemptNumber attemptNumber: Int) -> TimeInterval {
    let normalizedAttempt = max(1, attemptNumber)
    let index = min(normalizedAttempt - 1, retryDelayScheduleSeconds.count - 1)
    return retryDelayScheduleSeconds[index]
  }

  public static func shouldContinueRetrying(elapsedSeconds: TimeInterval) -> Bool {
    elapsedSeconds < retryWindowSeconds
  }
}
