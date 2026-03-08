import Foundation
import UserNotifications

@MainActor
final class DirectoryChangeNotificationService {
  static let shared = DirectoryChangeNotificationService()

  private let center = UNUserNotificationCenter.current()
  private var authorizationRequested = false

  private init() {}

  func requestAuthorizationIfNeeded() {
    guard !authorizationRequested else { return }
    authorizationRequested = true

    Task {
      let settings = await center.notificationSettings()
      guard settings.authorizationStatus == .notDetermined else { return }

      do {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      } catch {
        Diagnostics.log(
          severity: .warning,
          category: "Directory",
          message: "Notification authorization failed: \(error.localizedDescription)"
        )
      }
    }
  }

  func notifyNewReceiversIfNeeded(groupedByBackend: [SDRBackend: [String]]) {
    guard !groupedByBackend.isEmpty else { return }

    let summary = summaryText(from: groupedByBackend)
    let content = UNMutableNotificationContent()
    content.title = L10n.text("directory.notification.title")
    content.body = L10n.text("directory.notification.body", summary)
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "directory.new-receivers.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )

    center.add(request) { error in
      if let error {
        Diagnostics.log(
          severity: .warning,
          category: "Directory",
          message: "Directory notification scheduling failed: \(error.localizedDescription)"
        )
      }
    }
  }

  private func summaryText(from groupedByBackend: [SDRBackend: [String]]) -> String {
    let order: [SDRBackend] = [.fmDxWebserver, .kiwiSDR, .openWebRX]
    let parts = order.compactMap { backend -> String? in
      guard let names = groupedByBackend[backend], !names.isEmpty else { return nil }
      let count = names.count
      let previewLimit = 3
      let preview = names.prefix(previewLimit).joined(separator: ", ")
      if count > previewLimit {
        return "\(backend.displayName) +\(count): \(preview), +\(count - previewLimit)"
      }
      return "\(backend.displayName) +\(count): \(preview)"
    }

    return parts.joined(separator: ", ")
  }
}
