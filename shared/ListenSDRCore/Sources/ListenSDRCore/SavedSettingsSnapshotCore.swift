public enum SavedSettingsSnapshotCore {
  public struct State: Equatable, Sendable {
    public let frequencyHz: Int
    public let dxNightModeEnabled: Bool
    public let autoFilterProfileEnabled: Bool

    public init(
      frequencyHz: Int,
      dxNightModeEnabled: Bool,
      autoFilterProfileEnabled: Bool
    ) {
      self.frequencyHz = frequencyHz
      self.dxNightModeEnabled = dxNightModeEnabled
      self.autoFilterProfileEnabled = autoFilterProfileEnabled
    }
  }

  public static func createdSnapshot(from current: State) -> State {
    State(
      frequencyHz: current.frequencyHz,
      dxNightModeEnabled: false,
      autoFilterProfileEnabled: current.autoFilterProfileEnabled
    )
  }

  public static func restoredState(
    current: State,
    snapshot: State,
    includeFrequency: Bool
  ) -> State {
    State(
      frequencyHz: includeFrequency ? snapshot.frequencyHz : current.frequencyHz,
      dxNightModeEnabled: current.dxNightModeEnabled,
      autoFilterProfileEnabled: false
    )
  }
}
