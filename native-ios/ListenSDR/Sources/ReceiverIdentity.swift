import Foundation
import ListenSDRCore

typealias ReceiverIdentity = ListenSDRCore.ReceiverIdentity

extension ListenSDRCore.ReceiverIdentity {
  static func key(for entry: ReceiverDirectoryEntry) -> String {
    key(
      backend: entry.backend,
      host: entry.host,
      port: entry.port,
      useTLS: entry.useTLS,
      path: entry.path
    )
  }
}
