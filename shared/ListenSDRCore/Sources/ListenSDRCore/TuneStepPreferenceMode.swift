import Foundation

public enum TuneStepPreferenceMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case manual
  case automatic

  public var id: String { rawValue }
}
