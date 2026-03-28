import Foundation

struct StableAnnouncementCandidate<Kind: Equatable>: Equatable {
  let kind: Kind
  let text: String
}

final class StableAnnouncementGate<Kind: Equatable> {
  private struct PendingCandidate {
    let candidate: StableAnnouncementCandidate<Kind>
    let firstSeenAt: Date
  }

  private let stabilityInterval: (Kind) -> TimeInterval
  private let minimumInterval: (Kind) -> TimeInterval

  private var pending: PendingCandidate?
  private var lastAnnounced: StableAnnouncementCandidate<Kind>?
  private var lastAnnouncedAt = Date.distantPast

  init(
    stabilityInterval: @escaping (Kind) -> TimeInterval,
    minimumInterval: @escaping (Kind) -> TimeInterval
  ) {
    self.stabilityInterval = stabilityInterval
    self.minimumInterval = minimumInterval
  }

  func evaluate(
    candidate: StableAnnouncementCandidate<Kind>?,
    now: Date
  ) -> StableAnnouncementCandidate<Kind>? {
    guard let candidate else {
      pending = nil
      return nil
    }

    if pending?.candidate != candidate {
      pending = PendingCandidate(candidate: candidate, firstSeenAt: now)
      return nil
    }

    guard let pending else { return nil }
    guard now.timeIntervalSince(pending.firstSeenAt) >= stabilityInterval(candidate.kind) else { return nil }
    guard candidate != lastAnnounced else { return nil }
    guard now.timeIntervalSince(lastAnnouncedAt) >= minimumInterval(candidate.kind) else { return nil }

    lastAnnounced = candidate
    lastAnnouncedAt = now
    return candidate
  }

  func reset() {
    pending = nil
    lastAnnounced = nil
    lastAnnouncedAt = .distantPast
  }
}
