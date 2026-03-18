import Foundation
import XCTest
@testable import ListenSDR

final class LiveAudioStabilityTests: XCTestCase {
  private let fallbackCandidatePool = 10
  private let connectTimeoutSeconds: TimeInterval = 45
  private let warmupSeconds: TimeInterval = 8
  private let sampleIntervalSeconds: TimeInterval = 5
  private let liveAudioEnabledDefaultsKey = "ListenSDRLiveAudioTestsEnabled"
  private let liveAudioSecondsDefaultsKey = "ListenSDRLiveAudioSecondsPerReceiver"
  private let liveAudioReceiverCountDefaultsKey = "ListenSDRLiveAudioReceiverCount"

  func testFMDXLiveAudioStability() async throws {
    try await runLiveAudioTest(for: .fmDxWebserver)
  }

  func testKiwiLiveAudioStability() async throws {
    try await runLiveAudioTest(for: .kiwiSDR)
  }

  func testOpenWebRXLiveAudioStability() async throws {
    try await runLiveAudioTest(for: .openWebRX)
  }

  private func runLiveAudioTest(for backend: SDRBackend) async throws {
    guard liveAudioTestsEnabled else {
      throw XCTSkip("Set LISTEN_SDR_LIVE_AUDIO_TESTS=1 to run live backend audio tests.")
    }

    let secondsPerReceiver = configuredSecondsPerReceiver
    let candidates = try await selectCandidates(for: backend)
    XCTAssertFalse(candidates.isEmpty, "No live candidates available for \(backend.rawValue)")

    var reports: [ReceiverAudioReport] = []
    var stableCount = 0

    for entry in candidates {
      let report = try await exercise(entry: entry, seconds: secondsPerReceiver)
      reports.append(report)
      if report.isStable(for: secondsPerReceiver, sampleIntervalSeconds: sampleIntervalSeconds) {
        stableCount += 1
      }
      if stableCount >= configuredReceiverCount {
        break
      }
    }

    let summary = BackendAudioSummary(
      backend: backend.rawValue,
      targetSessions: configuredReceiverCount,
      secondsPerReceiver: secondsPerReceiver,
      reports: reports
    )

    emitLiveAudioLog(summary.renderedText)
    persistLiveAudioSummary(summary.renderedText, backend: backend.rawValue)
    XCTAssertGreaterThanOrEqual(
      stableCount,
      min(configuredReceiverCount, candidates.count),
      "Live audio test did not establish enough stable sessions for \(backend.rawValue)."
    )
  }

  private func selectCandidates(for backend: SDRBackend) async throws -> [ReceiverDirectoryEntry] {
    let service = ReceiverDirectoryService()
    let allEntries = try await service.fetchAllEntries()
    let backendEntries = allEntries.filter { $0.backend == backend }
    guard !backendEntries.isEmpty else { return [] }

    let preferredPoolSize = max(configuredReceiverCount * 3, fallbackCandidatePool)
    let probePool = Array(backendEntries.prefix(preferredPoolSize))
    let statuses = await service.probeStatuses(for: probePool, backend: backend)

    let rankedEntries = probePool.sorted { lhs, rhs in
      let lhsStatus = statuses[lhs.id] ?? lhs.status
      let rhsStatus = statuses[rhs.id] ?? rhs.status
      if lhsStatus.sortRank != rhsStatus.sortRank {
        return lhsStatus.sortRank < rhsStatus.sortRank
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    let preferred = rankedEntries.filter {
      let status = statuses[$0.id] ?? $0.status
      return status == .available || status == .limited
    }

    if preferred.count >= configuredReceiverCount {
      return preferred
    }

    return rankedEntries
  }

  @MainActor
  private func exercise(
    entry: ReceiverDirectoryEntry,
    seconds: TimeInterval
  ) async throws -> ReceiverAudioReport {
    Diagnostics.sharedStore.clear()

    let session = RadioSessionViewModel()
    session.updateRuntimePolicy(isForegroundActive: true, selectedTab: .receiver)

    let profile = entry.makeProfile()
    let startedAt = Date()
    session.connect(to: profile)

    let connected = try await waitForConnection(on: session, timeout: connectTimeoutSeconds)
    if !connected {
      let diagnostics = Diagnostics.sharedStore.exportText()
      session.disconnect()
      try? await sleep(seconds: 1.5)
      return ReceiverAudioReport(
        name: profile.name,
        endpoint: profile.endpointDescription,
        backend: profile.backend.rawValue,
        connected: false,
        monitoredSeconds: Date().timeIntervalSince(startedAt),
        sharedMaxGapSeconds: 0,
        sharedMaxQueuedBuffers: 0,
        sharedLongGapSamples: 0,
        sharedStartErrors: diagnosticsLines(containing: "Last start error", in: diagnostics),
        fmdxMaxOutputGapSeconds: 0,
        fmdxMaxQueuedDurationSeconds: 0,
        fmdxMaxQueuedBuffers: 0,
        fmdxLongGapSamples: 0,
        fmdxTrimEvents: 0,
        reconnectAttempts: 0,
        reconnectSuccesses: 0,
        disconnectDetected: session.state != .connected,
        statusText: session.statusText,
        backendStatusText: session.backendStatusText,
        diagnosticsTail: tailDiagnostics(from: diagnostics)
      )
    }

    try? await sleep(seconds: warmupSeconds)

    var report = ReceiverAudioReport(
      name: profile.name,
      endpoint: profile.endpointDescription,
      backend: profile.backend.rawValue,
      connected: true,
      monitoredSeconds: 0,
      sharedMaxGapSeconds: 0,
      sharedMaxQueuedBuffers: 0,
      sharedLongGapSamples: 0,
      sharedStartErrors: [],
      fmdxMaxOutputGapSeconds: 0,
      fmdxMaxQueuedDurationSeconds: 0,
      fmdxMaxQueuedBuffers: 0,
      fmdxLongGapSamples: 0,
      fmdxTrimEvents: 0,
      reconnectAttempts: 0,
      reconnectSuccesses: 0,
      disconnectDetected: false,
      statusText: session.statusText,
      backendStatusText: session.backendStatusText,
      diagnosticsTail: []
    )

    let monitorStartedAt = Date()
    let deadline = monitorStartedAt.addingTimeInterval(seconds)
    while Date() < deadline {
      try? await sleep(seconds: sampleIntervalSeconds)

      let audioDiagnostics = session.audioDiagnosticsSnapshot
      let sharedSnapshot = SharedAudioOutput.engine.runtimeSnapshot()
      let fmdxSnapshot = FMDXMP3AudioPlayer.shared.runtimeSnapshot()
      report.absorb(
        audioDiagnostics: audioDiagnostics,
        sharedSnapshot: sharedSnapshot,
        fmdxSnapshot: fmdxSnapshot,
        currentState: session.state
      )

      if session.state != .connected {
        report.disconnectDetected = true
        break
      }
    }

    let diagnostics = Diagnostics.sharedStore.exportText()
    report.monitoredSeconds = Date().timeIntervalSince(monitorStartedAt)
    report.statusText = session.statusText
    report.backendStatusText = session.backendStatusText
    report.sharedStartErrors = diagnosticsLines(containing: "Last start error", in: diagnostics)
    report.diagnosticsTail = tailDiagnostics(from: diagnostics)

    session.disconnect()
    try? await sleep(seconds: 2)
    return report
  }

  @MainActor
  private func waitForConnection(
    on session: RadioSessionViewModel,
    timeout: TimeInterval
  ) async throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      switch session.state {
      case .connected:
        return true
      case .failed:
        return false
      case .connecting, .disconnected:
        break
      }
      try? await sleep(seconds: 0.25)
    }
    return false
  }

  private func tailDiagnostics(from text: String, limit: Int = 14) -> [String] {
    let lines = text
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    guard lines.count > limit else { return lines }
    return Array(lines.suffix(limit))
  }

  private func diagnosticsLines(containing fragment: String, in text: String) -> [String] {
    text
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .filter { $0.localizedCaseInsensitiveContains(fragment) }
  }

  private func sleep(seconds: TimeInterval) async throws {
    let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
    try await Task.sleep(nanoseconds: nanoseconds)
  }

  private var liveAudioTestsEnabled: Bool {
    if ProcessInfo.processInfo.environment["LISTEN_SDR_LIVE_AUDIO_TESTS"] == "1" {
      return true
    }
    return UserDefaults.standard.bool(forKey: liveAudioEnabledDefaultsKey)
  }

  private var configuredSecondsPerReceiver: TimeInterval {
    if let rawValue = ProcessInfo.processInfo.environment["LISTEN_SDR_LIVE_AUDIO_SECONDS_PER_RECEIVER"],
      let parsed = Double(rawValue),
      parsed >= 30 {
      return parsed
    }
    let defaultsValue = UserDefaults.standard.double(forKey: liveAudioSecondsDefaultsKey)
    if defaultsValue >= 30 {
      return defaultsValue
    }
    return 300
  }

  private var configuredReceiverCount: Int {
    if let rawValue = ProcessInfo.processInfo.environment["LISTEN_SDR_LIVE_AUDIO_RECEIVER_COUNT"],
      let parsed = Int(rawValue),
      parsed > 0 {
      return parsed
    }
    let defaultsValue = UserDefaults.standard.integer(forKey: liveAudioReceiverCountDefaultsKey)
    if defaultsValue > 0 {
      return defaultsValue
    }
    return 2
  }

  private func persistLiveAudioSummary(_ text: String, backend: String) {
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let fileURL = directory.appendingPathComponent("live-audio-\(backend).txt")
    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
  }
}

private func emitLiveAudioLog(_ text: String) {
  text
    .split(whereSeparator: \.isNewline)
    .map(String.init)
    .forEach { line in
      Diagnostics.log(category: "Live Audio Test", message: line)
    }
  guard let data = (text + "\n").data(using: .utf8) else { return }
  FileHandle.standardError.write(data)
}

private struct BackendAudioSummary {
  let backend: String
  let targetSessions: Int
  let secondsPerReceiver: TimeInterval
  let reports: [ReceiverAudioReport]

  var renderedText: String {
    let connectedCount = reports.filter(\.connected).count
    let stableCount = reports.filter { $0.isStable(for: secondsPerReceiver, sampleIntervalSeconds: 5) }.count
    let header = "LIVE_AUDIO_SUMMARY backend=\(backend) target_sessions=\(targetSessions) seconds_per_receiver=\(formatted(secondsPerReceiver)) attempted=\(reports.count) connected=\(connectedCount) stable=\(stableCount)"
    let details = reports.map(\.renderedText)
    return ([header] + details).joined(separator: "\n")
  }

  private func formatted(_ value: TimeInterval) -> String {
    String(format: "%.1f", value)
  }
}

private struct ReceiverAudioReport {
  let name: String
  let endpoint: String
  let backend: String
  let connected: Bool
  var monitoredSeconds: TimeInterval
  var sharedMaxGapSeconds: Double
  var sharedMaxQueuedBuffers: Int
  var sharedLongGapSamples: Int
  var sharedStartErrors: [String]
  var fmdxMaxOutputGapSeconds: Double
  var fmdxMaxQueuedDurationSeconds: Double
  var fmdxMaxQueuedBuffers: Int
  var fmdxLongGapSamples: Int
  var fmdxTrimEvents: Int
  var reconnectAttempts: Int
  var reconnectSuccesses: Int
  var disconnectDetected: Bool
  var statusText: String
  var backendStatusText: String?
  var diagnosticsTail: [String]

  mutating func absorb(
    audioDiagnostics: AudioSessionDiagnosticsSnapshot,
    sharedSnapshot: SharedAudioRuntimeSnapshot,
    fmdxSnapshot: FMDXAudioRuntimeSnapshot,
    currentState: ConnectionState
  ) {
    sharedMaxQueuedBuffers = max(sharedMaxQueuedBuffers, sharedSnapshot.queuedBuffers)
    if let enqueueGap = sharedSnapshot.secondsSinceLastEnqueue {
      sharedMaxGapSeconds = max(sharedMaxGapSeconds, enqueueGap)
      if enqueueGap >= 1.5 {
        sharedLongGapSamples += 1
      }
    }

    reconnectAttempts = max(reconnectAttempts, audioDiagnostics.automaticReconnectAttempts)
    reconnectSuccesses = max(reconnectSuccesses, audioDiagnostics.automaticReconnectSuccesses)
    if let fmdxAudio = audioDiagnostics.fmdxAudio {
      fmdxMaxOutputGapSeconds = max(fmdxMaxOutputGapSeconds, fmdxSnapshot.secondsSinceLastAudioOutput)
      fmdxMaxQueuedDurationSeconds = max(fmdxMaxQueuedDurationSeconds, fmdxSnapshot.queuedDurationSeconds)
      fmdxMaxQueuedBuffers = max(fmdxMaxQueuedBuffers, fmdxSnapshot.queuedBufferCount)
      if fmdxSnapshot.secondsSinceLastAudioOutput >= 1.5 {
        fmdxLongGapSamples += 1
      }
      fmdxTrimEvents = max(fmdxTrimEvents, fmdxAudio.latencyTrimEvents)
    }
    if currentState != .connected {
      disconnectDetected = true
    }
  }

  func isStable(for expectedSeconds: TimeInterval, sampleIntervalSeconds: TimeInterval) -> Bool {
    connected
      && !disconnectDetected
      && monitoredSeconds >= max(expectedSeconds - sampleIntervalSeconds, expectedSeconds * 0.85)
  }

  var renderedText: String {
    let backendStatus = backendStatusText ?? "none"
    let startErrorCount = sharedStartErrors.count
    let diagnosticsPreview = diagnosticsTail.isEmpty
      ? "none"
      : diagnosticsTail.joined(separator: " || ")

    return [
      "LIVE_AUDIO_RECEIVER backend=\(backend) connected=\(connected) disconnected_mid_run=\(disconnectDetected) monitored=\(formatted(monitoredSeconds))",
      "name=\(name)",
      "endpoint=\(endpoint)",
      "status=\(statusText)",
      "backend_status=\(backendStatus)",
      "shared_gap_max=\(formatted(sharedMaxGapSeconds)) shared_queue_max=\(sharedMaxQueuedBuffers) shared_long_gap_samples=\(sharedLongGapSamples) shared_start_errors=\(startErrorCount)",
      "fmdx_gap_max=\(formatted(fmdxMaxOutputGapSeconds)) fmdx_queue_max=\(formatted(fmdxMaxQueuedDurationSeconds)) fmdx_buffers_max=\(fmdxMaxQueuedBuffers) fmdx_long_gap_samples=\(fmdxLongGapSamples) fmdx_trims=\(fmdxTrimEvents)",
      "reconnect_attempts=\(reconnectAttempts) reconnect_successes=\(reconnectSuccesses)",
      "diagnostics_tail=\(diagnosticsPreview)"
    ].joined(separator: " | ")
  }

  private func formatted(_ value: TimeInterval) -> String {
    String(format: "%.2f", value)
  }
}
