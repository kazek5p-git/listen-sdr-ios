public enum RuntimeAdjustedSettingsCore {
  public struct State: Codable, Equatable {
    public let mode: DemodulationMode
    public let squelchEnabled: Bool

    public init(
      mode: DemodulationMode,
      squelchEnabled: Bool
    ) {
      self.mode = mode
      self.squelchEnabled = squelchEnabled
    }
  }

  public static func effectiveSquelchEnabled(
    storedEnabled: Bool,
    isLockedByScanner: Bool
  ) -> Bool {
    storedEnabled && !isLockedByScanner
  }

  public static func adjustedState(
    backend: SDRBackend,
    mode: DemodulationMode,
    squelchEnabled: Bool,
    isSquelchLockedByScanner: Bool
  ) -> State {
    .init(
      mode: mode.normalized(for: backend),
      squelchEnabled: effectiveSquelchEnabled(
        storedEnabled: squelchEnabled,
        isLockedByScanner: isSquelchLockedByScanner
      )
    )
  }
}
