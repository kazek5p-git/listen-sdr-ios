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
  struct SessionSnapshot {
    let state: String
    let statusText: String
    let backendStatusText: String?
    let lastError: String?
    let audioMuted: Bool
    let audioVolumePercent: Int
  }

  struct AudioOutputSnapshot {
    let outputSampleRateHz: Int
    let lastInputSampleRateHz: Int?
    let queuedBuffers: Int
    let engineRunning: Bool
    let sessionConfigured: Bool
    let secondsSinceLastEnqueue: Double?
    let lastStartError: String?
  }

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
  let session: SessionSnapshot
  let audioOutput: AudioOutputSnapshot
  let receiver: ReceiverSnapshot?

  @MainActor
  static func current(
    profile: SDRConnectionProfile?,
    settings: RadioSessionSettings,
    radioSession: RadioSessionViewModel
  ) -> ListenSDRFeedbackContext {
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    let localeIdentifier = Locale.current.identifier
    let systemVersion = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    let deviceModel = hardwareIdentifier()
    let audioOutputSnapshot = SharedAudioOutput.engine.runtimeSnapshot()
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
      session: SessionSnapshot(
        state: connectionStateText(radioSession.state),
        statusText: radioSession.statusText,
        backendStatusText: radioSession.backendStatusText,
        lastError: radioSession.lastError,
        audioMuted: settings.audioMuted,
        audioVolumePercent: Int((settings.audioVolume * 100).rounded())
      ),
      audioOutput: AudioOutputSnapshot(
        outputSampleRateHz: audioOutputSnapshot.outputSampleRateHz,
        lastInputSampleRateHz: audioOutputSnapshot.lastInputSampleRateHz,
        queuedBuffers: audioOutputSnapshot.queuedBuffers,
        engineRunning: audioOutputSnapshot.engineRunning,
        sessionConfigured: audioOutputSnapshot.sessionConfigured,
        secondsSinceLastEnqueue: audioOutputSnapshot.secondsSinceLastEnqueue,
        lastStartError: audioOutputSnapshot.lastStartError
      ),
      receiver: receiver
    )
  }

  private static func connectionStateText(_ state: ConnectionState) -> String {
    switch state {
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .connected:
      return "connected"
    case .failed:
      return "failed"
    }
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
  struct SessionPayload: Encodable {
    let state: String
    let statusText: String
    let backendStatusText: String?
    let lastError: String?
    let audioMuted: Bool
    let audioVolumePercent: Int
  }

  struct AudioOutputPayload: Encodable {
    let outputSampleRateHz: Int
    let lastInputSampleRateHz: Int?
    let queuedBuffers: Int
    let engineRunning: Bool
    let sessionConfigured: Bool
    let secondsSinceLastEnqueue: Double?
    let lastStartError: String?
  }

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
  let session: SessionPayload
  let audioOutput: AudioOutputPayload
  let receiver: ReceiverPayload?
  let diagnosticsText: String?

  init(
    kind: ListenSDRFeedbackKind,
    senderName: String,
    message: String,
    context: ListenSDRFeedbackContext,
    diagnosticsText: String?
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
    session = SessionPayload(
      state: context.session.state,
      statusText: context.session.statusText,
      backendStatusText: context.session.backendStatusText,
      lastError: context.session.lastError,
      audioMuted: context.session.audioMuted,
      audioVolumePercent: context.session.audioVolumePercent
    )
    audioOutput = AudioOutputPayload(
      outputSampleRateHz: context.audioOutput.outputSampleRateHz,
      lastInputSampleRateHz: context.audioOutput.lastInputSampleRateHz,
      queuedBuffers: context.audioOutput.queuedBuffers,
      engineRunning: context.audioOutput.engineRunning,
      sessionConfigured: context.audioOutput.sessionConfigured,
      secondsSinceLastEnqueue: context.audioOutput.secondsSinceLastEnqueue,
      lastStartError: context.audioOutput.lastStartError
    )
    receiver = context.receiver.map {
      ReceiverPayload(
        name: $0.name,
        backend: $0.backend,
        endpoint: $0.endpoint,
        frequencyHz: $0.frequencyHz,
        mode: $0.mode
      )
    }
    self.diagnosticsText = diagnosticsText
  }
}

private struct ListenSDRFeedbackResponse: Decodable {
  let ok: Bool
  let error: String?
}

private struct ListenSDRFeedbackHealthResponse: Decodable {
  let ok: Bool
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
  static let endpointURL = URL(string: "https://kazpar.pl/listen-sdr-feedback/api/feedback")
  static let healthCheckURL = URL(string: "https://kazpar.pl/listen-sdr-feedback/healthz")

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
    context: ListenSDRFeedbackContext,
    diagnosticsText: String?
  ) async throws {
    guard let endpointURL else {
      throw ListenSDRFeedbackSendError.invalidEndpoint
    }

    let payload = ListenSDRFeedbackPayload(
      kind: kind,
      senderName: senderName,
      message: message,
      context: context,
      diagnosticsText: diagnosticsText
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

  static func checkHealth() async throws -> Bool {
    guard let healthCheckURL else {
      throw ListenSDRFeedbackSendError.invalidEndpoint
    }

    var request = URLRequest(url: healthCheckURL)
    request.httpMethod = "GET"

    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw ListenSDRFeedbackSendError.network
      }

      guard (200...299).contains(httpResponse.statusCode) else {
        throw ListenSDRFeedbackSendError.network
      }

      let healthResponse = try JSONDecoder().decode(ListenSDRFeedbackHealthResponse.self, from: data)
      return healthResponse.ok
    } catch let error as ListenSDRFeedbackSendError {
      throw error
    } catch {
      throw ListenSDRFeedbackSendError.network
    }
  }
}
