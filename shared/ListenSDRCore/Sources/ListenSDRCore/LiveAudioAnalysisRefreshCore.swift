public enum LiveAudioAnalysisRefreshCore {
  public static func shouldRefresh(
    policy: BackendRuntimePolicyCore.Policy,
    elapsedSecondsSinceLastReducedActivityRefresh: Double
  ) -> Bool {
    switch policy {
    case .interactive:
      return true
    case .passive:
      return elapsedSecondsSinceLastReducedActivityRefresh >= 3
    case .background:
      return elapsedSecondsSinceLastReducedActivityRefresh >= 10
    }
  }
}
