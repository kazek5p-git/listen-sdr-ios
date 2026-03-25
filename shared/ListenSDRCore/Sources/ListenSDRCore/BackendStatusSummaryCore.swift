public enum BackendStatusSummaryCore {
  public static func normalizedBandName(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  public static func openWebRXSummary(
    frequencyHz: Int,
    mode: DemodulationMode?,
    bandName: String?
  ) -> String {
    joinedSummary(
      frequencyHz: frequencyHz,
      mode: mode,
      bandName: normalizedBandName(bandName)
    )
  }

  public static func kiwiSummary(
    frequencyHz: Int,
    mode: DemodulationMode?,
    reportedBandName: String?
  ) -> String {
    joinedSummary(
      frequencyHz: frequencyHz,
      mode: mode,
      bandName: normalizedBandName(reportedBandName) ?? SessionTuningCore.inferredKiwiBandName(for: frequencyHz)
    )
  }

  private static func joinedSummary(
    frequencyHz: Int,
    mode: DemodulationMode?,
    bandName: String?
  ) -> String {
    var parts: [String] = [FrequencyFormatter.mhzText(fromHz: frequencyHz)]
    if let mode {
      parts.append(mode.displayName)
    }
    if let bandName {
      parts.append(bandName)
    }
    return parts.joined(separator: " | ")
  }
}
