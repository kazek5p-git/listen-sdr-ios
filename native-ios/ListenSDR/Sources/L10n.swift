import Foundation

enum L10n {
  static func text(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }

  static func text(_ key: String, fallback: String) -> String {
    let localized = NSLocalizedString(key, comment: "")
    return localized == key ? fallback : localized
  }

  static func text(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String(format: format, locale: Locale.current, arguments: args)
  }

  static func text(_ key: String, fallback: String, _ args: CVarArg...) -> String {
    let format = text(key, fallback: fallback)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}
