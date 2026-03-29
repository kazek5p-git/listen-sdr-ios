import Foundation
import Network

enum ConnectionNetworkPolicy: String, Codable, CaseIterable, Identifiable {
  case wifiOnly
  case wifiAndCellular

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .wifiOnly:
      return L10n.text(
        "settings.connection.policy.wifi_only",
        fallback: "Wi-Fi only"
      )
    case .wifiAndCellular:
      return L10n.text(
        "settings.connection.policy.wifi_and_cellular",
        fallback: "Wi-Fi and cellular data"
      )
    }
  }

  var localizedDetail: String {
    switch self {
    case .wifiOnly:
      return L10n.text(
        "settings.connection.policy.wifi_only.detail",
        fallback: "Blocks new connections and reconnects when only mobile data is available."
      )
    case .wifiAndCellular:
      return L10n.text(
        "settings.connection.policy.wifi_and_cellular.detail",
        fallback: "Allows listening on Wi-Fi and mobile data. Mobile data usage may increase and charges may apply depending on your plan."
      )
    }
  }
}

enum ActiveConnectionTransport {
  case unavailable
  case wifi
  case cellular
  case other
}

final class ConnectionNetworkPolicyMonitor {
  static let shared = ConnectionNetworkPolicyMonitor()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "ListenSDR.ConnectionNetworkPolicyMonitor")
  private let lock = NSLock()
  private var latestPath: NWPath?

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      self?.lock.lock()
      self?.latestPath = path
      self?.lock.unlock()
    }
    monitor.start(queue: queue)
  }

  var currentTransport: ActiveConnectionTransport {
    lock.lock()
    let path = latestPath ?? monitor.currentPath
    lock.unlock()

    guard path.status == .satisfied else {
      return .unavailable
    }

    if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
      return .wifi
    }
    if path.usesInterfaceType(.cellular) {
      return .cellular
    }
    return .other
  }

  func blockedMessage(for policy: ConnectionNetworkPolicy) -> String? {
    guard policy == .wifiOnly else { return nil }
    switch currentTransport {
    case .cellular:
      return L10n.text(
        "settings.connection.policy.blocked_message",
        fallback: "Wi-Fi only is enabled. Connect to Wi-Fi or allow mobile data in Settings to start listening."
      )
    default:
      return nil
    }
  }
}
