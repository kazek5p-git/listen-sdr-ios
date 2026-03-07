import Foundation

enum FrequencyFormatter {
  static func mhzText(fromHz value: Int) -> String {
    String(format: "%.3f MHz", Double(value) / 1_000_000.0)
  }

  static func tuneStepText(fromHz value: Int) -> String {
    if value >= 1_000_000 {
      if value % 1_000_000 == 0 {
        return "\(value / 1_000_000) MHz"
      }
      return String(format: "%.3f MHz", Double(value) / 1_000_000.0)
    }
    if value >= 1_000 {
      if value % 1_000 == 0 {
        return "\(value / 1_000) kHz"
      }
      return String(format: "%.3f kHz", Double(value) / 1_000.0)
    }
    return "\(value) Hz"
  }
}
