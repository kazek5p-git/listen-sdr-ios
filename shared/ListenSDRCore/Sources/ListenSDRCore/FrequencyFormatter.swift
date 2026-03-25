import Foundation

public enum FrequencyFormatter {
  public static func mhzText(fromHz value: Int) -> String {
    String(format: "%.3f MHz", Double(value) / 1_000_000.0)
  }

  public static func editableMHzText(fromHz value: Int, maxFractionDigits: Int = 5) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = max(1, maxFractionDigits)

    let mhz = Double(value) / 1_000_000.0
    if let text = formatter.string(from: NSNumber(value: mhz)) {
      return text
    }
    return String(format: "%.5f", mhz)
  }

  public static func fmDxMHzText(fromHz value: Int) -> String {
    fmDxMHzText(fromMHz: Double(value) / 1_000_000.0)
  }

  public static func fmDxMHzText(fromMHz value: Double) -> String {
    "\(fmDxLocalizedNumberText(fromMHz: value)) MHz"
  }

  public static func fmDxEntryText(fromHz value: Int) -> String {
    fmDxLocalizedNumberText(fromMHz: Double(value) / 1_000_000.0)
  }

  public static func tuneStepText(fromHz value: Int) -> String {
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

  private static func fmDxLocalizedNumberText(fromMHz value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 3

    if let text = formatter.string(from: NSNumber(value: value)) {
      return text
    }

    return String(format: "%.3f", value)
  }
}
