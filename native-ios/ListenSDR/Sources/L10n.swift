import Foundation

enum L10n {
  static func text(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }

  static func text(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String(format: format, locale: Locale.current, arguments: args)
  }
}
