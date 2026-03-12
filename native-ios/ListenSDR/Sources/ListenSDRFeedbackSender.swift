import Darwin
import Foundation
import UIKit

enum ListenSDRFeedbackKind: String, CaseIterable, Identifiable {
  case bug
  case suggestion

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .bug:
      return L10n.text("settings.feedback.report_bug")
    case .suggestion:
      return L10n.text("settings.feedback.send_suggestion")
    }
  }

  var localizedMessageTitle: String {
    switch self {
    case .bug:
      return L10n.text("settings.feedback.form.message.bug")
    case .suggestion:
      return L10n.text("settings.feedback.form.message.suggestion")
    }
  }
}

struct ListenSDRFeedbackContext {
  struct ReceiverSnapshot {
    let name: String
    let backend: String
    let endpoint: String
    let frequencyHz: Int
    let mode: String
  }

  let appVersion: String
  let buildNumber: String
  let localeIdentifier: String
  let systemVersion: String
  let deviceModel: String
  let voiceOverEnabled: Bool
  let receiver: ReceiverSnapshot?

  static func current(
    profile: SDRConnectionProfile?,
    settings: RadioSessionSettings
  ) -> ListenSDRFeedbackContext {
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    let localeIdentifier = Locale.current.identifier
    let systemVersion = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    let deviceModel = hardwareIdentifier()
    let receiver = profile.map {
      ReceiverSnapshot(
        name: $0.name,
        backend: $0.backend.displayName,
        endpoint: $0.endpointDescription,
        frequencyHz: settings.frequencyHz,
        mode: settings.mode.displayName
      )
    }

    return ListenSDRFeedbackContext(
      appVersion: appVersion,
      buildNumber: buildNumber,
      localeIdentifier: localeIdentifier,
      systemVersion: systemVersion,
      deviceModel: deviceModel,
      voiceOverEnabled: UIAccessibility.isVoiceOverRunning,
      receiver: receiver
    )
  }

  private static func hardwareIdentifier() -> String {
    var info = utsname()
    guard uname(&info) == 0 else { return UIDevice.current.model }

    let mirror = Mirror(reflecting: info.machine)
    let identifier = mirror.children.reduce(into: "") { result, element in
      guard let value = element.value as? Int8, value != 0 else { return }
      result.append(Character(UnicodeScalar(UInt8(value))))
    }
    return identifier.isEmpty ? UIDevice.current.model : identifier
  }
}

private struct ListenSDRFeedbackPayload: Encodable {
  struct ReceiverPayload: Encodable {
    let name: String
    let backend: String
    let endpoint: String
    let frequencyHz: Int
    let mode: String
  }

  let source: String
  let kind: String
  let senderName: String
  let message: String
  let submittedAt: String
  let appName: String
  let appVersion: String
  let buildNumber: String
  let localeIdentifier: String
  let systemVersion: String
  let deviceModel: String
  let voiceOverEnabled: Bool
  let receiver: ReceiverPayload?

  init(
    kind: ListenSDRFeedbackKind,
    senderName: String,
    message: String,
    context: ListenSDRFeedbackContext
  ) {
    source = "listen-sdr-ios"
    self.kind = kind.rawValue
    self.senderName = senderName
    self.message = message
    submittedAt = ISO8601DateFormatter().string(from: Date())
    appName = "Listen SDR"
    appVersion = context.appVersion
    buildNumber = context.buildNumber
    localeIdentifier = context.localeIdentifier
    systemVersion = context.systemVersion
    deviceModel = context.deviceModel
    voiceOverEnabled = context.voiceOverEnabled
    receiver = context.receiver.map {
      ReceiverPayload(
        name: $0.name,
        backend: $0.backend,
        endpoint: $0.endpoint,
        frequencyHz: $0.frequencyHz,
        mode: $0.mode
      )
    }
  }
}

private struct ListenSDRFeedbackResponse: Decodable {
  let ok: Bool
  let error: String?
}

enum ListenSDRFeedbackSendError: LocalizedError {
  case invalidEndpoint
  case network
  case server(String?)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint:
      return L10n.text("settings.feedback.form.error.body")
    case .network:
      return L10n.text("settings.feedback.form.error.body")
    case .server(let message):
      return message ?? L10n.text("settings.feedback.form.error.body")
    }
  }
}

enum ListenSDRFeedbackSender {
  static let endpointURL = URL(string: "http://kazpar.pl:18787/api/feedback")

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 20
    configuration.waitsForConnectivity = true
    return URLSession(configuration: configuration)
  }()

  static func send(
    kind: ListenSDRFeedbackKind,
    senderName: String,
    message: String,
    context: ListenSDRFeedbackContext
  ) async throws {
    guard let endpointURL else {
      throw ListenSDRFeedbackSendError.invalidEndpoint
    }

    let payload = ListenSDRFeedbackPayload(
      kind: kind,
      senderName: senderName,
      message: message,
      context: context
    )

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)

    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw ListenSDRFeedbackSendError.network
      }

      guard (200...299).contains(httpResponse.statusCode) else {
        let serverResponse = try? JSONDecoder().decode(ListenSDRFeedbackResponse.self, from: data)
        throw ListenSDRFeedbackSendError.server(serverResponse?.error)
      }

      if !data.isEmpty {
        let serverResponse = try? JSONDecoder().decode(ListenSDRFeedbackResponse.self, from: data)
        if serverResponse?.ok == false {
          throw ListenSDRFeedbackSendError.server(serverResponse?.error)
        }
      }
    } catch let error as ListenSDRFeedbackSendError {
      throw error
    } catch {
      throw ListenSDRFeedbackSendError.network
    }
  }
}
