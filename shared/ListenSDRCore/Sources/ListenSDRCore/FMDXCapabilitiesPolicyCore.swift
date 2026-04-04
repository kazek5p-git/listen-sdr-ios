import Foundation

public enum FMDXCapabilitiesPolicyCore {
  public struct ControlOption: Equatable, Sendable {
    public let id: String
    public let label: String
    public let legacyValue: String?

    public init(
      id: String,
      label: String? = nil,
      legacyValue: String? = nil
    ) {
      self.id = id
      self.label = label ?? id
      self.legacyValue = legacyValue
    }
  }

  public struct Capabilities: Equatable, Sendable {
    public let antennas: [ControlOption]
    public let bandwidths: [ControlOption]
    public let supportsAM: Bool
    public let supportsFilterControls: Bool
    public let supportsAGCControl: Bool
    public let requiresTunePassword: Bool
    public let lockedToAdmin: Bool

    public init(
      antennas: [ControlOption] = [],
      bandwidths: [ControlOption] = [],
      supportsAM: Bool = false,
      supportsFilterControls: Bool = false,
      supportsAGCControl: Bool = false,
      requiresTunePassword: Bool = false,
      lockedToAdmin: Bool = false
    ) {
      self.antennas = antennas
      self.bandwidths = bandwidths
      self.supportsAM = supportsAM
      self.supportsFilterControls = supportsFilterControls
      self.supportsAGCControl = supportsAGCControl
      self.requiresTunePassword = requiresTunePassword
      self.lockedToAdmin = lockedToAdmin
    }
  }

  public static func isMeaningful(_ capabilities: Capabilities) -> Bool {
    !capabilities.antennas.isEmpty ||
      !capabilities.bandwidths.isEmpty ||
      capabilities.supportsAM ||
      capabilities.supportsFilterControls ||
      capabilities.supportsAGCControl ||
      capabilities.requiresTunePassword ||
      capabilities.lockedToAdmin
  }
}
