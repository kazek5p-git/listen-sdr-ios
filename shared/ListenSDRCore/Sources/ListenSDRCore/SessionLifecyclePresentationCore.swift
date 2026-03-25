public enum SessionLifecyclePhase: String, Codable, CaseIterable, Sendable {
  case disconnected
  case connecting
  case connected
  case failed
}

public enum SessionLifecycleStatusKind: String, Codable, CaseIterable, Sendable {
  case disconnected
  case connectingTo
  case reconnectingTo
  case connectedTo
  case connectionFailed
  case connectionLost
}

public enum SessionLifecycleBackendStatusKind: String, Codable, CaseIterable, Sendable {
  case none
  case reconnectingWait
  case syncingTuning
}

public enum SessionLifecycleErrorKind: String, Codable, CaseIterable, Sendable {
  case none
  case providedMessage
  case reconnectExhausted
}

public struct SessionLifecyclePresentation: Codable, Equatable, Sendable {
  public let phase: SessionLifecyclePhase
  public let statusKind: SessionLifecycleStatusKind
  public let backendStatusKind: SessionLifecycleBackendStatusKind
  public let errorKind: SessionLifecycleErrorKind

  public init(
    phase: SessionLifecyclePhase,
    statusKind: SessionLifecycleStatusKind,
    backendStatusKind: SessionLifecycleBackendStatusKind,
    errorKind: SessionLifecycleErrorKind
  ) {
    self.phase = phase
    self.statusKind = statusKind
    self.backendStatusKind = backendStatusKind
    self.errorKind = errorKind
  }
}

public enum SessionLifecyclePresentationEvent: String, Codable, CaseIterable, Sendable {
  case connectRequested
  case reconnectingRequested
  case connected
  case disconnected
  case connectionFailed
  case connectionLostAfterReconnectExhausted
}

public enum SessionLifecyclePresentationCore {
  public static func presentation(
    for event: SessionLifecyclePresentationEvent,
    backend: SDRBackend? = nil
  ) -> SessionLifecyclePresentation {
    switch event {
    case .connectRequested:
      return SessionLifecyclePresentation(
        phase: .connecting,
        statusKind: .connectingTo,
        backendStatusKind: .none,
        errorKind: .none
      )

    case .reconnectingRequested:
      return SessionLifecyclePresentation(
        phase: .connecting,
        statusKind: .reconnectingTo,
        backendStatusKind: .reconnectingWait,
        errorKind: .none
      )

    case .connected:
      return SessionLifecyclePresentation(
        phase: .connected,
        statusKind: .connectedTo,
        backendStatusKind: connectedBackendStatusKind(for: backend),
        errorKind: .none
      )

    case .disconnected:
      return SessionLifecyclePresentation(
        phase: .disconnected,
        statusKind: .disconnected,
        backendStatusKind: .none,
        errorKind: .none
      )

    case .connectionFailed:
      return SessionLifecyclePresentation(
        phase: .failed,
        statusKind: .connectionFailed,
        backendStatusKind: .none,
        errorKind: .providedMessage
      )

    case .connectionLostAfterReconnectExhausted:
      return SessionLifecyclePresentation(
        phase: .failed,
        statusKind: .connectionLost,
        backendStatusKind: .none,
        errorKind: .reconnectExhausted
      )
    }
  }

  private static func connectedBackendStatusKind(
    for backend: SDRBackend?
  ) -> SessionLifecycleBackendStatusKind {
    guard let backend,
      InitialServerTuningSyncCore.requiresInitialServerTuningSync(for: backend)
    else {
      return .none
    }
    return .syncingTuning
  }
}
