import Foundation

protocol SDRBackendClient {
  var backend: SDRBackend { get }
  func connect(profile: SDRConnectionProfile) async throws
  func disconnect() async
  func apply(settings: RadioSessionSettings) async throws
  func consumeServerError() async -> String?
  func consumeStatusUpdate() async -> String?
  func isConnected() async -> Bool
}

extension SDRBackendClient {
  func consumeStatusUpdate() async -> String? { nil }
}

enum SDRClientError: LocalizedError {
  case invalidHost
  case invalidPort
  case invalidURL
  case notConnected
  case unsupported(String)

  var errorDescription: String? {
    switch self {
    case .invalidHost:
      return "Host is empty."
    case .invalidPort:
      return "Port must be in range 1-65535."
    case .invalidURL:
      return "Unable to build WebSocket URL."
    case .notConnected:
      return "Not connected."
    case .unsupported(let message):
      return message
    }
  }
}

private struct ReceiverBandpass {
  let lowCut: Int
  let highCut: Int
}

private func validate(profile: SDRConnectionProfile) throws -> (host: String, port: Int) {
  let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !host.isEmpty else { throw SDRClientError.invalidHost }
  guard (1...65535).contains(profile.port) else { throw SDRClientError.invalidPort }
  return (host, profile.port)
}

private func pathWithTrailingSlash(_ path: String) -> String {
  var output = path
  if !output.hasPrefix("/") {
    output = "/\(output)"
  }
  if !output.hasSuffix("/") {
    output.append("/")
  }
  return output
}

private func makeWebSocketURL(profile: SDRConnectionProfile, path: String) throws -> URL {
  let endpoint = try validate(profile: profile)
  var components = URLComponents()
  components.scheme = profile.useTLS ? "wss" : "ws"
  components.host = endpoint.host
  components.port = endpoint.port
  components.path = path

  guard let url = components.url else {
    throw SDRClientError.invalidURL
  }
  return url
}

private func makeHTTPURL(profile: SDRConnectionProfile, path: String) throws -> URL {
  let endpoint = try validate(profile: profile)
  var components = URLComponents()
  components.scheme = profile.useTLS ? "https" : "http"
  components.host = endpoint.host
  components.port = endpoint.port
  components.path = path

  guard let url = components.url else {
    throw SDRClientError.invalidURL
  }
  return url
}

private func encodeJSONString(_ payload: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: payload, options: [])
  guard let text = String(data: data, encoding: .utf8) else {
    throw SDRClientError.unsupported("Unable to encode JSON payload.")
  }
  return text
}

private func kiwiMode(from mode: DemodulationMode) -> String {
  switch mode {
  case .am:
    return "am"
  case .fm, .nfm:
    return "nbfm"
  case .usb:
    return "usb"
  case .lsb:
    return "lsb"
  case .cw:
    return "cw"
  }
}

private func kiwiBandpass(for mode: DemodulationMode) -> ReceiverBandpass {
  switch mode {
  case .am:
    return ReceiverBandpass(lowCut: -4900, highCut: 4900)
  case .fm:
    return ReceiverBandpass(lowCut: -6000, highCut: 6000)
  case .nfm:
    return ReceiverBandpass(lowCut: -3000, highCut: 3000)
  case .usb:
    return ReceiverBandpass(lowCut: 300, highCut: 2700)
  case .lsb:
    return ReceiverBandpass(lowCut: -2700, highCut: -300)
  case .cw:
    return ReceiverBandpass(lowCut: 300, highCut: 700)
  }
}

private func openWebRXMode(from mode: DemodulationMode) -> String {
  switch mode {
  case .am:
    return "am"
  case .fm:
    return "wfm"
  case .nfm:
    return "nfm"
  case .usb:
    return "usb"
  case .lsb:
    return "lsb"
  case .cw:
    return "cw"
  }
}

private func openWebRXBandpass(for mode: DemodulationMode) -> ReceiverBandpass {
  switch mode {
  case .am:
    return ReceiverBandpass(lowCut: -4900, highCut: 4900)
  case .fm:
    return ReceiverBandpass(lowCut: -75_000, highCut: 75_000)
  case .nfm:
    return ReceiverBandpass(lowCut: -6000, highCut: 6000)
  case .usb:
    return ReceiverBandpass(lowCut: 300, highCut: 2700)
  case .lsb:
    return ReceiverBandpass(lowCut: -2700, highCut: -300)
  case .cw:
    return ReceiverBandpass(lowCut: 300, highCut: 700)
  }
}

private func kiwiToken(_ raw: String) -> String {
  raw
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: " ", with: "%20")
}

private func kiwiAuthenticationErrorDescription(code: String) -> String {
  switch code {
  case "1":
    return "Bad password or all channels that do not require a password are busy."
  case "2":
    return "Receiver is still determining local interface address."
  case "3":
    return "Admin connection is not allowed from this IP address."
  case "4":
    return "No admin password set. Admin access is local network only."
  case "5":
    return "Multiple connections from the same IP are not allowed."
  case "6":
    return "Receiver database update in progress. Try again in about a minute."
  case "7":
    return "Another admin connection is already open."
  default:
    return "Authentication rejected by KiwiSDR."
  }
}

actor KiwiSDRClient: SDRBackendClient {
  let backend: SDRBackend = .kiwiSDR

  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var keepAliveTask: Task<Void, Never>?
  private var lastServerMessage: String?
  private var adpcmDecoder = KiwiIMAADPCMDecoder()
  private var sampleRateHz = 12_000

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let timestamp = Int(Date().timeIntervalSince1970)
    let path = "\(basePath)\(timestamp)/SND"
    let url = try makeWebSocketURL(profile: profile, path: path)
    log("Connecting to \(url.absoluteString)")

    let task = URLSession.shared.webSocketTask(with: url)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }
    keepAliveTask = Task { [task] in
      await self.keepAliveLoop(task: task)
    }

    try await send("SET auth t=kiwi p=\(kiwiToken(profile.password))")
    log("Authentication sent")
    let user = kiwiToken(profile.username)
    if !user.isEmpty {
      try await send("SET ident_user=\(user)")
      log("Client identity sent")
    }
    try await send("SET compression=0")
    try await send("SET keepalive")
    log("Connection initialized")
  }

  func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil

    keepAliveTask?.cancel()
    keepAliveTask = nil

    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    lastServerMessage = nil
    sampleRateHz = 12_000
    adpcmDecoder.reset()

    await MainActor.run {
      SharedAudioOutput.engine.stop()
    }
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }

    let mode = kiwiMode(from: settings.mode)
    let passband = kiwiBandpass(for: settings.mode)
    let frequencyKHz = Double(settings.frequencyHz) / 1000.0
    let formattedFrequency = String(format: "%.3f", frequencyKHz)

    try await send(
      "SET mod=\(mode) low_cut=\(passband.lowCut) high_cut=\(passband.highCut) freq=\(formattedFrequency)"
    )
    log("Applied tuning: mode=\(mode) freq=\(formattedFrequency) kHz")

    if settings.agcEnabled {
      try await send("SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50")
    } else {
      let manualGain = Int(settings.rfGain.rounded())
      try await send("SET agc=0 hang=0 thresh=-100 slope=6 decay=1000 manGain=\(manualGain)")
    }

    let squelchEnabled = settings.squelchEnabled ? 1 : 0
    let squelchThreshold = settings.squelchEnabled ? 6 : 0
    try await send("SET squelch=\(squelchEnabled) max=\(squelchThreshold)")
    log("Applied AGC/squelch settings")
  }

  func consumeServerError() async -> String? {
    defer { lastServerMessage = nil }
    return lastServerMessage
  }

  func isConnected() async -> Bool {
    socket != nil
  }

  private func send(_ message: String) async throws {
    guard let socket else { throw SDRClientError.notConnected }
    try await socket.send(.string(message))
  }

  private func receiveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          await handleInboundText(text)
        case .data(let data):
          await handleInboundData(data)
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleReceiveFailure(error)
        break
      }
    }
  }

  private func keepAliveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      if Task.isCancelled {
        return
      }

      do {
        try await task.send(.string("SET keepalive"))
      } catch {
        return
      }
    }
  }

  private func handleInboundText(_ text: String) async {
    if text.contains("badp=") || text.contains("too_busy=") || text.contains("down=") {
      lastServerMessage = text
    }
  }

  private func handleInboundData(_ data: Data) async {
    guard data.count >= 4 else { return }
    let tag = String(decoding: data.prefix(3), as: UTF8.self)
    let body = Data(data.dropFirst(3))

    switch tag {
    case "MSG":
      let payload = Data(body.dropFirst())
      guard let text = String(data: payload, encoding: .utf8) else { return }
      await handleKiwiMessage(text)

    case "SND":
      await handleKiwiAudio(body)

    default:
      break
    }
  }

  private func handleKiwiMessage(_ payload: String) async {
    let entries = payload.split(separator: " ")
    for entry in entries {
      let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = String(parts[0])
      let value = parts.count > 1 ? String(parts[1]) : nil

      switch name {
      case "audio_rate":
        if let value, let inputRate = Int(value) {
          try? await send("SET AR OK in=\(inputRate) out=44100")
        }

      case "sample_rate":
        if let value, let sampleRate = Double(value) {
          sampleRateHz = max(8000, Int(sampleRate.rounded()))
          log("Sample rate updated: \(sampleRateHz) Hz")
        }

      case "badp":
        if let value {
          lastServerMessage = kiwiAuthenticationErrorDescription(code: value)
          log(lastServerMessage ?? "Authentication rejected", severity: .error)
        } else {
          lastServerMessage = "Authentication rejected by KiwiSDR."
          log("Authentication rejected by KiwiSDR", severity: .error)
        }

      case "too_busy":
        lastServerMessage = "KiwiSDR is currently busy (all client slots are used)."
        log(lastServerMessage ?? "Server busy", severity: .warning)

      case "down":
        lastServerMessage = "KiwiSDR reports that the receiver is down."
        log(lastServerMessage ?? "Receiver down", severity: .warning)

      default:
        break
      }
    }
  }

  private func handleKiwiAudio(_ body: Data) async {
    guard body.count > 7 else { return }

    let flags = body[0]
    let isStereo = (flags & 0x08) != 0
    let isCompressed = (flags & 0x10) != 0
    let isLittleEndian = (flags & 0x80) != 0

    if isStereo {
      return
    }

    let audioBytes = Data(body.dropFirst(7))
    guard !audioBytes.isEmpty else { return }

    let pcm: [Int16]
    if isCompressed {
      pcm = adpcmDecoder.decode(audioBytes)
    } else {
      pcm = decodeInt16PCM(audioBytes, littleEndian: isLittleEndian)
    }

    let floats = int16ToFloatPCM(pcm)
    guard !floats.isEmpty else { return }

    let sampleRate = Double(sampleRateHz)
    await MainActor.run {
      SharedAudioOutput.engine.enqueueMono(samples: floats, sampleRate: sampleRate)
    }
  }

  private func handleReceiveFailure(_ error: Error) {
    lastServerMessage = error.localizedDescription
    log("Receive loop failed: \(error.localizedDescription)", severity: .error)
    keepAliveTask?.cancel()
    keepAliveTask = nil
    receiveTask = nil
    socket = nil
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "KiwiSDR",
      message: message
    )
  }
}

actor OpenWebRXClient: SDRBackendClient {
  let backend: SDRBackend = .openWebRX

  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var centerFrequencyHz: Int?
  private var lastAppliedSettings: RadioSessionSettings = .default
  private var lastServerMessage: String?
  private var outputRateHz = 12_000
  private var hdOutputRateHz = 48_000
  private var audioCompression = "none"
  private var adpcmDecoder = OpenWebRXSyncADPCMDecoder()

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let wsPath = "\(basePath)ws/"
    let url = try makeWebSocketURL(profile: profile, path: wsPath)
    log("Connecting to \(url.absoluteString)")

    let task = URLSession.shared.webSocketTask(with: url)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }

    try await send("SERVER DE CLIENT client=ListenSDR type=receiver")
    log("Handshake sent")
    try await sendJSON(
      [
        "type": "connectionproperties",
        "params": [
          "output_rate": outputRateHz,
          "hd_output_rate": hdOutputRateHz
        ]
      ]
    )
    try await sendJSON(
      [
        "type": "dspcontrol",
        "action": "start"
      ]
    )
    log("DSP start sent")
    try? await sendJSON(
      [
        "type": "dspcontrol",
        "params": [
          "audio_compression": "none"
        ]
      ]
    )
    log("Requested uncompressed audio")
  }

  func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil

    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    centerFrequencyHz = nil
    lastServerMessage = nil
    audioCompression = "none"
    outputRateHz = 12_000
    hdOutputRateHz = 48_000
    adpcmDecoder.reset()

    await MainActor.run {
      SharedAudioOutput.engine.stop()
    }
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }
    lastAppliedSettings = settings

    try await sendJSON(
      [
        "type": "dspcontrol",
        "params": openWebRXParams(from: settings)
      ]
    )
    log(
      "Applied tuning: mode=\(openWebRXMode(from: settings.mode)) freq=\(settings.frequencyHz) Hz"
    )
  }

  func consumeServerError() async -> String? {
    defer { lastServerMessage = nil }
    return lastServerMessage
  }

  func isConnected() async -> Bool {
    socket != nil
  }

  private func openWebRXParams(from settings: RadioSessionSettings) -> [String: Any] {
    let mode = openWebRXMode(from: settings.mode)
    let passband = openWebRXBandpass(for: settings.mode)
    let offset = centerFrequencyHz.map { settings.frequencyHz - $0 } ?? 0

    return [
      "mod": mode,
      "offset_freq": offset,
      "low_cut": passband.lowCut,
      "high_cut": passband.highCut,
      "squelch_level": settings.squelchEnabled ? -95 : -150
    ]
  }

  private func send(_ message: String) async throws {
    guard let socket else { throw SDRClientError.notConnected }
    try await socket.send(.string(message))
  }

  private func sendJSON(_ payload: [String: Any]) async throws {
    let text = try encodeJSONString(payload)
    try await send(text)
  }

  private func receiveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          await handleInboundText(text)
        case .data(let data):
          await handleBinaryData(data)
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleReceiveFailure(error)
        break
      }
    }
  }

  private func handleInboundText(_ text: String) async {
    if text.hasPrefix("CLIENT DE SERVER") {
      log("Handshake acknowledged by server")
      return
    }

    guard let data = text.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = parsed["type"] as? String
    else {
      return
    }

    switch type {
    case "config", "update":
      guard let value = parsed["value"] as? [String: Any] else { return }

      if let compression = value["audio_compression"] as? String {
        audioCompression = compression
        log("Audio compression: \(compression)")
      }
      if let outputRate = extractInt(value["output_rate"]) {
        outputRateHz = max(8_000, outputRate)
        log("Audio output rate: \(outputRateHz) Hz")
      }
      if let hdOutputRate = extractInt(value["hd_output_rate"]) {
        hdOutputRateHz = max(8_000, hdOutputRate)
        log("HD audio output rate: \(hdOutputRateHz) Hz")
      }

      if let centerFrequency = extractInt(value["center_freq"]) {
        let centerChanged = centerFrequency != centerFrequencyHz
        centerFrequencyHz = centerFrequency

        if centerChanged {
          try? await sendJSON(
            [
              "type": "dspcontrol",
              "params": openWebRXParams(from: lastAppliedSettings)
            ]
          )
        }
      }

    case "sdr_error", "demodulator_error":
      if let message = parsed["value"] as? String {
        lastServerMessage = message
        log("Server error: \(message)", severity: .error)
      }

    default:
      break
    }
  }

  private func handleBinaryData(_ data: Data) async {
    guard data.count > 1 else { return }

    let frameType = data[0]
    let payload = Data(data.dropFirst())

    switch frameType {
    case 2:
      await playAudio(payload, sampleRate: Double(outputRateHz))

    case 4:
      await playAudio(payload, sampleRate: Double(hdOutputRateHz))

    default:
      break
    }
  }

  private func playAudio(_ payload: Data, sampleRate: Double) async {
    guard !payload.isEmpty else { return }

    let pcm: [Int16]
    if audioCompression.lowercased() == "adpcm" {
      pcm = adpcmDecoder.decodeWithSync(payload)
    } else {
      pcm = decodeInt16PCM(payload, littleEndian: true)
    }

    let floats = int16ToFloatPCM(pcm)
    guard !floats.isEmpty else { return }

    await MainActor.run {
      SharedAudioOutput.engine.enqueueMono(samples: floats, sampleRate: sampleRate)
    }
  }

  private func extractInt(_ value: Any?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let text = value as? String, let intValue = Int(text) {
      return intValue
    }
    return nil
  }

  private func handleReceiveFailure(_ error: Error) {
    lastServerMessage = error.localizedDescription
    log("Receive loop failed: \(error.localizedDescription)", severity: .error)
    receiveTask = nil
    socket = nil
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "OpenWebRX",
      message: message
    )
  }
}

actor FMDXWebserverClient: SDRBackendClient {
  let backend: SDRBackend = .fmDxWebserver

  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var pollTask: Task<Void, Never>?
  private var lastServerMessage: String?
  private var pendingStatusUpdate: String?

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()
    try await authenticateIfNeeded(profile: profile)

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeWebSocketURL(profile: profile, path: "\(basePath)text")
    log("Connecting to \(url.absoluteString)")

    let task = URLSession.shared.webSocketTask(with: url)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }

    pollTask = Task { [profile] in
      await self.pollLoop(profile: profile)
    }

    if let tunerName = try? await fetchTunerName(profile: profile), !tunerName.isEmpty {
      pendingStatusUpdate = "Tuner: \(tunerName)"
    }
  }

  func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil

    pollTask?.cancel()
    pollTask = nil

    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    lastServerMessage = nil
    pendingStatusUpdate = nil
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }

    let frequencyKHz = max(1, settings.frequencyHz / 1000)
    try await send("T\(frequencyKHz)")

    // FM-DX exposes cEQ/iMS via Gxy command; map app DSP toggles to it.
    let eq = settings.noiseReductionEnabled ? 1 : 0
    let ims = settings.agcEnabled ? 1 : 0
    try? await send("G\(eq)\(ims)")

    if settings.mode != .fm && settings.mode != .nfm {
      pendingStatusUpdate = "FM-DX supports FM demodulation. Current mode may be ignored."
    }
  }

  func consumeServerError() async -> String? {
    defer { lastServerMessage = nil }
    return lastServerMessage
  }

  func consumeStatusUpdate() async -> String? {
    defer { pendingStatusUpdate = nil }
    return pendingStatusUpdate
  }

  func isConnected() async -> Bool {
    socket != nil
  }

  private func send(_ message: String) async throws {
    guard let socket else { throw SDRClientError.notConnected }
    try await socket.send(.string(message))
  }

  private func receiveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          await handleInboundText(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            await handleInboundText(text)
          }
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleReceiveFailure(error)
        break
      }
    }
  }

  private func pollLoop(profile: SDRConnectionProfile) async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      if Task.isCancelled {
        return
      }

      do {
        let snapshot = try await fetchAPI(profile: profile)
        updateStatus(from: snapshot)
      } catch {
        if Task.isCancelled {
          return
        }
      }
    }
  }

  private func handleInboundText(_ text: String) async {
    if text == "KICK" {
      lastServerMessage = "Access denied by FM-DX server."
      log(lastServerMessage ?? "Access denied", severity: .error)
      return
    }

    guard let data = text.data(using: .utf8),
      let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return
    }

    updateStatus(from: snapshot)
  }

  private func authenticateIfNeeded(profile: SDRConnectionProfile) async throws {
    let password = profile.password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !password.isEmpty else { return }

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)login")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(
      withJSONObject: ["password": password],
      options: []
    )

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SDRClientError.unsupported("FM-DX login returned invalid response.")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let message = extractServerMessage(from: data)
      if let message, !message.isEmpty {
        throw SDRClientError.unsupported("FM-DX login failed: \(message)")
      }
      throw SDRClientError.unsupported("FM-DX login failed. Check tune/admin password.")
    }

    log("Authenticated on FM-DX /login endpoint")
  }

  private func fetchAPI(profile: SDRConnectionProfile) async throws -> [String: Any] {
    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)api")
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw SDRClientError.unsupported("FM-DX API is unavailable.")
    }

    guard let snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SDRClientError.unsupported("FM-DX API returned invalid JSON.")
    }

    return snapshot
  }

  private func fetchTunerName(profile: SDRConnectionProfile) async throws -> String {
    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)static_data")
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ""
    }

    return (payload["tunerName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private func updateStatus(from snapshot: [String: Any]) {
    let frequencyMHz = parseDouble(snapshot["freq"])
    let signal = parseDouble(snapshot["sig"])
    let users = parseInt(snapshot["users"])
    let ps = parseString(snapshot["ps"])
    let countryISO = parseString(snapshot["country_iso"])

    var stationName: String?
    if let txInfo = snapshot["txInfo"] as? [String: Any] {
      stationName = parseString(txInfo["tx"])
    }

    var parts: [String] = []
    if let frequencyMHz {
      parts.append(String(format: "%.3f MHz", frequencyMHz))
    }
    if let stationName, !stationName.isEmpty, stationName != "?" {
      parts.append(stationName)
    }
    if let ps, !ps.isEmpty, ps != "?" {
      parts.append("PS \(ps)")
    }
    if let signal {
      parts.append(String(format: "S %.0f", signal))
    }
    if let users {
      parts.append("U \(users)")
    }
    if let countryISO, !countryISO.isEmpty, countryISO != "UN" {
      parts.append(countryISO)
    }

    let update = parts.joined(separator: " | ")
    if !update.isEmpty {
      pendingStatusUpdate = update
    }
  }

  private func extractServerMessage(from data: Data) -> String? {
    guard
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return payload["message"] as? String
  }

  private func parseString(_ value: Any?) -> String? {
    if let text = value as? String {
      return text
    }
    return nil
  }

  private func parseDouble(_ value: Any?) -> Double? {
    if let number = value as? Double {
      return number
    }
    if let number = value as? Float {
      return Double(number)
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let text = value as? String {
      return Double(text)
    }
    return nil
  }

  private func parseInt(_ value: Any?) -> Int? {
    if let number = value as? Int {
      return number
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let text = value as? String {
      return Int(text)
    }
    return nil
  }

  private func handleReceiveFailure(_ error: Error) {
    lastServerMessage = error.localizedDescription
    log("Receive loop failed: \(error.localizedDescription)", severity: .error)
    receiveTask = nil
    socket = nil
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "FM-DX",
      message: message
    )
  }
}
