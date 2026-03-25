public enum BackendRuntimePolicyCore {
  public enum Policy: String, Codable, Equatable {
    case interactive
    case passive
    case background
  }

  public static func policy(
    isForegroundActive: Bool,
    isReceiverTabSelected: Bool
  ) -> Policy {
    if isForegroundActive {
      return isReceiverTabSelected ? .interactive : .passive
    }
    return .background
  }
}
