public enum ConnectionMonitorCore {
  public static func pollIntervalSeconds(
    for policy: BackendRuntimePolicyCore.Policy
  ) -> Double {
    switch policy {
    case .interactive:
      return 1.3
    case .passive:
      return 2.5
    case .background:
      return 6.0
    }
  }
}
