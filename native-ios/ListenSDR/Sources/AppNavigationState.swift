import Foundation

enum AppTab: Hashable {
  case receiver
  case radios
  case settings
}

@MainActor
final class AppNavigationState: ObservableObject {
  @Published var selectedTab: AppTab = .receiver
}
