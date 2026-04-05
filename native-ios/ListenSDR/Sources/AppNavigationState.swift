import Foundation

enum AppTab: Hashable {
  case receiver
  case radios
  case settings
}

@MainActor
final class AppNavigationState: ObservableObject {
  @Published var selectedTab: AppTab

  init(selectedTab: AppTab = .receiver) {
    self.selectedTab = selectedTab
  }

  static func preferredLaunchTab(
    profileCount: Int,
    hasRecentReceiverHistory: Bool,
    hasRecentListeningHistory: Bool
  ) -> AppTab {
    if profileCount == 0 && !hasRecentReceiverHistory && !hasRecentListeningHistory {
      return .radios
    }
    return .receiver
  }
}
