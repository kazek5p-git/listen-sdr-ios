import Foundation

enum FrequencyFormatter {
  static func mhzText(fromHz value: Int) -> String {
    String(format: "%.3f MHz", Double(value) / 1_000_000.0)
  }
}
