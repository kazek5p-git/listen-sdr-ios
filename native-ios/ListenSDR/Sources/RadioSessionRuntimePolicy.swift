import ListenSDRCore

struct RadioSessionRuntimePolicy {
  let foregroundActive: Bool
  let selectedTab: AppTab
  let communicationInterruptionActive: Bool

  var backendPolicy: BackendRuntimePolicy {
    BackendRuntimePolicy(
      BackendRuntimePolicyCore.policy(
        isForegroundActive: foregroundActive || communicationInterruptionActive,
        isReceiverTabSelected: selectedTab == .receiver
      )
    )
  }
}
